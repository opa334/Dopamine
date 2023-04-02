#include <fcntl.h>
#import <Foundation/Foundation.h>
#import "macho.h"

#import <IOKit/IOKitLib.h>
#import "log.h"

#define SecStaticCodeRef CFDictionaryRef
extern const CFStringRef kSecCodeInfoUnique;

CF_ENUM(uint32_t) {
	kSecCSInternalInformation = 1 << 0,
	kSecCSSigningInformation = 1 << 1,
	kSecCSRequirementInformation = 1 << 2,
	kSecCSDynamicInformation = 1 << 3,
	kSecCSContentInformation = 1 << 4,
	kSecCSSkipResourceDirectory = 1 << 5,
	kSecCSCalculateCMSDigest = 1 << 6,
};

#define AMFI_IS_CD_HASH_IN_TRUST_CACHE 6

extern OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, uint32_t flags, CFDictionaryRef attributes, SecStaticCodeRef  _Nullable *staticCode);
extern OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, uint32_t flags, CFDictionaryRef  _Nullable *information);

int getCSBlobOffsetAndSize(FILE* machoFile, uint32_t* outOffset, uint32_t* outSize)
{
	int64_t archOffsetCandidate = machoFindBestArch(machoFile);
	if (archOffsetCandidate < 0) {
		// arch not found, abort
		return 1;
	}

	uint32_t archOffset = (uint32_t)archOffsetCandidate;
	machoFindCSBlob(machoFile, archOffset, outOffset, outSize);
	return 0;
}

int loadEmbeddedSignature(FILE *file)
{
	uint32_t offset = 0, size = 0;
	
	int ret = getCSBlobOffsetAndSize(file, &offset, &size);
	if (ret == 0) {
		struct fsignatures fsig;
		fsig.fs_file_start = 0;
		fsig.fs_blob_start = (void*)(uint64_t)offset;
		fsig.fs_blob_size = size;
		ret = fcntl(fileno(file), F_ADDFILESIGS, fsig);
	}
	
	return ret;
}

int loadDetachedSignature(int fd, NSData *detachedSignature)
{
	struct fsignatures fsig;
    fsig.fs_file_start = 0;
    fsig.fs_blob_start = (void*)[detachedSignature bytes];
    fsig.fs_blob_size = [detachedSignature length];
    return fcntl(fd, F_ADDSIGS, fsig);
}

void evaluateSignature(NSURL* fileURL, NSData **cdHashOut, BOOL *isAdhocSignedOut)
{
	if(![fileURL checkResourceIsReachableAndReturnError:nil]) return;

	FILE *machoTestFile = fopen(fileURL.fileSystemRepresentation, "rb");
	if (!machoTestFile) return;

	BOOL isMacho = NO;
	machoGetInfo(machoTestFile, &isMacho, NULL);
	fclose(machoTestFile);

	if (!isMacho) return;

	SecStaticCodeRef staticCode = NULL;
	OSStatus status = SecStaticCodeCreateWithPathAndAttributes((__bridge CFURLRef)fileURL, 0, NULL, &staticCode);
	if (status == noErr) {
		CFDictionaryRef codeInfoDict;

		uint32_t flags = 0;
		if (cdHashOut) flags |= kSecCSInternalInformation | kSecCSCalculateCMSDigest;
		if (isAdhocSignedOut) flags |= kSecCSSigningInformation;

		SecCodeCopySigningInformation(staticCode, flags, &codeInfoDict);
		if (codeInfoDict) {
			// Get the signing info dictionary
			NSDictionary *signingInfoDict = (__bridge NSDictionary *)codeInfoDict;

			if (isAdhocSignedOut) {
				NSData *cms = signingInfoDict[@"cms"];
				*isAdhocSignedOut = cms.length == 0;
			}

			if (cdHashOut) {
				*cdHashOut = signingInfoDict[@"unique"];
			}

			CFRelease(codeInfoDict);
		}
		CFRelease(staticCode);
	}
}

BOOL isCdHashInTrustCache(NSData *cdHash)
{
	kern_return_t kr;

	CFMutableDictionaryRef amfiServiceDict = IOServiceMatching("AppleMobileFileIntegrity");
	if(amfiServiceDict)
	{
		io_connect_t connect;
		io_service_t amfiService = IOServiceGetMatchingService(kIOMainPortDefault, amfiServiceDict);
		kr = IOServiceOpen(amfiService, mach_task_self(), 0, &connect);
		if(kr != KERN_SUCCESS)
		{
			JBLogError(@"Failed to open amfi service %d %s", kr, mach_error_string(kr));
			return -2;
		}

		uint64_t includeLoadedTC = YES;
		kr = IOConnectCallMethod(connect, AMFI_IS_CD_HASH_IN_TRUST_CACHE, &includeLoadedTC, 1, CFDataGetBytePtr((__bridge CFDataRef)cdHash), CFDataGetLength((__bridge CFDataRef)cdHash), 0, 0, 0, 0);
		JBLogDebug(@"Is %@ in TrustCache? %@", cdHash, kr == 0 ? @"Yes" : @"No");

		IOServiceClose(connect);
		return kr == 0;
	}

	return NO;
}