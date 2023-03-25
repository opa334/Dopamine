#import "trustcache_structs.h"
#import <Foundation/Foundation.h>

void dynamicTrustCacheAddEntry(trustcache_entry entry);
void dynamicTrustCacheRemoveEntry(trustcache_entry entry);
void fileEnumerateTrustCacheEntries(NSURL *fileURL, void (^enumerateBlock)(trustcache_entry entry));
void dynamicTrustCacheUploadFile(NSURL *fileURL);
void dynamicTrustCacheUploadCDHashFromData(NSData *cdHash);
void dynamicTrustCacheUploadCDHashesFromArray(NSArray *cdHashArray);
void dynamicTrustCacheUploadDirectory(NSString *directoryPath);
void rebuildDynamicTrustCache(void);

BOOL trustCacheListAdd(uint64_t trustCacheKaddr);
BOOL trustCacheListRemove(uint64_t trustCacheKaddr);
uint64_t staticTrustCacheUploadFile(trustcache_file *fileToUpload, size_t fileSize, size_t *outMapSize);
uint64_t staticTrustCacheUploadCDHashesFromArray(NSArray *cdHashArray, size_t *outMapSize);;
uint64_t staticTrustCacheUploadFileAtPath(NSString *filePath, size_t *outMapSize);
