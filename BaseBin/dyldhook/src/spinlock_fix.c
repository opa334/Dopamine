#if IOS==15 && __arm64e__

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sandbox.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <sys/mman.h>
#define TARGET_OS_SIMULATOR 0
#include <dyld_cache_format.h>

#include "machomerger_hook.h"

char *__locate_dsc(void)
{
	// We make two assumptions here
	// 1. This code is only called on iOS 15 arm64e (since the spinlock panic doesn't affect anything else)
	// 2. This code is only called if the shared cache has been mapped in via a shared region
	// For these reasons, we can just hardcode the path
	return "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e";
}

void __dsc_file_enumerate_mappings(int fd, struct dyld_cache_header *header, uintptr_t slide, bool (*enumeratorFunc)(int fd, struct dyld_cache_header *header, uintptr_t slide, struct dyld_cache_mapping_info *mapping))
{
	struct dyld_cache_mapping_info mappingInfos[header->mappingCount];
	lseek(fd, header->mappingOffset, SEEK_SET);
	if (read(fd, mappingInfos, sizeof(struct dyld_cache_mapping_info) * header->mappingCount) != sizeof(struct dyld_cache_mapping_info) * header->mappingCount) return;

	for (uint32_t i = 0; i < header->mappingCount; i++) {
		struct dyld_cache_mapping_info *mapping = &mappingInfos[i];
		enumeratorFunc(fd, header, slide, mapping);
	}
}

void __dsc_enumerate_mappings(uintptr_t slide, bool (*enumeratorFunc)(int fd, struct dyld_cache_header *header, uintptr_t slide, struct dyld_cache_mapping_info *mapping))
{
	char *dscPath = __locate_dsc();

	int dscFd = open(dscPath, O_RDONLY);
	if (dscFd < 0) return;

	struct dyld_cache_header header;
	if (read(dscFd, &header, sizeof(header)) != sizeof(header)) { close(dscFd); return; }

	__dsc_file_enumerate_mappings(dscFd, &header, slide, enumeratorFunc);

	struct dyld_subcache_entry_v1 subcacheEntries[header.subCacheArrayCount];
	lseek(dscFd, header.subCacheArrayOffset, SEEK_SET);
	if (read(dscFd, subcacheEntries, sizeof(struct dyld_subcache_entry_v1) * header.subCacheArrayCount) != sizeof(struct dyld_subcache_entry_v1) * header.subCacheArrayCount) { close(dscFd); return; };

	for (uint32_t i = 0; i < header.subCacheArrayCount; i++) {
		char subcachePath[PATH_MAX];
		strcpy(subcachePath, dscPath);

		// Only supports 1-9
		// Since iOS 15 usually only has one subcache, this shall be fine
		char suffix[3];
		suffix[0] = '.';
		suffix[1] = '1' + i;
		suffix[2] = '\0';
		strcat(subcachePath, suffix);

		int subcacheFd = open(subcachePath, O_RDONLY);
		if (subcacheFd >= 0) {
			struct dyld_cache_header subcacheHeader;
			if (read(subcacheFd, &subcacheHeader, sizeof(subcacheHeader)) != sizeof(subcacheHeader)) continue;
			__dsc_file_enumerate_mappings(subcacheFd, &subcacheHeader, slide, enumeratorFunc);
			close(subcacheFd);
		}
	}

	close(dscFd);
}

int __dsc_attach_signature(int fd, struct dyld_cache_header *header)
{
	fsignatures_t siginfo;
    siginfo.fs_file_start = 0;
    siginfo.fs_blob_start = (void*)header->codeSignatureOffset;
    siginfo.fs_blob_size  = (size_t)(header->codeSignatureSize);
    return fcntl(fd, F_ADDFILESIGS_RETURN, &siginfo);
}

bool __dsc_mapping_make_private(int fd, struct dyld_cache_header *header, uintptr_t slide, struct dyld_cache_mapping_info *mapping)
{
	if (mapping->initProt & PROT_EXEC) {
		int r = __dsc_attach_signature(fd, header);
		if (r == 0) {
			void *r = mmap((void *)(mapping->address + slide), mapping->size, PROT_READ | PROT_EXEC, MAP_FIXED | MAP_PRIVATE, fd, mapping->fileOffset);
		}
	}
	return true;
}

void dyld_make_dsc_text_private(uintptr_t slide)
{
	__dsc_enumerate_mappings(slide, __dsc_mapping_make_private);
}

extern bool ORIG(_ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE)(uintptr_t options, uintptr_t results);
bool HOOK(_ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE)(uintptr_t options, uintptr_t results)
{
	bool r = ORIG(_ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE)(options, results);

	bool forcePrivate = *(bool *)(options + 8);
	if (!forcePrivate) {
		long slide = *(long *)(results + 8);
		dyld_make_dsc_text_private(slide);
	}

	return r;
}

#endif