#import <Foundation/Foundation.h>
void getCSBlobOffsetAndSize(int fd, uint32_t* outOffset, uint32_t* outSize);
void machoGetInfo(int fd, bool *isMachoOut, bool *isLibraryOut);
NSString *processRpaths(NSString *path, NSString *tokenName, NSArray *rpaths);
NSString *resolveLoadPath(NSString *loadPath, NSString *machoPath, NSString *sourceExecutablePath, NSArray *rpaths);
void machoEnumerateDependencies(FILE *machoFile, NSString *machoPath, void (^enumerateBlock)(NSString *dependencyPath));
int loadSignature(int fd);
void evaluateSignature(NSString* filePath, NSData **cdHashOut, BOOL *isAdhocSignedOut);
BOOL isCdHashInTrustCache(NSData *cdHash);