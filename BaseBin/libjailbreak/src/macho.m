#import <Foundation/Foundation.h>
#import "macho.h"
#import <CommonCrypto/CommonDigest.h>
#import "log.h"

void machoEnumerateArchs(FILE* machoFile, void (^archEnumBlock)(struct fat_arch* arch, uint32_t archMetadataOffset, uint32_t archOffset, BOOL* stop))
{
	struct mach_header_64 mh;
	fseek(machoFile,0,SEEK_SET);
	fread(&mh,sizeof(mh),1,machoFile);
	
	if(mh.magic == FAT_MAGIC || mh.magic == FAT_CIGAM)
	{
		struct fat_header fh;
		fseek(machoFile,0,SEEK_SET);
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

	struct mach_header_64 mh;
	fseek(candidateFile,0,SEEK_SET);
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
		uint32_t maskedSubtype = OSSwapLittleToHostInt32(mh.cpusubtype) & ~0x80000000;
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

	uint32_t nCmds = OSSwapLittleToHostInt32(mh.ncmds);
	uint32_t sizeOfCmds = OSSwapLittleToHostInt32(mh.sizeofcmds);
	uint32_t offset = 0;
	JBLogDebug("[machoEnumerateLoadCommands] About to enumerate over %u load commands (total size: 0x%X)", nCmds, sizeOfCmds);
	for (uint32_t i = 0; i < nCmds && offset < sizeOfCmds; i++) {
		uint32_t absoluteOffset = archOffset + sizeof(mh) + offset;
		struct load_command cmd;
		fseek(machoFile, absoluteOffset, SEEK_SET);
		fread(&cmd, sizeof(cmd), 1, machoFile);
		enumerateBlock(cmd, absoluteOffset);
		offset += OSSwapLittleToHostInt32(cmd.cmdsize);
	}
	JBLogDebug("[machoEnumerateLoadCommands] Finished enumerating over %u load commands (total size: 0x%X)", nCmds, sizeOfCmds);
}

void machoFindCSData(FILE* machoFile, uint32_t archOffset, uint32_t* outOffset, uint32_t* outSize)
{
	machoEnumerateLoadCommands(machoFile, archOffset, ^(struct load_command cmd, uint32_t cmdOffset) {
		if (OSSwapLittleToHostInt32(cmd.cmd) == LC_CODE_SIGNATURE) {
			struct linkedit_data_command CSCommand;
			fseek(machoFile, cmdOffset, SEEK_SET);
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
			struct rpath_command rpathCommand;
			fseek(machoFile, cmdOffset, SEEK_SET);
			fread(&rpathCommand, sizeof(rpathCommand), 1, machoFile);

			size_t stringLength = OSSwapLittleToHostInt32(rpathCommand.cmdsize) - sizeof(rpathCommand);
			char* rpathC = malloc(stringLength);
			fseek(machoFile, cmdOffset + OSSwapLittleToHostInt32(rpathCommand.path.offset), SEEK_SET);
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
			struct dylib_command dylibCommand;
			fseek(machoFile, cmdOffset, SEEK_SET);
			fread(&dylibCommand,sizeof(dylibCommand),1,machoFile);
			size_t stringLength = OSSwapLittleToHostInt32(dylibCommand.cmdsize) - sizeof(dylibCommand);
			char *imagePathC = malloc(stringLength);
			fseek(machoFile, cmdOffset + OSSwapLittleToHostInt32(dylibCommand.dylib.name.offset), SEEK_SET);
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

					JBLogDebug("[_machoEnumerateDependencies] Found depdendency %s, recursively enumerating over it...", resolvedPath.UTF8String);
					FILE *nextFile = fopen(resolvedPath.fileSystemRepresentation, "rb");
					if (nextFile) {
						BOOL nextFileIsMacho = NO;
						machoGetInfo(nextFile, &nextFileIsMacho, NULL);
						if (nextFileIsMacho) {
							int64_t nextBestArchCandidate = machoFindBestArch(nextFile);
							if (nextBestArchCandidate >= 0) {
								_machoEnumerateDependencies(nextFile, nextBestArchCandidate, imagePath, sourceExecutablePath, enumeratedCache, enumerateBlock);
							}
							else {
								JBLogError("[_machoEnumerateDependencies] Failed to find best arch of dependency %s", resolvedPath.UTF8String);
							}
						}
						else {
							JBLogError("[_machoEnumerateDependencies] Dependency %s does not seem to be a macho", resolvedPath.UTF8String);
						}
						fclose(nextFile);
					}
					else {
						JBLogError("[_machoEnumerateDependencies] Dependency %s does not seem to exist, maybe path resolving failed?", resolvedPath.UTF8String);
					}
				}
				else {
					if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
						JBLogError("[_machoEnumerateDependencies] Skipped dependency %s, non existant", resolvedPath.UTF8String);
					}
					else {
						JBLogDebug("[_machoEnumerateDependencies] Skipped dependency %s, already cached", resolvedPath.UTF8String);
					}
				}
			}
			else {
				JBLogDebug("[_machoEnumerateDependencies] Skipped dependency %s, in dyld_shared_cache", imagePath.UTF8String);
			}
		}
	});
}

