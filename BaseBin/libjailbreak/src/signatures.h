#import <Foundation/Foundation.h>
int getCSBlobOffsetAndSize(FILE* machoFile, uint32_t* outOffset, uint32_t* outSize);

NSString *processRpaths(NSString *path, NSString *tokenName, NSArray *rpaths);
NSString *resolveLoadPath(NSString *loadPath, NSString *machoPath, NSString *sourceExecutablePath, NSArray *rpaths);
int evaluateSignature(NSURL* fileURL, NSData **cdHashOut, BOOL *isAdhocSignedOut);
BOOL isCdHashInTrustCache(NSData *cdHash);
int loadEmbeddedSignature(FILE *file);