#import <Foundation/Foundation.h>
#import "macho.h"


void machoEnumerateArchs(FILE* machoFile, void (^archEnumBlock)(struct fat_arch* arch, uint32_t archMetadataOffset, uint32_t archOffset, BOOL* stop))
{
	struct mach_header_64 mh;
	fseek(machoFile,0,SEEK_SET);
	fread(&mh,sizeof(mh),1,machoFile);
	
	if(mh.magic == FAT_MAGIC || mh.magic == FAT_CIGAM)
	{
		fseek(machoFile,0,SEEK_SET);
		struct fat_header fh;
		fread(&fh,sizeof(fh),1,machoFile);
		
		for(int i = 0; i < OSSwapBigToHostInt32(fh.nfat_arch); i++)
		{
			uint32_t archMetadataOffset = sizeof(fh) + sizeof(struct fat_arch) * i;
			struct fat_arch fatArch;
			fseek(machoFile, archMetadataOffset, SEEK_SET);
			fread(&fatArch, sizeof(fatArch), 1, machoFile);
			
			BOOL stop = NO;
			archEnumBlock(&fatArch, archMetadataOffset, OSSwapBigToHostInt32(fatArch.offset), &stop);
			if(stop) break;
		}
	}
	else if(mh.magic == MH_MAGIC_64 || mh.magic == MH_CIGAM_64)
	{
		BOOL stop;
		archEnumBlock(NULL, 0, 0, &stop);
	}
}

void machoGetInfo(FILE* candidateFile, bool *isMachoOut, bool *isLibraryOut)
{
	if (!candidateFile) return;

	fseek(candidateFile,0,SEEK_SET);
	struct mach_header_64 mh;
	fread(&mh,sizeof(mh),1,candidateFile);

	bool isMacho = mh.magic == MH_MAGIC_64 || mh.magic == MH_CIGAM_64 || mh.magic == FAT_MAGIC || mh.magic == FAT_CIGAM;
	bool isLibrary = NO;
	if (isMacho && isLibraryOut) {
		__block int32_t anyArchOffset = 0;
		machoEnumerateArchs(candidateFile, ^(struct fat_arch* arch, uint32_t archMetadataOffset, uint32_t archOffset, BOOL* stop) {
			anyArchOffset = archOffset;
			*stop = YES;
		});

		fseek(candidateFile, anyArchOffset, SEEK_SET);
		fread(&mh, sizeof(mh), 1, candidateFile);

		isLibrary = OSSwapLittleToHostInt32(mh.filetype) == MH_DYLIB || OSSwapLittleToHostInt32(mh.filetype) == MH_DYLIB_STUB;
	}

	if (isMachoOut) *isMachoOut = isMacho;
	if (isLibraryOut) *isLibraryOut = isLibrary;
}

int64_t machoFindArch(FILE *machoFile, uint32_t subtypeToSearch)
{
	__block int64_t outArchOffset = -1;

	machoEnumerateArchs(machoFile, ^(struct fat_arch* arch, uint32_t archMetadataOffset, uint32_t archOffset, BOOL* stop) {
		struct mach_header_64 mh;
		fseek(machoFile, archOffset, SEEK_SET);
		fread(&mh, sizeof(mh), 1, machoFile);
		uint32_t maskedSubtype = OSSwapBigToHostInt32(mh.cpusubtype) & ~0x80000000;
		if (maskedSubtype == subtypeToSearch) {
			outArchOffset = archOffset;
			*stop = YES;
		}
	});

	return outArchOffset;
}

int64_t machoFindBestArch(FILE *machoFile)
{
#if __arm64e__
	int64_t archOffsetCandidate = machoFindArch(machoFile, CPU_SUBTYPE_ARM64E);
	if (archOffsetCandidate < 0) {
		archOffsetCandidate = machoFindArch(machoFile, CPU_SUBTYPE_ARM64_ALL);
	}
	return archOffsetCandidate;
#else
	int64_t archOffsetCandidate = machoFindArch(machoFile, CPU_SUBTYPE_ARM64_ALL);
	return archOffsetCandidate;
#endif
}

void machoEnumerateLoadCommands(FILE *machoFile, uint32_t archOffset, void (^enumerateBlock)(struct load_command cmd, uint32_t cmdOffset))
{
	struct mach_header_64 mh;
	fseek(machoFile, archOffset, SEEK_SET);
	fread(&mh, sizeof(mh), 1, machoFile);

	uint32_t offset = archOffset + sizeof(mh);
	for (int i = 0; i < OSSwapLittleToHostInt32(mh.ncmds) && offset < OSSwapLittleToHostInt32(mh.sizeofcmds); i++) {
		struct load_command cmd;
		fseek(machoFile, offset, SEEK_SET);
		fread(&cmd, sizeof(cmd), 1, machoFile);
		enumerateBlock(cmd, offset);
		offset += OSSwapLittleToHostInt32(cmd.cmdsize);
	}
}

