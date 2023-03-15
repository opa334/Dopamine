#include <fcntl.h>
#import <Foundation/Foundation.h>

#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/machine.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach-o/reloc.h>
#import <mach-o/dyld_images.h>
#import <mach-o/fat.h>
#import <IOKit/IOKitLib.h>

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

#define SWAP32(x) ((((x) & 0xff000000) >> 24) | (((x) & 0xff0000) >> 8) | (((x) & 0xff00) << 8) | (((x) & 0xff) << 24))
uint32_t s32(uint32_t toSwap, BOOL shouldSwap)
{
    return shouldSwap ? SWAP32(toSwap) : toSwap;
}

void getCSBlobOffsetAndSize(int fd, uint32_t* outOffset, uint32_t* outSize)
{
    FILE* binaryFile = fdopen(fd, "rb");
    struct mach_header_64 header;
    fread(&header,sizeof(header),1,binaryFile);

#if __arm64e__
    uint32_t subtypeToSearch = CPU_SUBTYPE_ARM64E;
#else
    uint32_t subtypeToSearch = CPU_SUBTYPE_ARM64_ALL;
#endif

    // get arch offset
    uint32_t archOffset = 0;
    if(header.magic == FAT_MAGIC || header.magic == FAT_CIGAM)
    {
        fseek(binaryFile,0,SEEK_SET);

        struct fat_header fatHeader;
        fread(&fatHeader,sizeof(fatHeader),1,binaryFile);

        BOOL swpFat = fatHeader.magic == FAT_CIGAM;

        for(int i = 0; i < s32(fatHeader.nfat_arch, swpFat); i++)
        {
            struct fat_arch fatArch;
            fseek(binaryFile,sizeof(fatHeader) + sizeof(fatArch) * i,SEEK_SET);
            fread(&fatArch,sizeof(fatArch),1,binaryFile);

            uint32_t maskedSubtype = s32(fatArch.cputype, swpFat) & ~CPU_SUBTYPE_ARM64_PTR_AUTH_MASK;

            if(maskedSubtype != subtypeToSearch)
            {
                continue;
            }

            archOffset = s32(fatArch.offset, swpFat);
            break;
        }
    }

    // get blob offset
    fseek(binaryFile,archOffset,SEEK_SET);
    fread(&header,sizeof(header),1,binaryFile);

    BOOL swp = header.magic == MH_CIGAM_64;

    uint32_t offset = archOffset + sizeof(header);
    for(int c = 0; c < s32(header.ncmds, swp); c++)
    {
        fseek(binaryFile,offset,SEEK_SET);
        struct load_command cmd;
        fread(&cmd,sizeof(cmd),1,binaryFile);
        uint32_t normalizedCmd = s32(cmd.cmd,swp);
        if(normalizedCmd == LC_CODE_SIGNATURE)
        {
            struct linkedit_data_command codeSignCommand;
            fseek(binaryFile,offset,SEEK_SET);
            fread(&codeSignCommand,sizeof(codeSignCommand),1,binaryFile);
            if(outOffset) *outOffset = archOffset + codeSignCommand.dataoff;
            if(outSize) *outSize = archOffset + codeSignCommand.datasize;
            break;
        }

        offset += cmd.cmdsize;
    }
    
    fclose(binaryFile);
}

int loadSignature(int fd)
{
    uint32_t offset = 0, size = 0;
    
    getCSBlobOffsetAndSize(fd, &offset, &size);
    
    struct fsignatures fsig;
    fsig.fs_file_start = 0;
    fsig.fs_blob_start = (void*)(uint64_t)offset;
    fsig.fs_blob_size = size;
    
    int ret = fcntl(fd, F_ADDFILESIGS, fsig);
    return ret;
}

void evaluateSignature(NSString* filePath, NSData **cdHashOut, BOOL *isAdhocSignedOut)
{
    if(![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return;

    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecStaticCodeCreateWithPathAndAttributes((__bridge CFURLRef)[NSURL fileURLWithPath:filePath], 0, NULL, &staticCode);
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
			NSLog(@"Failed to open amfi service %d %s", kr, mach_error_string(kr));
			return -2;
		}

		kr = IOConnectCallMethod(connect, AMFI_IS_CD_HASH_IN_TRUST_CACHE, NULL, 0, CFDataGetBytePtr((__bridge CFDataRef)cdHash), CFDataGetLength((__bridge CFDataRef)cdHash), 0, 0, 0, 0);
		NSLog(@"amfi returned %d, %s", kr, mach_error_string(kr));

		IOServiceClose(connect);
		return kr == 0;
	}

	return NO;
}