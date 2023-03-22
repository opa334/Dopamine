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

bool isMachoOrFAT(uint32_t magic)
{
	return magic == FAT_MAGIC || magic == FAT_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64;
}

void machoGetInfo(FILE* candidateFile, bool *isMachoOut, bool *isLibraryOut)
{
	if (!candidateFile) return;

	fseek(candidateFile,0,SEEK_SET);
	struct mach_header_64 header;
	fread(&header,sizeof(header),1,candidateFile);

	bool isMacho = isMachoOrFAT(header.magic);
	bool isLibrary = NO;
	if (isMacho) {
		isLibrary = header.filetype == MH_DYLIB || header.filetype == MH_DYLIB_STUB;
	}

	if (isMachoOut) *isMachoOut = isMacho;
	if (isLibraryOut) *isLibraryOut = isLibrary;
}

int64_t machoFindArch(FILE *machoFile, struct mach_header_64 header, uint32_t typeToSearch)
{
	if(header.magic == FAT_MAGIC || header.magic == FAT_CIGAM)
	{
		fseek(machoFile,0,SEEK_SET);

		struct fat_header fatHeader;
		fread(&fatHeader,sizeof(fatHeader),1,machoFile);

		BOOL swpFat = fatHeader.magic == FAT_CIGAM;

		for(int i = 0; i < s32(fatHeader.nfat_arch, swpFat); i++)
		{
			struct fat_arch fatArch;
			fseek(machoFile,sizeof(fatHeader) + sizeof(fatArch) * i,SEEK_SET);
			fread(&fatArch,sizeof(fatArch),1,machoFile);

			uint32_t maskedSubtype = s32(fatArch.cputype, swpFat) & ~0x80000000;

			if(maskedSubtype != typeToSearch)
			{
				continue;
			}

			return s32(fatArch.offset, swpFat);
		}
	}
	else if (header.magic == MH_MAGIC_64 || header.magic == MH_CIGAM_64) {
		BOOL swpMh = header.magic == MH_CIGAM_64;
		uint32_t maskedSubtype = s32(header.cpusubtype, swpMh) & ~0x80000000;
		if (maskedSubtype == typeToSearch) return 0;
	}

	return -1;
}

int getCSBlobOffsetAndSize(FILE* machoFile, uint32_t* outOffset, uint32_t* outSize)
{
	fseek(machoFile,0,SEEK_SET);
	struct mach_header_64 header;
	fread(&header,sizeof(header),1,machoFile);

	if (!isMachoOrFAT(header.magic)) return 2;

#if __arm64e__
	int64_t archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64E);
	if (archOffsetCandidate < 0) {
		int64_t archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64_ALL);
		if (archOffsetCandidate < 0) {
			// arch not found, abort
			return 3;
		}
	}
#else
	int64_t archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64_ALL);
	if (archOffsetCandidate < 0) {
		// arch not found, abort
		return 3;
	}
#endif

	uint32_t archOffset = (uint32_t)archOffsetCandidate;

	if (archOffset) {
		fseek(machoFile,archOffset,SEEK_SET);
		fread(&header,sizeof(header),1,machoFile);
	}

	BOOL swp = header.magic == MH_CIGAM_64;

	uint32_t offset = archOffset + sizeof(header);
	for(int c = 0; c < s32(header.ncmds, swp); c++)
	{
		fseek(machoFile,offset,SEEK_SET);
		struct load_command cmd;
		fread(&cmd,sizeof(cmd),1,machoFile);
		uint32_t normalizedCmd = s32(cmd.cmd,swp);
		if(normalizedCmd == LC_CODE_SIGNATURE)
		{
			struct linkedit_data_command codeSignCommand;
			fseek(machoFile,offset,SEEK_SET);
			fread(&codeSignCommand,sizeof(codeSignCommand),1,machoFile);
			if(outOffset) *outOffset = archOffset + codeSignCommand.dataoff;
			if(outSize) *outSize = archOffset + codeSignCommand.datasize;
			break;
		}

		offset += cmd.cmdsize;
	}
	
	return 0;
}

NSString *processRpaths(NSString *path, NSString *tokenName, NSArray *rpaths)
{
	if ([path containsString:tokenName]) {
		for (NSString *rpath in rpaths) {
			NSString *testPath = [path stringByReplacingOccurrencesOfString:tokenName withString:rpath];
			if ([[NSFileManager defaultManager] fileExistsAtPath:testPath]) {
				return testPath;
			}
		}
	}
	return path;
}

NSString *resolveLoadPath(NSString *loadPath, NSString *machoPath, NSString *sourceExecutablePath, NSArray *rpaths)
{
	if (!loadPath || !machoPath) return nil;

	NSString *processedPath = processRpaths(loadPath, @"@rpath", rpaths);
	processedPath = processRpaths(processedPath, @"@executable_path", rpaths);
	processedPath = processRpaths(processedPath, @"@loader_path", rpaths);
	processedPath = [processedPath stringByReplacingOccurrencesOfString:@"@executable_path" withString:[sourceExecutablePath stringByDeletingLastPathComponent]];
	processedPath = [processedPath stringByReplacingOccurrencesOfString:@"@loader_path" withString:[machoPath stringByDeletingLastPathComponent]];

	return processedPath;
}