void machoEnumerateDependencies(FILE *machoFile, uint32_t archOffset, NSString *machoPath, void (^enumerateBlock)(NSString *dependencyPath))
{
	_machoEnumerateDependencies(machoFile, archOffset, machoPath, machoPath, nil, enumerateBlock);
}

unsigned CSCodeDirectoryRank(CS_CodeDirectory *cd) {
	// The supported hash types, ranked from least to most preferred. From XNU's
	// bsd/kern/ubc_subr.c.
	static uint32_t rankedHashTypes[] = {
		CS_HASHTYPE_SHA160_160,
		CS_HASHTYPE_SHA256_160,
		CS_HASHTYPE_SHA256_256,
		CS_HASHTYPE_SHA384_384,
	};
	// Define the rank of the code directory as its index in the array plus one.
	for (unsigned i = 0; i < sizeof(rankedHashTypes) / sizeof(rankedHashTypes[0]); i++) {
		if (rankedHashTypes[i] == cd->hashType) {
			return (i + 1);
		}
	}
	return 0;
}

void machoCSDataEnumerateBlobs(FILE *machoFile, uint32_t CSDataStart, uint32_t CSDataSize, void (^enumerateBlock)(struct CSBlob blobDescriptor, uint32_t blobDescriptorOffset, BOOL *stop))
{
	struct CSSuperBlob superBlob;
	fseek(machoFile, CSDataStart, SEEK_SET);
	fread(&superBlob, sizeof(superBlob), 1, machoFile);

	uint32_t blobLength = OSSwapBigToHostInt32(superBlob.length);
	uint32_t blobCount = OSSwapBigToHostInt32(superBlob.count);

	if ((CSDataStart + blobLength) > (CSDataStart + CSDataSize)) return;
	if ((sizeof(struct CSSuperBlob) + blobCount * sizeof(struct CSBlob)) > blobLength) return;

	for (int i = 0; i < blobCount; i++) {
		uint32_t blobDescriptorOffset = CSDataStart + sizeof(struct CSSuperBlob) + (i * sizeof(struct CSBlob));
		struct CSBlob blobDescriptor;
		fseek(machoFile, blobDescriptorOffset, SEEK_SET);
		fread(&blobDescriptor, sizeof(blobDescriptor), 1, machoFile);

		BOOL stop = NO;
		enumerateBlock(blobDescriptor, blobDescriptorOffset, &stop);
		if (stop) return;
	}
}

NSData *codeDirectoryCalculateCDHash(CS_CodeDirectory *cd, void *data, size_t size)
{
	uint8_t cdHashC[CS_CDHASH_LEN];

	switch (cd->hashType) {
		case CS_HASHTYPE_SHA160_160: {
			CC_SHA1(data, (CC_LONG)size, cdHashC);
			break;
		}
		
		case CS_HASHTYPE_SHA256_256:
		case CS_HASHTYPE_SHA256_160: {
			uint8_t fullHash[CC_SHA256_DIGEST_LENGTH];
			CC_SHA256(data, (CC_LONG)size, fullHash);
			memcpy(cdHashC, fullHash, CS_CDHASH_LEN);
			break;
		}

		case CS_HASHTYPE_SHA384_384: {
			uint8_t fullHash[CC_SHA384_DIGEST_LENGTH];
			CC_SHA256(data, (CC_LONG)size, fullHash);
			memcpy(cdHashC, fullHash, CS_CDHASH_LEN);
			break;
		}

		default:
		return nil;
	}

	return [NSData dataWithBytes:cdHashC length:CS_CDHASH_LEN];
}

