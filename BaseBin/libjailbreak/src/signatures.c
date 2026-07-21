#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <choma/MachO.h>
#include <choma/Fat.h>
#include <choma/MemoryStream.h>
#include <choma/FileStream.h>
#include <choma/CSBlob.h>
#include <choma/CodeDirectory.h>
#include <choma/Util.h>
#include <choma/Host.h>
#include <mach-o/dyld.h>
#include "trustcache.h"

bool macho_is_mappable(MachO *macho)
{
	// Determine if there is any case in which the macho could be mapped

	struct mach_header *header = macho_get_mach_header(macho);

	cpu_type_t cputype = header->cputype;
	cpu_subtype_t cpusubtype = header->cpusubtype;
	bool isLibrary = (header->filetype == MH_EXECUTE);

	if (cputype != CPU_TYPE_ARM64) return false;

#ifdef __arm64e__

	if (cpusubtype == (CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2)) {
		// New arm64e ABI always mappable on arm64e
		return true;
	}
	else if (cpusubtype == CPU_SUBTYPE_ARM64E && isLibrary) {
		// Old arm64e ABI only mappable for libraries on arm64e iOS 14.6+
		return true;
	}

#endif

	// Anything arm64 is always mappable on all dvices
	if ((cpusubtype == CPU_SUBTYPE_ARM64_V8) || (cpusubtype == CPU_SUBTYPE_ARM64_ALL)) return true;

	return false;
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

bool code_signature_calculate_adhoc_cdhash(CS_SuperBlob *superblob, cdhash_t cdhashOut)
{
	bool isAdhocSigned = false;

	CS_DecodedSuperBlob *decodedSuperblob = csd_superblob_decode(superblob);
	if (decodedSuperblob) {
		if (csd_superblob_is_adhoc_signed(decodedSuperblob)) {
			if (csd_superblob_calculate_best_cdhash(decodedSuperblob, cdhashOut, NULL) == 0) {
				isAdhocSigned = true;
			}
		}
		csd_superblob_free(decodedSuperblob);
	}

	return isAdhocSigned;
}

bool macho_parse_code_signature(MachO *macho, cdhash_t cdhashOut)
{
	bool isAdhocSigned = false;

	CS_SuperBlob *superblob = macho_read_code_signature(macho);
	if (superblob) {
		isAdhocSigned = code_signature_calculate_adhoc_cdhash(superblob, cdhashOut);
		free(superblob);
	}

	return isAdhocSigned;
}

void fat_collect_untrusted_cdhashes(Fat *fat, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	__block cdhash_t *cdhashes = NULL;
	__block uint32_t cdhashCount = 0;
	fat_enumerate_slices(fat, ^(MachO *macho, bool *stop) {
		if (macho_is_mappable(macho)) {
			cdhash_t cdhash;
			if (macho_parse_code_signature(macho, cdhash)) {
				if (!is_cdhash_trustcached(cdhash)) {
					cdhashCount++;
					cdhashes = realloc(cdhashes, cdhashCount * sizeof(cdhash_t));
					memcpy(cdhashes[cdhashCount-1], cdhash, sizeof(cdhash));
				}
			}
		}
	});

	*cdhashesOut = cdhashes;
	*cdhashCountOut = cdhashCount;
}

void file_collect_untrusted_cdhashes(int fd, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	MemoryStream *s = file_stream_init_from_file_descriptor(fd, 0, FILE_STREAM_SIZE_AUTO, 0);
	if (!s) return;

	Fat *fat = fat_init_from_memory_stream(s);
	if (!fat) {
		memory_stream_free(s);
		return;
	}

	fat_collect_untrusted_cdhashes(fat, cdhashesOut, cdhashCountOut);

	fat_free(fat);
}

void file_collect_untrusted_cdhashes_by_path(const char *path, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) return;
	file_collect_untrusted_cdhashes(fd, cdhashesOut, cdhashCountOut);
	close(fd);
}