void machoFindCSBlob(FILE* machoFile, uint32_t archOffset, uint32_t* outOffset, uint32_t* outSize)
{
	machoEnumerateLoadCommands(machoFile, archOffset, ^(struct load_command cmd, uint32_t cmdOffset) {
		if (OSSwapLittleToHostInt32(cmd.cmd) == LC_CODE_SIGNATURE) {
			fseek(machoFile, cmdOffset, SEEK_SET);
			struct linkedit_data_command CSCommand;
			fread(&CSCommand, sizeof(CSCommand), 1, machoFile);
			if(outOffset) *outOffset = archOffset + OSSwapLittleToHostInt32(CSCommand.dataoff);
			if(outSize) *outSize = archOffset + OSSwapLittleToHostInt32(CSCommand.datasize);
		}
	});
}

NSString *processRpaths(NSString *path, NSString *tokenName, NSArray *rpaths)
{
	if (!rpaths) return path;

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

void _machoEnumerateDependencies(FILE *machoFile, uint32_t archOffset, NSString *machoPath, NSString *sourceExecutablePath, NSMutableSet *enumeratedCache, void (^enumerateBlock)(NSString *dependencyPath))
{
	if (!enumeratedCache) enumeratedCache = [NSMutableSet new];

	// First iteration: Collect rpaths
	NSMutableArray* rpaths = [NSMutableArray new];
	machoEnumerateLoadCommands(machoFile, archOffset, ^(struct load_command cmd, uint32_t cmdOffset) {
		if (OSSwapLittleToHostInt32(cmd.cmd) == LC_RPATH) {
			fseek(machoFile, cmdOffset, SEEK_SET);
			struct rpath_command rpathCommand;
			fread(&rpathCommand, sizeof(rpathCommand), 1, machoFile);

			size_t stringLength = OSSwapLittleToHostInt32(rpathCommand.cmdsize) - sizeof(rpathCommand);
			fseek(machoFile, cmdOffset + OSSwapLittleToHostInt32(rpathCommand.path.offset), SEEK_SET);
			char* rpathC = malloc(stringLength);
			fread(rpathC,stringLength,1,machoFile);
			NSString *rpath = [NSString stringWithUTF8String:rpathC];
			free(rpathC);

			NSString *resolvedRpath = resolveLoadPath(rpath, machoPath, sourceExecutablePath, nil);
			if (resolvedRpath) {
				[rpaths addObject:resolvedRpath];
			}
		}
	});

	// Second iteration: Find dependencies
	machoEnumerateLoadCommands(machoFile, archOffset, ^(struct load_command cmd, uint32_t cmdOffset) {
		uint32_t cmdId = OSSwapLittleToHostInt32(cmd.cmd);
		if (cmdId == LC_LOAD_DYLIB || cmdId == LC_LOAD_WEAK_DYLIB || cmdId == LC_REEXPORT_DYLIB) {
			fseek(machoFile, cmdOffset, SEEK_SET);
			struct dylib_command dylibCommand;
			fread(&dylibCommand,sizeof(dylibCommand),1,machoFile);
			size_t stringLength = OSSwapLittleToHostInt32(dylibCommand.cmdsize) - sizeof(dylibCommand);
			fseek(machoFile, cmdOffset + OSSwapLittleToHostInt32(dylibCommand.dylib.name.offset), SEEK_SET);
			char *imagePathC = malloc(stringLength);
			fread(imagePathC, stringLength, 1, machoFile);
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
					_machoEnumerateDependencies(nextFile, archOffset, imagePath, sourceExecutablePath, enumeratedCache, enumerateBlock);
					fclose(nextFile);
				}
				else {
					if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
						//JBLogDebug(@"skipped %@, non existant", resolvedPath);
					}
					else {
						//JBLogDebug(@"skipped %@, in cache", resolvedPath);
					}
				}
			}
			else {
				//JBLogDebug(@"skipped %@, in DSC", imagePath);
			}
		}
	});
}

void machoEnumerateDependencies(FILE *machoFile, uint32_t archOffset, NSString *machoPath, void (^enumerateBlock)(NSString *dependencyPath))
{
	_machoEnumerateDependencies(machoFile, archOffset, machoPath, machoPath, nil, enumerateBlock);
}