void _machoEnumerateDependencies(FILE *machoFile, NSString *machoPath, NSString *sourceExecutablePath, NSMutableSet *enumeratedCache, void (^enumerateBlock)(NSString *dependencyPath))
{
	if (!enumeratedCache) enumeratedCache = [NSMutableSet new];

	fseek(machoFile,0,SEEK_SET);
	struct mach_header_64 header;
	fread(&header,sizeof(header),1,machoFile);

	if (!isMachoOrFAT(header.magic)) return;

#if __arm64e__
	int64_t archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64E);
	if (archOffsetCandidate < 0) {
		archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64_ALL);
		if (archOffsetCandidate < 0) {
			// arch not found, abort
			return;
		}
	}
#else
	int64_t archOffsetCandidate = machoFindArch(machoFile, header, CPU_SUBTYPE_ARM64_ALL);
	if (archOffsetCandidate < 0) {
		// arch not found, abort
		return;
	}
#endif

	uint32_t archOffset = (uint32_t)archOffsetCandidate;

	if (archOffset) {
		fseek(machoFile,archOffset,SEEK_SET);
		fread(&header,sizeof(header),1,machoFile);
	}

	BOOL swp = header.magic == MH_CIGAM_64;

	// First iteration: Collect rpaths
	NSMutableArray* rpaths = [NSMutableArray new];
	uint32_t offset = archOffset + sizeof(header);
	while(offset < archOffset + s32(header.sizeofcmds,swp))
	{
		fseek(machoFile,offset,SEEK_SET);
		struct load_command cmd;
		fread(&cmd,sizeof(cmd),1,machoFile);
		uint32_t cmdId = s32(cmd.cmd,swp);
		if(cmdId == LC_RPATH)
		{
			fseek(machoFile,offset,SEEK_SET);
			struct rpath_command rpathCommand;
			fread(&rpathCommand,sizeof(rpathCommand),1,machoFile);
			size_t stringLength = s32(rpathCommand.cmdsize,swp) - sizeof(rpathCommand);
			fseek(machoFile,offset + s32(rpathCommand.path.offset,swp),SEEK_SET);
			char* rpathC = malloc(stringLength);
			fread(rpathC,stringLength,1,machoFile);
			NSString* rpath = [NSString stringWithUTF8String:rpathC];
			[rpaths addObject:rpath];
			free(rpathC);
		}

		offset += s32(cmd.cmdsize,swp);
	}

	// Second iteration: Find dependencies
	offset = archOffset + sizeof(header);
	while(offset < archOffset + s32(header.sizeofcmds,swp))
	{
		fseek(machoFile,offset,SEEK_SET);
		struct load_command cmd;
		fread(&cmd,sizeof(cmd),1,machoFile);
		uint32_t cmdId = s32(cmd.cmd,swp);
		if(cmdId == LC_LOAD_DYLIB || cmdId == LC_LOAD_WEAK_DYLIB || cmdId == LC_REEXPORT_DYLIB)
		{
			fseek(machoFile,offset,SEEK_SET);
			struct dylib_command dylibCommand;
			fread(&dylibCommand,sizeof(dylibCommand),1,machoFile);
			size_t stringLength = s32(dylibCommand.cmdsize,swp) - sizeof(dylibCommand);
			fseek(machoFile,offset + s32(dylibCommand.dylib.name.offset,swp),SEEK_SET);
			char *imagePathC = malloc(stringLength);
	
			fread(imagePathC,stringLength,1,machoFile);
			NSString *imagePath = [NSString stringWithUTF8String:imagePathC];
			free(imagePathC);
	
			BOOL inDSC = _dyld_shared_cache_contains_path(imagePath.fileSystemRepresentation);
			if (!inDSC) {
				NSString *resolvedPath = resolveLoadPath(imagePath, machoPath, sourceExecutablePath, rpaths);
				resolvedPath = [[resolvedPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
				if (![enumeratedCache containsObject:resolvedPath] && [[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
					[enumeratedCache addObject:resolvedPath];
					enumerateBlock(resolvedPath);

					FILE *nextFile = fopen(resolvedPath.fileSystemRepresentation, "rb");
					_machoEnumerateDependencies(nextFile, imagePath, sourceExecutablePath, enumeratedCache, enumerateBlock);
					fclose(nextFile);
				}
				else {
					if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
						//NSLog(@"skipped %@, non existant", resolvedPath);
					}
					else {
						//NSLog(@"skipped %@, in cache", resolvedPath);
					}
				}
			}
			else {
				//NSLog(@"skipped %@, in DSC", imagePath);
			}
		}

		offset += s32(cmd.cmdsize,swp);
	}
}

void machoEnumerateDependencies(FILE *machoFile, NSString *machoPath, void (^enumerateBlock)(NSString *dependencyPath))
{
	_machoEnumerateDependencies(machoFile, machoPath, machoPath, nil, enumerateBlock);
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
			NSLog(@"Failed to open amfi service %d %s", kr, mach_error_string(kr));
			return -2;
		}

		uint64_t includeLoadedTC = YES;
		kr = IOConnectCallMethod(connect, AMFI_IS_CD_HASH_IN_TRUST_CACHE, &includeLoadedTC, 1, CFDataGetBytePtr((__bridge CFDataRef)cdHash), CFDataGetLength((__bridge CFDataRef)cdHash), 0, 0, 0, 0);
		NSLog(@"amfi returned %d, %s", kr, mach_error_string(kr));

		IOServiceClose(connect);
		return kr == 0;
	}

	return NO;
}