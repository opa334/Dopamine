#import "JBDTCPage.h"
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/util.h>

NSMutableArray<JBDTCPage *> *gTCPages = nil;

BOOL tcPagesRecover(void)
{
	NSArray *existingTCAllocations = bootInfo_getArray(@"trustcache_allocations");
	for (NSNumber *allocNum in existingTCAllocations) {
		uint64_t kaddr = [allocNum unsignedLongLongValue];
		[gTCPages addObject:[[JBDTCPage alloc] initWithKernelAddress:kaddr]];
	}
	return (BOOL)existingTCAllocations;
}

void tcPagesChanged(void)
{
	NSMutableArray *tcAllocations = [NSMutableArray new];
	for (JBDTCPage *page in gTCPages) {
		[tcAllocations addObject:@(page.kaddr)];
	}
	bootInfo_setObject(@"trustcache_allocations", tcAllocations);
}

@implementation JBDTCPage

- (instancetype)initWithKernelAddress:(uint64_t)kaddr
{
	self = [super init];
	if (self) {
		_mappedInPage = NULL;
		_kaddr = kaddr;
	}
	return self;
}

- (instancetype)initAllocateAndLink
{
	self = [super init];
	if (self) {
		_mappedInPage = NULL;
		if (![self allocateInKernel]) return nil;
		[self linkInKernel];
	}
	return self;
}

- (void)mapIn
{
	if (_mappedInPage) return;

	_mappedInPageCtx = mapInRange(_kaddr, 1, (uint8_t**)&_mappedInPage);
}

- (void)mapOut
{
	if (!_mappedInPage) return;

	mappingDestroy(_mappedInPageCtx);
	_mappedInPage = NULL;
	_mappedInPageCtx = NULL;
}

- (void)ensureMappedInAndPerform:(void (^)(void))block
{
	BOOL alreadyMappedIn = _mappedInPage != NULL;
	if (!alreadyMappedIn)
	{
		[self mapIn];
	}
	block();
	if (!alreadyMappedIn)
	{
		[self mapOut];
	}
}

- (BOOL)allocateInKernel
{
	_kaddr = kalloc(0x4000);
	if (_kaddr == 0) return NO;

	NSLog(@"allocated trust cache page at 0x%llX", _kaddr);
	
	[self ensureMappedInAndPerform:^{
		_mappedInPage->selfPtr = _kaddr + 0x10;
		uuid_generate(_mappedInPage->file.uuid);
		_mappedInPage->file.version = 1;
	}];

	[gTCPages addObject:self];
	tcPagesChanged();
	return YES;
}

- (void)linkInKernel
{
	uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
	uint64_t curTc = kread64(pmap_image4_trust_caches);
	if(curTc == 0) {
		kwrite64(pmap_image4_trust_caches, _kaddr);
	}
	else {
		uint64_t prevTc = 0;
		while (curTc != 0)
		{
			prevTc = curTc;
			curTc = kread64(curTc);
		}
		kwrite64(prevTc, _kaddr);
	}
}

- (void)unlinkInKernel
{
	__block uint64_t ourNextPtr = 0;
	[self ensureMappedInAndPerform:^{
		ourNextPtr = _mappedInPage->nextPtr;
	}];

	uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
	uint64_t curTc = kread64(pmap_image4_trust_caches);
	if (curTc == 0) {
		NSLog(@"WARNING: Tried to unlink trust cache page 0x%llX but pmap_image4_trust_caches points to 0x0", _kaddr);
		return;
	}
	else if (curTc == _kaddr) {
		kwrite64(pmap_image4_trust_caches, ourNextPtr);
	}
	else {
		uint64_t prevTc = 0;
		while (curTc != _kaddr)
		{
			if (curTc == 0) {
				NSLog(@"WARNING: Hit end of trust cache chain while trying to unlink trust cache page 0x%llX", _kaddr);
				return;
			}
			prevTc = curTc;
			curTc = kread64(curTc);
		}
		kwrite64(prevTc, ourNextPtr);
	}
}

- (void)freeInKernel
{
	if (_kaddr == 0) return;

	kfree(_kaddr, 0x4000);
	[gTCPages removeObject:self];
	_kaddr = 0;
}

- (void)unlinkAndFree
{
	[self unlinkInKernel];
	[self freeInKernel];
}

int entry_cmp(const void * vp1, const void * vp2)
{
	trustcache_entry* tc1 = (trustcache_entry*)vp1;
	trustcache_entry* tc2 = (trustcache_entry*)vp2;
	return memcmp(tc1->hash, tc2->hash, CS_CDHASH_LEN);
}

- (void)sort
{
	[self ensureMappedInAndPerform:^{
		uint32_t length = _mappedInPage->file.length;
		qsort(_mappedInPage->file.entries, length, sizeof(trustcache_entry), entry_cmp);
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
	NSLog(@"left: %u, right: %u, mid: %u", left, right, mid);
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
		// A higher order (definitely not ChatGPT) has optimized this code to be as fast as possible
		// Let's hope it works :P
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