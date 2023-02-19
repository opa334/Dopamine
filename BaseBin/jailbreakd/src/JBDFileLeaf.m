#import "JBDFileLeaf.h"

extern void trustCacheAddEntry(trustcache_entry entry);
extern void trustCacheRemoveEntry(trustcache_entry entry);

@implementation JBDFileLeaf

- (instancetype)initWithName:(const char *)name parent:(OPFileNode *)parent
{
	self = [super initWithName:name parent:parent];
	if (self) {
		_cdh.count = 0;
		_cdh.h = NULL;
		_loaded = NO;
	}
	return self;
}

- (BOOL)ensureLoaded
{
	if (!_loaded) {
		_loaded = YES;
		const char *fileCPath = [self.fullPath fileSystemRepresentation];
		stat(fileCPath, &_sb);
		find_cdhash(fileCPath, &_sb, &_cdh);
		return YES;
	}
	return NO;
}

- (void)unload
{
	if (_cdh.h) {
		free(_cdh.h);
		_cdh.h = NULL;
	}
	_cdh.count = 0;
	_loaded = NO;
}

- (void)updateEntry
{
	NSString *logPath = self.fullPath;
	NSLog(@"[updateEntry %@] start", logPath);
	// Cache value before
	struct cdhashes cdh_before;
	cdh_before.count = _cdh.count;
	cdh_before.h = NULL;
	if (cdh_before.count > 0)
	{
		uint32_t size = cdh_before.count * sizeof(struct hashes);
		cdh_before.h = malloc(size);
		memcpy(cdh_before.h, _cdh.h, size);
		NSLog(@"[updateEntry %@] copied %d hashes from previous cdhashes", logPath, cdh_before.count);
	}

	// reload
	[self unload];
	[self ensureLoaded];
	NSLog(@"[updateEntry %@] reloaded", logPath);

	BOOL changed = NO;

	// First check: Did count change?
	if (!changed) {
		changed = _cdh.count != cdh_before.count;
		NSLog(@"[updateEntry %@] new count: %d, old count: %d, changed: %d", logPath, _cdh.count, cdh_before.count, changed);
	}

	// Second check: Did a hash change?
	if (!changed) {
		for (int i = 0; i < _cdh.count; i++) {
			if (memcmp(_cdh.h[i].cdhash, cdh_before.h[i].cdhash, 20) != 0) {
				changed = YES;
				break;
			}
		}
		NSLog(@"[updateEntry %@] second check through, changed: %d", logPath, changed);
	}

	// If something changed, unload the previous hashes and load the new ones
	if (changed)
	{
		for (int i = 0; i < cdh_before.count; i++) {
			trustcache_entry entry;
			memcpy(&entry.hash, &cdh_before.h[i].cdhash[0], CS_CDHASH_LEN);
			entry.hash_type = 0x2;
			entry.flags = 0x0;
			NSLog(@"[TC] Removing entry %d for %@ (Dynamic Update)", i, logPath);
			trustCacheRemoveEntry(entry);
		}

		for (int i = 0; i < _cdh.count; i++) {
			NSLog(@"[TC] Adding entry %d for %@ (Dynamic Update)", i, logPath);
			trustCacheAddEntry([self entryForHashIndex:i]);
		}
	}

	// Clean up
	if (cdh_before.h != NULL) {
		free(cdh_before.h);
	}
}

- (void)createReceived
{
	[super createReceived];
	[self updateEntry];
}

- (void)modifyReceived
{
	[super modifyReceived];
	[self updateEntry];
}

- (void)deleteReceived
{
	[super deleteReceived];
	for (int i = 0; i < _cdh.count; i++) {
		NSLog(@"[TC] Removing entry %d for %@ (Dynamic Update)", i, self.fullPath);
		trustCacheRemoveEntry([self entryForHashIndex:i]);
	}	
	_cdh.count = 0;
}

- (uint64_t)hashCount
{
	return _cdh.count;
}

- (trustcache_entry)entryForHashIndex:(int)entryIndex
{
	trustcache_entry entry;
	memcpy(&entry.hash, &_cdh.h[entryIndex].cdhash[0], CS_CDHASH_LEN);
	entry.hash_type = 0x2;
	entry.flags = 0x0;
	return entry;
}

- (void)dealloc
{
	[self unload];
}

@end