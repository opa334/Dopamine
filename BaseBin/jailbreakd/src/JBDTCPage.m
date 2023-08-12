#import "JBDTCPage.h"
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/util.h>

NSMutableArray<JBDTCPage *> *gTCPages = nil;
NSMutableArray<NSNumber *> *gTCUnusedAllocations = nil;

extern void trustCacheListAdd(uint64_t trustCacheKaddr);
extern void trustCacheListRemove(uint64_t trustCacheKaddr);
extern int tcentryComparator(const void * vp1, const void * vp2);

BOOL tcPagesRecover(void)
{
	NSArray *existingTCAllocations = bootInfo_getArray(@"trustcache_allocations");
	for (NSNumber *allocNum in existingTCAllocations) {
		@autoreleasepool {
			uint64_t kaddr = [allocNum unsignedLongLongValue];
			[gTCPages addObject:[[JBDTCPage alloc] initWithKernelAddress:kaddr]];
		}
	}
	NSArray *existingUnusuedTCAllocations = bootInfo_getArray(@"trustcache_unused_allocations");
	if (existingUnusuedTCAllocations) {
		gTCUnusedAllocations = [existingUnusuedTCAllocations mutableCopy];
	}
	return (BOOL)existingTCAllocations;
}

void tcPagesChanged(void)
{
	NSMutableArray *tcAllocations = [NSMutableArray new];
	for (JBDTCPage *page in gTCPages) {
		@autoreleasepool {
			[tcAllocations addObject:@(page.kaddr)];
		}
	}
	bootInfo_setObject(@"trustcache_allocations", tcAllocations);
	bootInfo_setObject(@"trustcache_unused_allocations", gTCUnusedAllocations);
}

@implementation JBDTCPage

- (instancetype)initWithKernelAddress:(uint64_t)kaddr
{
	self = [super init];
	if (self) {
		_page = NULL;
		self.kaddr = kaddr;
	}
	return self;
}

- (instancetype)initAllocateAndLink
{
	self = [super init];
	if (self) {
		_page = NULL;
		self.kaddr = 0;
		if (![self allocateInKernel]) return nil;
		[self linkInKernel];
	}
	return self;
}

- (void)setKaddr:(uint64_t)kaddr
{
	_kaddr = kaddr;
	if (kaddr) {
		_page = kvtouaddr(kaddr);
	}
	else {
		_page = 0;
	}
}

- (BOOL)allocateInKernel
{
	uint64_t kaddr = 0;
	if (gTCUnusedAllocations.count) {
		kaddr = [gTCUnusedAllocations.firstObject unsignedLongLongValue];
		[gTCUnusedAllocations removeObjectAtIndex:0];
		JBLogDebug("got existing trust cache page at 0x%llX", self.kaddr);
	}
	else {
		if (kalloc(&kaddr, 0x4000) != 0) return NO;
		JBLogDebug("allocated trust cache page at 0x%llX", self.kaddr);
	}

	if (kaddr == 0) return NO;
	self.kaddr = kaddr;

	_page->nextPtr = 0;
	_page->selfPtr = kaddr + 0x10;
	_page->file.version = 1;
	uuid_generate(_page->file.uuid);
	_page->file.length = 0;

	[gTCPages addObject:self];
	tcPagesChanged();
	return YES;
}

- (void)linkInKernel
{
	trustCacheListAdd(self.kaddr);
}

- (void)unlinkInKernel
{
	trustCacheListRemove(self.kaddr);
}

- (void)freeInKernel
{
	if (self.kaddr == 0) return;

	[gTCUnusedAllocations addObject:@(self.kaddr)];
	JBLogDebug("moved trust cache page at 0x%llX to unused list", self.kaddr);
	self.kaddr = 0;

	[gTCPages removeObject:self];
	tcPagesChanged();
}

- (void)unlinkAndFree
{
	[self unlinkInKernel];
	[self freeInKernel];
}

- (void)sort
{
	qsort(_page->file.entries, _page->file.length, sizeof(trustcache_entry), tcentryComparator);
}

- (uint32_t)amountOfSlotsLeft
{
	return TC_ENTRY_COUNT_PER_PAGE - _page->file.length;
}

// Put entry at end, the caller of this is supposed to be calling "sort" after it's done adding everything desired
- (BOOL)addEntry:(trustcache_entry)entry
{
	uint32_t index = _page->file.length;
	if (index >= TC_ENTRY_COUNT_PER_PAGE) {
		return NO;
	}
	_page->file.entries[index] = entry;
	_page->file.length++;

	return YES;
}

// This method only works when the entries are sorted, so the caller needs to ensure they are
- (int64_t)_indexOfEntry:(trustcache_entry)entry
{
	trustcache_entry *entries = _page->file.entries;
	int32_t count = _page->file.length;
	int32_t left = 0;
	int32_t right = count - 1;

	while (left <= right) {
		int32_t mid = (left + right) / 2;
		int32_t cmp = memcmp(entry.hash, entries[mid].hash, CS_CDHASH_LEN);
		if (cmp == 0) {
			return mid;
		}
		if (cmp < 0) {
			right = mid - 1;
		} else {
			left = mid + 1;
		}
	}
	return -1;
}

// The idea here is to move the entry to remove to the end and then decrement length by one
// So we change it to all 0xFF's, run sort and decrement, win :D
- (BOOL)removeEntry:(trustcache_entry)entry
{
	int64_t entryIndexOrNot = [self _indexOfEntry:entry];
	if (entryIndexOrNot == -1) return NO; // Entry isn't in here, do nothing
	uint32_t entryIndex = (uint32_t)entryIndexOrNot;

	memset(_page->file.entries[entryIndex].hash, 0xFF, CS_CDHASH_LEN);
	[self sort];
	_page->file.length--;

	return YES;
}

@end