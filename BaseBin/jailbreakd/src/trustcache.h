#import "trustcache_structs.h"
#import <Foundation/Foundation.h>

void trustCacheAddEntry(trustcache_entry entry);
void trustCacheRemoveEntry(trustcache_entry entry);
void fileEnumerateTrustCacheEntries(NSURL *fileURL, void (^enumerateBlock)(trustcache_entry entry));
void trustCacheUploadFile(NSURL *fileURL);
void trustCacheUploadCDHashFromData(NSData *cdHash);
void trustCacheUploadCDHashesFromArray(NSArray *cdHashArray);
void trustCacheUploadDirectory(NSString *directoryPath);

void rebuildTrustCache(void);