NSData *machoCSDataCalculateCDHash(FILE *machoFile, uint32_t CSDataStart, uint32_t CSDataSize)
{
	__block CS_CodeDirectory bestCd = { 0 };
	__block unsigned bestCdRank = 0;
	__block uint32_t cdOffset = 0;

	machoCSDataEnumerateBlobs(machoFile, CSDataStart, CSDataSize, ^(struct CSBlob blobDescriptor, uint32_t blobDescriptorOffset, BOOL *stop) {
		uint32_t blobType = OSSwapBigToHostInt32(blobDescriptor.type);
		if (blobType == CSSLOT_CODEDIRECTORY || ((CSSLOT_ALTERNATE_CODEDIRECTORIES <= blobType && blobType < CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT))) {
			uint32_t blobDataOffset = OSSwapBigToHostInt32(blobDescriptor.offset);
			uint32_t blobMagic = 0;

			if ((blobDataOffset + sizeof(CS_CodeDirectory)) > CSDataSize) {
				// file corrupted, abort
				*stop = YES;
				return;
			}

			fseek(machoFile, CSDataStart + blobDataOffset, SEEK_SET);
			fread(&blobMagic, sizeof(blobMagic), 1, machoFile);
			if (OSSwapBigToHostInt32(blobMagic) == CS_MAGIC_CODEDIRECTORY) {
				CS_CodeDirectory cd;
				fseek(machoFile, CSDataStart + blobDataOffset, SEEK_SET);
				fread(&cd, sizeof(cd), 1, machoFile);

				unsigned codeDirectoryRank = CSCodeDirectoryRank(&cd);
				if (codeDirectoryRank > bestCdRank) {
					bestCdRank = codeDirectoryRank;
					bestCd = cd;
					cdOffset = OSSwapBigToHostInt32(blobDescriptor.offset);
				}
			}
		}
	});

	if (!cdOffset) return nil;

	uint32_t cdDataLength = OSSwapBigToHostInt32(bestCd.length);
	if (((cdOffset + cdDataLength) > CSDataSize) || cdDataLength == 0) {
		// file corrupted, abort
		return nil;
	}

	uint8_t *cdData = malloc(cdDataLength);
	if (!cdData) return nil;

	fseek(machoFile, CSDataStart + cdOffset, SEEK_SET);
	fread(cdData, cdDataLength, 1, machoFile);	

	NSData *cdHash = codeDirectoryCalculateCDHash(&bestCd, cdData, cdDataLength);
	free(cdData);
	return cdHash;
}

bool machoCSDataIsAdHocSigned(FILE *machoFile, uint32_t CSDataStart, uint32_t CSDataSize)
{
	__block bool blobWrapperFound = false;

	machoCSDataEnumerateBlobs(machoFile, CSDataStart, CSDataSize, ^(struct CSBlob blobDescriptor, uint32_t blobDescriptorOffset, BOOL *stop) {
		uint32_t blobType = OSSwapBigToHostInt32(blobDescriptor.type);
		if (blobType == CSSLOT_SIGNATURESLOT) {
			uint32_t blobDataOffset = OSSwapBigToHostInt32(blobDescriptor.offset);

			if ((blobDataOffset + sizeof(CS_BlobWrapper)) > CSDataSize) {
				// file corrupted, abort
				*stop = YES;
				return;
			}

			CS_BlobWrapper blobWrapper;
			fseek(machoFile, CSDataStart + blobDataOffset, SEEK_SET);
			fread(&blobWrapper, sizeof(blobWrapper), 1, machoFile);
			if (OSSwapBigToHostInt32(blobWrapper.magic) == CS_MAGIC_BLOB_WRAPPER) {
				if (OSSwapBigToHostInt32(blobWrapper.length) > 8) {
					blobWrapperFound = true;
					*stop = YES;
				}
			}
		}
	});

	return !blobWrapperFound;
}
