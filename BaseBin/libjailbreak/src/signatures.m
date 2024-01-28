#include <choma/FAT.h>
#include <choma/MachO.h>
#include <choma/Host.h>
#include <mach-o/dyld.h>
#include "trustcache.h"

#import <Foundation/Foundation.h>

MachO *ljb_fat_find_preferred_slice(FAT *fat)
{
	cpu_type_t cputype;
	cpu_subtype_t cpusubtype;
	if (host_get_cpu_information(&cputype, &cpusubtype) != 0) { return NULL; }
	
	MachO *candidateSlice = NULL;

	if (cpusubtype == CPU_SUBTYPE_ARM64E)
	{
		// New arm64e ABI
		candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2);
		if (!candidateSlice) {
			// Old arm64e ABI
			candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E);
			if (candidateSlice) {
				// If we found an old arm64e slice, make sure this is a library! If it's a binary, skip!!!
				// For binaries the system will fall back to the arm64 slice, which has the CDHash that we want to add
				if (macho_get_filetype(candidateSlice) == MH_EXECUTE) candidateSlice = NULL;
			}
		}
	}

	if (!candidateSlice) {
		// On iOS 15+ the kernels prefers ARM64_V8 to ARM64_ALL
		candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_V8);
		if (!candidateSlice) {
			candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_ALL);
		}
	}

	return candidateSlice;
}

bool csd_superblob_is_adhoc_signed(CS_DecodedSuperBlob *superblob)
{
	CS_DecodedBlob *wrapperBlob = csd_superblob_find_blob(superblob, CSSLOT_SIGNATURESLOT, NULL);
	if (wrapperBlob) {
		if (csd_blob_get_size(wrapperBlob) > 8) {
			return false;
		}
	}
	return true;
}

NSString *processRpaths(NSString *path, NSString *symbol, NSArray *rpaths)
{
	if (!rpaths) return path;

	if ([path containsString:symbol]) {
		for (NSString *rpath in rpaths) {
			NSString *testPath = [path stringByReplacingOccurrencesOfString:symbol withString:rpath];
			if ([[NSFileManager defaultManager] fileExistsAtPath:testPath]) {
				return testPath;
			}
		}
	}
	return path;
}

NSString *resolveLoadPath(NSString *dylibPath, NSString *loaderPath, NSString *executablePath, NSArray *rpaths)
{
	if (!dylibPath || !loaderPath) return nil;

	NSString *processedPath = dylibPath;

	// XXX: The order of these seems off?
	processedPath = processRpaths(processedPath, @"@rpath", rpaths);
	processedPath = processRpaths(processedPath, @"@executable_path", rpaths);
	processedPath = processRpaths(processedPath, @"@loader_path", rpaths);
	processedPath = [processedPath stringByReplacingOccurrencesOfString:@"@executable_path" withString:[executablePath stringByDeletingLastPathComponent]];
	processedPath = [processedPath stringByReplacingOccurrencesOfString:@"@loader_path" withString:[loaderPath stringByDeletingLastPathComponent]];

	return processedPath;
}

void macho_collect_untrusted_cdhashes(const char *path, const char *callerPath, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	@autoreleasepool {
		if (!path) return;
		if (access(path, R_OK) != 0) return;

		__block cdhash_t *cdhashes = NULL;
		__block uint32_t cdhashCount = 0;

		bool (^cdhashesContains)(cdhash_t) = ^bool(cdhash_t cdhash) {
			for (int i = 0; i < cdhashCount; i++) {
				if (!memcmp(cdhashes[i], cdhash, sizeof(cdhash_t))) {
					return true;
				}
			}
			return false;
		};

		void (^cdhashesAdd)(cdhash_t) = ^(cdhash_t cdhash) {
			cdhashCount++;
			cdhashes = realloc(cdhashes, cdhashCount * sizeof(cdhash_t));
			memcpy(cdhashes[cdhashCount-1], cdhash, sizeof(cdhash_t));
		};

		FAT *mainFAT = fat_init_from_path(path);
		if (!mainFAT) return;
		MachO *mainMachO = ljb_fat_find_preferred_slice(mainFAT);
		if (!mainMachO) {
			fat_free(mainFAT);
			return;
		}
		if (macho_get_filetype(mainMachO) == MH_EXECUTE) {
			callerPath = path;
		}

		__weak __block void (^machoAddHandler_recurse)(MachO *, const char *);
		void (^machoAddHandler)(MachO *, const char *) = ^(MachO *macho, const char *machoPath) {
			// Calculate cdhash and add it to our array
			bool cdhashWasKnown = true;
			bool isAdhocSigned = false;
			CS_SuperBlob *superblob = macho_read_code_signature(macho);
			if (superblob) {
				CS_DecodedSuperBlob *decodedSuperblob = csd_superblob_decode(superblob);
				if (decodedSuperblob) {
					if (csd_superblob_is_adhoc_signed(decodedSuperblob)) {
						isAdhocSigned = true;
						cdhash_t cdhash;
						if (csd_superblob_calculate_best_cdhash(decodedSuperblob, cdhash) == 0) {
							if (!cdhashesContains(cdhash)) {
								if (!is_cdhash_trustcached(cdhash)) {
									// If something is trustcached we do not want to add it to your array
									// We do want to parse it's dependencies however, as one may have been updated since we added the binary to trustcache
									// Potential optimization: If trustcached, save in some array so we don't recheck
									cdhashesAdd(cdhash);
								}
								cdhashWasKnown = false;
							}
						}
					}
					csd_superblob_free(decodedSuperblob);
				}
				free(superblob);
			}

			if (cdhashWasKnown) return; // If we already knew the cdhash, we can skip parsing dependencies
			if (!isAdhocSigned) return; // If it was not ad hoc signed, we can safely skip it aswell

			// Collect rpaths...
			NSMutableArray *rpaths = [NSMutableArray new];
			macho_enumerate_rpaths(macho, ^(const char *rpathC, bool *stop) {
				NSString *rpath = [NSString stringWithUTF8String:rpathC];
				[rpaths addObject:rpath];
			});

			// Recurse this block on all dependencies
			macho_enumerate_dependencies(macho, ^(const char *dylibPathC, uint32_t cmd, struct dylib* dylib, bool *stop) {
				if (_dyld_shared_cache_contains_path(dylibPathC)) return;
				NSString *dylibPath = [NSString stringWithUTF8String:dylibPathC];
				NSString *loaderPath = [NSString stringWithUTF8String:machoPath];
				NSString *executablePath = callerPath ? [NSString stringWithUTF8String:callerPath] : loaderPath;
				dylibPath = resolveLoadPath(dylibPath, loaderPath, executablePath, rpaths);
				if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
					FAT *dependencyFAT = fat_init_from_path(dylibPath.fileSystemRepresentation);
					if (dependencyFAT) {
						MachO *dependencyMacho = ljb_fat_find_preferred_slice(dependencyFAT);
						if (dependencyMacho) {
							machoAddHandler_recurse(dependencyMacho, dylibPath.fileSystemRepresentation);
						}
						fat_free(dependencyFAT);
					}
				}
			});
		};
		machoAddHandler_recurse = machoAddHandler;

		machoAddHandler(mainMachO, path);
		fat_free(mainFAT);

		*cdhashesOut = cdhashes;
		*cdhashCountOut = cdhashCount;
	}
}