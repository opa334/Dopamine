#import "JBDTCPage.h"
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/util.h>

NSMutableArray<JBDTCPage *> *gTCPages = nil;
NSMutableArray<NSNumber *> *gTCUnusedAllocations = nil;

dispatch_queue_t gTCAccessQueue;

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
		_mappedInPage = NULL;
		_kaddr = kaddr;
		_mapRefCount = 0;
	}
	return self;
}

- (instancetype)initAllocateAndLink
{
	self = [super init];
	if (self) {
		_mappedInPage = NULL;
		_kaddr = 0;
		_mapRefCount = 0;
		if (![self allocateInKernel]) return nil;
		[self linkInKernel];
	}
	return self;
}

- (BOOL)mapIn
{
	if (!_kaddr) return NO;
	if (_mapRefCount == 0) {
		_mappedInPageCtx = mapInVirtual(_kaddr, 1, (uint8_t**)&_mappedInPage);
		JBLogDebug("mapped in page %p", _mappedInPage);
	};
	_mapRefCount++;
	return YES;
}

- (void)mapOut
{
	if (_mapRefCount == 0) {
		JBLogError("attempted to map out a map with a ref count of 0");
		abort();
	}
	_mapRefCount--;
	
	if (_mapRefCount == 0) {
		JBLogDebug("mapping out page %p", _mappedInPage);
		mappingDestroy(_mappedInPageCtx);
		_mappedInPage = NULL;
		_mappedInPageCtx = NULL;
	}
}

- (void)ensureMappedInAndPerform:(void (^)(void))block
{
	[self mapIn];
	const char *curLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
	if (!strcmp(curLabel, "com.opa334.jailbreakd.tcAccessQueue")) {
		block();
	}
	else {
		dispatch_sync(gTCAccessQueue, block);
	}
	[self mapOut];
}

- (BOOL)allocateInKernel
{
	if (gTCUnusedAllocations.count) {
		_kaddr = [gTCUnusedAllocations.firstObject unsignedLongLongValue];
		[gTCUnusedAllocations removeObjectAtIndex:0];
		JBLogDebug("got existing trust cache page at 0x%llX", _kaddr);
	}
	else {
		if (kalloc(&_kaddr, 0x4000) != 0) return NO;
		JBLogDebug("allocated trust cache page at 0x%llX", _kaddr);
	}

	if (_kaddr == 0) return NO;

	[self ensureMappedInAndPerform:^{
		_mappedInPage->nextPtr = 0;
		_mappedInPage->selfPtr = _kaddr + 0x10;

		_mappedInPage->file.version = 1;
		uuid_generate(_mappedInPage->file.uuid);
		_mappedInPage->file.length = 0;
	}];

	[gTCPages addObject:self];
	tcPagesChanged();
	return YES;
}

- (void)linkInKernel
{
	trustCacheListAdd(_kaddr);
}

- (void)unlinkInKernel
{
	trustCacheListRemove(_kaddr);
}

- (void)freeInKernel
{
	if (_kaddr == 0) return;

	[gTCUnusedAllocations addObject:@(_kaddr)];
	JBLogDebug("moved trust cache page at 0x%llX to unused list", _kaddr);
	_kaddr = 0;

	[gTCPages removeObject:self];
	tcPagesChanged();
}

- (void)unlinkAndFree
{
	dispatch_sync(gTCAccessQueue, ^{
		[self unlinkInKernel];
		[self freeInKernel];
	});
}

- (void)sort
{
	[self ensureMappedInAndPerform:^{
		uint32_t length = _mappedInPage->file.length;
		qsort(_mappedInPage->file.entries, length, sizeof(trustcache_entry), tcentryComparator);
	}];
}

- (uint32_t)amountOfSlotsLeft
{
	__block uint32_t length = 0;
	[self ensureMappedInAndPerform:^{
		length = _mappedInPage->file.length;
	}];
	return TC_ENTRY_COUNT_PER_PAGE - length;
}

// Put entry at end, the caller of this is supposed to be calling "sort" after it's done adding everything desired
- (BOOL)addEntry:(trustcache_entry)entry
{
	__block BOOL success = YES;

	[self ensureMappedInAndPerform:^{
		uint32_t index = _mappedInPage->file.length;
		if (index >= TC_ENTRY_COUNT_PER_PAGE) {
			success = NO;
			return;
		}
		_mappedInPage->file.entries[index] = entry;
		_mappedInPage->file.length++;
	}];

	return success;
}

/*

Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 367, mid: 183
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 182, mid: 91
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 90, mid: 45
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 44, mid: 22
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 21, mid: 10
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 9, mid: 4
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 3, mid: 1
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 0, mid: 0
Feb 18 03:06:35 jailbreakd[313] <Notice>: left: 0, right: 4294967295, mid: 2147483647

old code: (broken)

trustcache_entry *entries = _mappedInPage->file.entries;
uint32_t count = _mappedInPage->file.length;
uint32_t left = 0;
uint32_t right = count - 1;

register uint32_t mid, cmp, i;
while (left <= right) {
	mid = (left + right) >> 1;
	JBLogDebug("left: %u, right: %u, mid: %u", left, right, mid);
	cmp = entries[mid].hash[0] - entry.hash[0];
	
	if (cmp == 0) {
		// If the first byte of the hash matches, compare the remaining bytes
		i = 1;
		while (i < CS_CDHASH_LEN) {
			cmp = entries[mid].hash[i] - entry.hash[i];
			if (cmp) {
				break;
			}
			i++;
		}
		
		// If all bytes match, return the index
		if (i == CS_CDHASH_LEN) {
			index = mid;
			return;
		}
	}
	
	if (cmp < 0) {
		left = mid + 1;
	} else {
		right = mid - 1;
	}
}

*/

// This only works when the entries are sorted, so the caller needs to ensure they are
- (int64_t)_indexOfEntry:(trustcache_entry)entry
{
	__block int64_t index = -1;

	[self ensureMappedInAndPerform:^{
		trustcache_entry *entries = _mappedInPage->file.entries;
		int32_t count = _mappedInPage->file.length;
		int32_t left = 0;
		int32_t right = count - 1;

		while (left <= right) {
			int32_t mid = (left + right) / 2;
			int32_t cmp = memcmp(entry.hash, entries[mid].hash, CS_CDHASH_LEN);
			if (cmp == 0) {
				index = mid;
				return;
			}
			if (cmp < 0) {
				right = mid - 1;
			} else {
				left = mid + 1;
			}
		}
	}];

	return index;
}

// The idea here is to move the entry to remove to the end and then decrement length by one
// So we change it to all 0xFF's, run sort and decrement, win :D
- (BOOL)removeEntry:(trustcache_entry)entry
{
	int64_t entryIndexOrNot = [self _indexOfEntry:entry];
	if (entryIndexOrNot == -1) return NO; // Entry isn't in here, do nothing
	uint32_t entryIndex = (uint32_t)entryIndexOrNot;

	[self ensureMappedInAndPerform:^{
		trustcache_entry* entryPtr = &_mappedInPage->file.entries[entryIndex];
		memset(entryPtr->hash, 0xFF, CS_CDHASH_LEN);
		[self sort];
		_mappedInPage->file.length--;
	}];

	return YES;
}

@end