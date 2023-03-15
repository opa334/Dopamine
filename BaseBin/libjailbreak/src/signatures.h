#import <Foundation/Foundation.h>
void getCSBlobOffsetAndSize(int fd, uint32_t* outOffset, uint32_t* outSize);
int loadSignature(int fd);
void evaluateSignature(NSString* filePath, NSData **cdHashOut, BOOL *isAdhocSignedOut);
BOOL isCdHashInTrustCache(NSData *cdHash);