#include <fcntl.h>
#import <Foundation/Foundation.h>
#import "macho.h"

#import <IOKit/IOKitLib.h>
#import "log.h"

#define AMFI_IS_CD_HASH_IN_TRUST_CACHE 6

int getCSDataOffsetAndSize(FILE* machoFile, uint32_t* outOffset, uint32_t* outSize)
{
	int64_t archOffsetCandidate = machoFindBestArch(machoFile);
	if (archOffsetCandidate < 0) {
		// arch not found, abort
		return 1;
	}

	uint32_t archOffset = (uint32_t)archOffsetCandidate;
	machoFindCSData(machoFile, archOffset, outOffset, outSize);
	return 0;
}

int loadEmbeddedSignature(FILE *file)
{
	uint32_t offset = 0, size = 0;
	
	int ret = getCSDataOffsetAndSize(file, &offset, &size);
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

int evaluateSignature(NSURL* fileURL, NSData **cdHashOut, BOOL *isAdhocSignedOut)
{
	if (!fileURL || (!cdHashOut && !isAdhocSignedOut)) return 1;
	if (![fileURL checkResourceIsReachableAndReturnError:nil]) return 2;

	FILE *machoFile = fopen(fileURL.fileSystemRepresentation, "rb");
	if (!machoFile) return 3;

	int ret = 0;

	BOOL isMacho = NO;
	machoGetInfo(machoFile, &isMacho, NULL);

	if (!isMacho) {
		fclose(machoFile);
		return 4;
	}

	int64_t archOffset = machoFindBestArch(machoFile);
	if (archOffset < 0) {
		fclose(machoFile);
		return 5;
	}

	uint32_t CSDataStart = 0, CSDataSize = 0;
	machoFindCSData(machoFile, archOffset, &CSDataStart, &CSDataSize);
	if (CSDataStart == 0 || CSDataSize == 0) {
		fclose(machoFile);
		return 6;
	}

	BOOL isAdhocSigned = machoCSDataIsAdHocSigned(machoFile, CSDataStart, CSDataSize);
	if (isAdhocSignedOut) {
		*isAdhocSignedOut = isAdhocSigned;
	}

	// we only care about the cd hash on stuff that's already verified to be ad hoc signed
	if (isAdhocSigned && cdHashOut) {
		*cdHashOut = machoCSDataCalculateCDHash(machoFile, CSDataStart, CSDataSize);
	}

	fclose(machoFile);
	return 0;
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
			JBLogError("Failed to open amfi service %d %s", kr, mach_error_string(kr));
			return -2;
		}

		uint64_t includeLoadedTC = YES;
		kr = IOConnectCallMethod(connect, AMFI_IS_CD_HASH_IN_TRUST_CACHE, &includeLoadedTC, 1, CFDataGetBytePtr((__bridge CFDataRef)cdHash), CFDataGetLength((__bridge CFDataRef)cdHash), 0, 0, 0, 0);
		JBLogDebug("Is %s in TrustCache? %s", cdHash.description.UTF8String, kr == 0 ? "Yes" : "No");

		IOServiceClose(connect);
		return kr == 0;
	}

	return NO;
}