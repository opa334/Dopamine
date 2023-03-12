#import "trustcache.h"

#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fileobserve/OPFileTree.h>
#import "JBDFileLeaf.h"
#import "JBDFileTree.h"
#import <libjailbreak/boot_info.h>
#import "trustcache_structs.h"
#import "JBDTCPage.h"
#import "spawn_wrapper.h"

OPFileTree *gFileTree = nil;

NSString* normalizePath(NSString* path)
{
	return [[path stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

JBDTCPage *trustCacheMapInFreePage(void)
{
	// Find page that has slots left
	for (JBDTCPage *page in gTCPages) {
		[page mapIn];
		if (page.amountOfSlotsLeft > 0) {
			return page;
		}
		[page mapOut];
	}

	// No page found, allocate new one
	JBDTCPage *newPage = [[JBDTCPage alloc] initAllocateAndLink];
	[newPage mapIn];
	return newPage;
}

void uploadTrustCache(void)
{
	__block JBDTCPage *mappedInPage = nil;

	[gFileTree enumerateLeafs:^(JBDFileLeaf *leaf, BOOL *stop) {
		[leaf ensureLoaded];
		for (uint64_t i = 0; i < leaf.hashCount; i++)
		{
			@autoreleasepool {
				if (!mappedInPage || mappedInPage.amountOfSlotsLeft == 0) {
					// If there is still a page mapped, map it out now
					if (mappedInPage) {
						[mappedInPage sort];
						[mappedInPage mapOut];
					}

					mappedInPage = trustCacheMapInFreePage();
				}

				NSLog(@"[TC] Adding entry %llu for %@ (Initial Run)", i, leaf.fullPath);
				[mappedInPage addEntry:[leaf entryForHashIndex:i]];
			}
		}
	}];

	if (mappedInPage) {
		[mappedInPage sort];
		[mappedInPage mapOut];
	}
}

void trustCacheAddEntry(trustcache_entry entry)
{
	JBDTCPage *freePage = trustCacheMapInFreePage();
	[freePage addEntry:entry];
	[freePage sort];
	[freePage mapOut];
}

void trustCacheRemoveEntry(trustcache_entry entry)
{
	for (JBDTCPage *page in gTCPages) {
		BOOL removed = [page removeEntry:entry];
		if (removed) return;
	}
}

void rebuildTrustCache(void)
{
	for (JBDTCPage *page in [gTCPages reverseObjectEnumerator]) {
		[page unlinkAndFree];
	}

	NSLog(@"About to open file tree...");
	gFileTree = [[JBDFileTree alloc] initWithPath:normalizePath(@"/var/jb")];
	gFileTree.leafClass = [JBDFileLeaf class];
	[gFileTree openTree];
	NSLog(@"Opened file tree!");

	NSLog(@"Triggering initial trustcache upload...");
	uploadTrustCache();
	NSLog(@"Initial TrustCache upload done!");
}

void startTrustCacheFileListener(void)
{
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		tcPagesRecover();
		rebuildTrustCache();
		if (!bootInfo_getUInt64(@"launchdInitialized")) {
			// if launchd hook is not active, we want to load launch daemons now as the trustcache should be up now
			spawn(@"/var/jb/usr/bin/launchctl", @[@"bootstrap", @"system", @"/var/jb/Library/LaunchDaemons"]);
		}
	});
}