#import "trustcache.h"

#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/util.h>
#import <sys/stat.h>
#import <unistd.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/signatures.h>
#import "trustcache_structs.h"
#import "JBDTCPage.h"
#import "spawn_wrapper.h"

NSString* normalizePath(NSString* path)
{
	return [[path stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

int tcentryComparator(const void * vp1, const void * vp2)
{
	trustcache_entry* tc1 = (trustcache_entry*)vp1;
	trustcache_entry* tc2 = (trustcache_entry*)vp2;
	return memcmp(tc1->hash, tc2->hash, CS_CDHASH_LEN);
}

JBDTCPage *trustCacheMapInFreePage(void)
{
	// Find page that has slots left
	for (JBDTCPage *page in gTCPages) {
		@autoreleasepool {
			[page mapIn];
			if (page.amountOfSlotsLeft > 0) {
				return page;
			}
			[page mapOut];
		}
	}

	// No page found, allocate new one
	JBDTCPage *newPage = [[JBDTCPage alloc] initAllocateAndLink];
	[newPage mapIn];
	return newPage;
}

void dynamicTrustCacheAddEntry(trustcache_entry entry)
{
	JBDTCPage *freePage = trustCacheMapInFreePage();
	[freePage addEntry:entry];
	[freePage sort];
	[freePage mapOut];
}

void dynamicTrustCacheRemoveEntry(trustcache_entry entry)
{
	for (JBDTCPage *page in gTCPages) {
		@autoreleasepool {
			BOOL removed = [page removeEntry:entry];
			if (removed) return;
		}
	}
}

void fileEnumerateTrustCacheEntries(NSURL *fileURL, void (^enumerateBlock)(trustcache_entry entry)) {
	NSData *cdHash = nil;
	BOOL adhocSigned = NO;
	int evalRet = evaluateSignature(fileURL, &cdHash, &adhocSigned);
	if (evalRet == 0) {
		JBLogDebug("%s cdHash: %s, adhocSigned: %d", fileURL.path.UTF8String, cdHash.description.UTF8String, adhocSigned);
		if (adhocSigned) {
			if ([cdHash length] == CS_CDHASH_LEN) {
				trustcache_entry entry;
				memcpy(&entry.hash, [cdHash bytes], CS_CDHASH_LEN);
				entry.hash_type = 0x2;
				entry.flags = 0x0;
				enumerateBlock(entry);
			}
		}
	} else if (evalRet != 4) {
		JBLogError("evaluateSignature failed with error %d", evalRet);
	}
}

void dynamicTrustCacheUploadFile(NSURL *fileURL)
{
	fileEnumerateTrustCacheEntries(fileURL, ^(trustcache_entry entry) {
		dynamicTrustCacheAddEntry(entry);
	});
}

void dynamicTrustCacheUploadCDHashFromData(NSData *cdHash)
{
	if (cdHash.length != CS_CDHASH_LEN) return;

	trustcache_entry entry;
	memcpy(&entry.hash, cdHash.bytes, CS_CDHASH_LEN);
	entry.hash_type = 0x2;
	entry.flags = 0x0;
	dynamicTrustCacheAddEntry(entry);
}

void dynamicTrustCacheUploadCDHashesFromArray(NSArray *cdHashArray)
{
	__block JBDTCPage *mappedInPage = nil;
	for (NSData *cdHash in cdHashArray) {
		@autoreleasepool {
			if (!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
				// If there is still a page mapped, map it out now
				if (mappedInPage) {
					[mappedInPage sort];
					[mappedInPage mapOut];
				}

				mappedInPage = trustCacheMapInFreePage();
			}

			trustcache_entry entry;
			memcpy(&entry.hash, cdHash.bytes, CS_CDHASH_LEN);
			entry.hash_type = 0x2;
			entry.flags = 0x0;
			JBLogDebug("[dynamicTrustCacheUploadCDHashesFromArray] uploading %s", cdHash.description.UTF8String);
			[mappedInPage addEntry:entry];
		}
	}

	if (mappedInPage) {
		[mappedInPage sort];
		[mappedInPage mapOut];
	}
}

void dynamicTrustCacheUploadDirectory(NSString *directoryPath)
{
	NSString *basebinPath = [[prebootPath(@"basebin") stringByResolvingSymlinksInPath] stringByStandardizingPath];
	NSString *resolvedPath = [[directoryPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
	NSDirectoryEnumerator<NSURL *> *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:resolvedPath isDirectory:YES] 
																			   includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey]
																								  options:0
																							 errorHandler:nil];
	__block JBDTCPage *mappedInPage = nil;
	for (NSURL *enumURL in directoryEnumerator) {
		@autoreleasepool {
			NSNumber *isSymlink;
			[enumURL getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil];
			if (isSymlink && ![isSymlink boolValue]) {
				// never inject basebin binaries here
				if ([[[enumURL.path stringByResolvingSymlinksInPath] stringByStandardizingPath] hasPrefix:basebinPath]) continue;
				fileEnumerateTrustCacheEntries(enumURL, ^(trustcache_entry entry) {
					if (!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
						// If there is still a page mapped, map it out now
						if (mappedInPage) {
							[mappedInPage sort];
							[mappedInPage mapOut];
						}
						JBLogDebug("mapping in a new tc page");
						mappedInPage = trustCacheMapInFreePage();
					}

					JBLogDebug("[dynamicTrustCacheUploadDirectory %s] Uploading cdhash of %s", directoryPath.UTF8String, enumURL.path.UTF8String);
					[mappedInPage addEntry:entry];
				});
			}
		}
	}

	if (mappedInPage) {
		[mappedInPage sort];
		[mappedInPage mapOut];
	}
}

void rebuildDynamicTrustCache(void)
{
	// nuke existing
	for (JBDTCPage *page in [gTCPages reverseObjectEnumerator]) {
		@autoreleasepool {
			[page unlinkAndFree];
		}
	}

	JBLogDebug("Triggering initial trustcache upload...");
	dynamicTrustCacheUploadDirectory(prebootPath(nil));
	JBLogDebug("Initial TrustCache upload done!");
}

BOOL trustCacheListAdd(uint64_t trustCacheKaddr)
{
	if (!trustCacheKaddr) return NO;

	uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
	uint64_t curTc = kread64(pmap_image4_trust_caches);
	if(curTc == 0) {
		kwrite64(pmap_image4_trust_caches, trustCacheKaddr);
	}
	else {
		uint64_t prevTc = 0;
		while (curTc != 0)
		{
			prevTc = curTc;
			curTc = kread64(curTc);
		}
		kwrite64(prevTc, trustCacheKaddr);
	}

	return YES;
}

BOOL trustCacheListRemove(uint64_t trustCacheKaddr)
{
	if (!trustCacheKaddr) return NO;

	uint64_t nextPtr = kread64(trustCacheKaddr + offsetof(trustcache_page, nextPtr));

	uint64_t pmap_image4_trust_caches = bootInfo_getSlidUInt64(@"pmap_image4_trust_caches");
	uint64_t curTc = kread64(pmap_image4_trust_caches);
	if (curTc == 0) {
		JBLogError("WARNING: Tried to unlink trust cache page 0x%llX but pmap_image4_trust_caches points to 0x0", trustCacheKaddr);
		return NO;
	}
	else if (curTc == trustCacheKaddr) {
		kwrite64(pmap_image4_trust_caches, nextPtr);
	}
	else {
		uint64_t prevTc = 0;
		while (curTc != trustCacheKaddr)
		{
			if (curTc == 0) {
				JBLogError("WARNING: Hit end of trust cache chain while trying to unlink trust cache page 0x%llX", trustCacheKaddr);
				return NO;
			}
			prevTc = curTc;
			curTc = kread64(curTc);
		}
		kwrite64(prevTc, nextPtr);
	}
	return YES;
}

// These functions make new allocations and add them to the trustcache list

uint64_t staticTrustCacheUploadFile(trustcache_file *fileToUpload, size_t fileSize, size_t *outMapSize)
{
	if (fileSize < sizeof(trustcache_file)) {
		JBLogError("attempted to load a trustcache file that's too small.");
		return 0;
	}

	size_t expectedSize = sizeof(trustcache_file) + fileToUpload->length * sizeof(trustcache_entry);
	if (expectedSize != fileSize) {
		JBLogError("attempted to load a trustcache file with an invalid size (0x%zX vs 0x%zX)", expectedSize, fileSize);
		return 0;
	}

	uint64_t mapSize = sizeof(trustcache_page) + fileSize;

	uint64_t mapKaddr = 0;
	uint64_t allocRet = kalloc(&mapKaddr, mapSize);
	if (!mapKaddr || allocRet != 0) {
		JBLogError("failed to allocate memory for trust cache file with size %zX", fileSize);
		return 0;
	}

	if (outMapSize) *outMapSize = mapSize;

	uint64_t mapSelfPtrPtr = mapKaddr + offsetof(trustcache_page, selfPtr);
	uint64_t mapSelfPtr = mapKaddr + offsetof(trustcache_page, file);

	kwrite64(mapSelfPtrPtr, mapSelfPtr);
	kwritebuf(mapSelfPtr, fileToUpload, fileSize);
	trustCacheListAdd(mapKaddr);
	return mapKaddr;
}

uint64_t staticTrustCacheUploadCDHashesFromArray(NSArray *cdHashArray, size_t *outMapSize)
{
	size_t fileSize = sizeof(trustcache_file) + cdHashArray.count * sizeof(trustcache_entry);
	trustcache_file *fileToUpload = malloc(fileSize);

	uuid_generate(fileToUpload->uuid);
	fileToUpload->version = 1;
	fileToUpload->length = cdHashArray.count;

	[cdHashArray enumerateObjectsUsingBlock:^(NSData *cdHash, NSUInteger idx, BOOL *stop) {
		if (![cdHash isKindOfClass:[NSData class]]) return;
		if (cdHash.length != CS_CDHASH_LEN) return;

		memcpy(&fileToUpload->entries[idx].hash, cdHash.bytes, cdHash.length);
		fileToUpload->entries[idx].hash_type = 0x2;
		fileToUpload->entries[idx].flags = 0x0;
	}];

	qsort(fileToUpload->entries, cdHashArray.count, sizeof(trustcache_entry), tcentryComparator);

	uint64_t mapKaddr = staticTrustCacheUploadFile(fileToUpload, fileSize, outMapSize);
	free(fileToUpload);
	return mapKaddr;
}

uint64_t staticTrustCacheUploadFileAtPath(NSString *filePath, size_t *outMapSize)
{
	if (!filePath) return 0;
	NSData *tcData = [NSData dataWithContentsOfFile:filePath];
	if (!tcData) return 0;
	return staticTrustCacheUploadFile((trustcache_file *)tcData.bytes, tcData.length, outMapSize);
}