#import <Foundation/Foundation.h>
int getCSBlobOffsetAndSize(FILE* machoFile, uint32_t* outOffset, uint32_t* outSize);
void machoGetInfo(FILE* candidateFile, bool *isMachoOut, bool *isLibraryOut);
NSString *processRpaths(NSString *path, NSString *tokenName, NSArray *rpaths);
NSString *resolveLoadPath(NSString *loadPath, NSString *machoPath, NSString *sourceExecutablePath, NSArray *rpaths);
void machoEnumerateDependencies(FILE *machoFile, NSString *machoPath, void (^enumerateBlock)(NSString *dependencyPath));
int loadEmbeddedSignature(FILE *file);
void evaluateSignature(NSURL* fileURL, NSData **cdHashOut, BOOL *isAdhocSignedOut);
BOOL isCdHashInTrustCache(NSData *cdHash);