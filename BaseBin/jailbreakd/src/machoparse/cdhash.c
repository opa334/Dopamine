/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2018 Brandon Azad
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

/*
 * This is forked from https://github.com/bazad/blanket/blob/master/amfidupe/cdhash.c
 *
 * Notable changes:
 *   1. 32bit binary support
 *   2. Endianness handling
 *   3. FAT support
 */

/*
 * Cdhash computation
 * ------------------
 *
 *  The amfid patch needs to be able to compute the cdhash of a binary.
 *  This code is heavily based on the implementation in Ian Beer's triple_fetch project [1] and on
 *  the source of XNU [2].
 *
 *  [1]: https://bugs.chromium.org/p/project-zero/issues/detail?id=1247
 *  [2]: https://opensource.apple.com/source/xnu/xnu-4570.41.2/bsd/kern/ubc_subr.c.auto.html
 *
 */
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <CommonCrypto/CommonCrypto.h>

#if __APPLE__
#	include <libkern/OSByteOrder.h>
#	define bswap32(x) OSSwapInt32(x)
#	define be32toh(x) OSSwapBigToHostInt32(x)
#elif __has_include(<endian.h>)
#	include <endian.h>
#	define bswap32(x) __builtin_bswap32(x)
#else
#	include <sys/endian.h>
#endif

#include "cdhash.h"
#include "cs_blobs.h"
#include "macho.h"

#define ERROR(x, ...)
#define DEBUG_TRACE(x, y, ...)

static uint32_t
swap(const void *h, const void *h2, const uint32_t s) {
	uint32_t magic = *((uint32_t*)(h == NULL ? h2 : h));
	if (magic == MH_CIGAM || magic == MH_CIGAM_64)
		return bswap32(s);
	else
		return s;
}

// Check whether the file looks like a Mach-O file.
static bool
macho_identify(const struct mach_header_64 *mh, const struct mach_header *mh32, size_t size) {
	uint32_t magic = mh != NULL ? mh->magic : mh32->magic;
	// Check the file size and magic.
	if (size < 0x1000 || (magic != MH_MAGIC_64 &&
				magic != MH_CIGAM_64 && magic != MH_MAGIC &&
				magic != MH_CIGAM)) {
		return false;
	}
	return true;
}

// Get the next load command in a Mach-O file.
static const void *
macho_next_load_command(const struct mach_header_64 *mh, const struct mach_header *mh32, const void *lc) {
	const struct load_command *next = lc;

	if (next == NULL) {
		if (mh != NULL)
			next = (const struct load_command *)(mh + 1);
		else
			next = (const struct load_command *)(mh32 + 1);
	} else {
		next = (const struct load_command *)((uint8_t *)next + swap(mh, mh32, next->cmdsize));
	}
	if (mh != NULL) {
		if ((uintptr_t)next >= (uintptr_t)(mh + 1) + swap(mh, mh32, mh->sizeofcmds)) {
			next = NULL;
		}
	} else {
		if ((uintptr_t)next >= (uintptr_t)(mh32 + 1) + swap(mh, mh32, mh32->sizeofcmds)) {
			next = NULL;
		}
	}
	return next;
}

// Find the next load command in a Mach-O file matching the given type.
static const void *
macho_find_load_command(const struct mach_header_64 *mh, const struct mach_header *mh32, uint32_t command, const void *lc) {
	const struct load_command *loadcmd = lc;
	for (;;) {
		loadcmd = macho_next_load_command(mh, mh32, loadcmd);
		if (loadcmd == NULL || swap(mh, mh32, loadcmd->cmd) == command) {
			return loadcmd;
		}
	}
}

// Validate a CS_CodeDirectory and return its true length.
static size_t
cs_codedirectory_validate(CS_CodeDirectory *cd, size_t size) {
	// Make sure we at least have a CS_CodeDirectory. There's an end_earliest parameter, but
	// XNU doesn't seem to use it in cs_validate_codedirectory().
	if (size < sizeof(*cd)) {
		ERROR("CS_CodeDirectory is too small\n");
		return 0;
	}
	// Validate the magic.
	uint32_t magic = be32toh(cd->magic);
	if (magic != CSMAGIC_CODEDIRECTORY) {
		ERROR("CS_CodeDirectory has incorrect magic\n");
		return 0;
	}
	// Validate the length.
	uint32_t length = be32toh(cd->length);
	if (length > size) {
		ERROR("CS_CodeDirectory has invalid length\n");
		return 0;
	}
	return length;
}

// Validate a CS_SuperBlob and return its true length.
static size_t
cs_superblob_validate(CS_SuperBlob *sb, size_t size) {
	// Make sure we at least have a CS_SuperBlob.
	if (size < sizeof(*sb)) {
		ERROR("CS_SuperBlob is too small\n");
		return 0;
	}
	// Validate the magic.
	uint32_t magic = be32toh(sb->magic);
	if (magic != CSMAGIC_EMBEDDED_SIGNATURE) {
		ERROR("CS_SuperBlob has incorrect magic\n");
		return 0;
	}
	// Validate the length.
	uint32_t length = be32toh(sb->length);
	if (length > size) {
		ERROR("CS_SuperBlob has invalid length\n");
		return 0;
	}
	uint32_t count = be32toh(sb->count);
	// Validate the count.
	CS_BlobIndex *index = &sb->index[count];
	if (count >= 0x10000 || (uintptr_t)index > (uintptr_t)sb + size) {
		ERROR("CS_SuperBlob has invalid count\n");
		return 0;
	}
	return length;
}

// Compute the cdhash of a code directory using SHA1.
static void
cdhash_sha1(CS_CodeDirectory *cd, size_t length, void *cdhash) {
	uint8_t digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1((void*)cd, length, digest);
	memcpy(cdhash, digest, CS_CDHASH_LEN);
}

// Compute the cdhash of a code directory using SHA256.
static void
cdhash_sha256(CS_CodeDirectory *cd, size_t length, void *cdhash) {
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256((void*)cd, length, digest);
	memcpy(cdhash, digest, CS_CDHASH_LEN);
}

// Compute the cdhash of a code directory using SHA384.
static void
cdhash_sha384(CS_CodeDirectory *cd, size_t length, void *cdhash) {
	uint8_t digest[CC_SHA384_DIGEST_LENGTH];
	CC_SHA384((void*)cd, length, digest);
	memcpy(cdhash, digest, CS_CDHASH_LEN);
}

// Compute the cdhash from a CS_CodeDirectory.
static bool
cs_codedirectory_cdhash(CS_CodeDirectory *cd, struct hashes *cdhash) {
	size_t length = be32toh(cd->length);
	switch (cd->hashType) {
		case CS_HASHTYPE_SHA1:
			DEBUG_TRACE(2, "Using SHA1\n");
			cdhash_sha1(cd, length, cdhash->cdhash);
			cdhash->hash_type = CS_HASHTYPE_SHA1;
			return true;
		case CS_HASHTYPE_SHA256:
			DEBUG_TRACE(2, "Using SHA256\n");
			cdhash_sha256(cd, length, cdhash->cdhash);
			cdhash->hash_type = CS_HASHTYPE_SHA256;
			return true;
		case CS_HASHTYPE_SHA384:
			DEBUG_TRACE(2, "Using SHA384\n");
			cdhash_sha384(cd, length, cdhash->cdhash);
			cdhash->hash_type = CS_HASHTYPE_SHA384;
			return true;
	}
	ERROR("Unsupported hash type %d\n", cd->hashType);
	return false;
}

// Get the rank of a code directory.
static unsigned
cs_codedirectory_rank(CS_CodeDirectory *cd) {
	// The supported hash types, ranked from least to most preferred. From XNU's
	// bsd/kern/ubc_subr.c.
	static uint32_t ranked_hash_types[] = {
		CS_HASHTYPE_SHA1,
		CS_HASHTYPE_SHA256_TRUNCATED,
		CS_HASHTYPE_SHA256,
		CS_HASHTYPE_SHA384,
	};
	// Define the rank of the code directory as its index in the array plus one.
	for (unsigned i = 0; i < sizeof(ranked_hash_types) / sizeof(ranked_hash_types[0]); i++) {
		if (ranked_hash_types[i] == cd->hashType) {
			return (i + 1);
		}
	}
	return 0;
}

// Compute the cdhash from a CS_SuperBlob.
static bool
cs_superblob_cdhash(CS_SuperBlob *sb, size_t size, void *cdhash) {
	// Iterate through each index searching for the best code directory.
	CS_CodeDirectory *best_cd = NULL;
	unsigned best_cd_rank = 0;
	uint32_t count = be32toh(sb->count);
	for (size_t i = 0; i < count; i++) {
		CS_BlobIndex *index = &sb->index[i];
		uint32_t type = be32toh(index->type);
		uint32_t offset = be32toh(index->offset);
		// Validate the offset.
		if (offset > size) {
			ERROR("CS_SuperBlob has out-of-bounds CS_BlobIndex\n");
			return false;
		}
		// Look for a code directory.
		if (type == CSSLOT_CODEDIRECTORY ||
				(CSSLOT_ALTERNATE_CODEDIRECTORIES <= type && type < CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT)) {
			CS_CodeDirectory *cd = (CS_CodeDirectory *)((uint8_t *)sb + offset);
			size_t cd_size = cs_codedirectory_validate(cd, size - offset);
			if (cd_size == 0) {
				return false;
			}
			DEBUG_TRACE(2, "CS_CodeDirectory { hashType = %u }\n", cd->hashType);
			// Rank the code directory to see if it's better than our previous best.
			unsigned cd_rank = cs_codedirectory_rank(cd);
			if (cd_rank > best_cd_rank) {
				best_cd = cd;
				best_cd_rank = cd_rank;
			}
		}
	}
	// If we didn't find a code directory, error.
	if (best_cd == NULL) {
		ERROR("CS_SuperBlob does not have a code directory\n");
		return false;
	}
	// Hash the code directory.
	return cs_codedirectory_cdhash(best_cd, cdhash);
}

// Compute the cdhash from a csblob.
static bool
csblob_cdhash(CS_GenericBlob *blob, size_t size, void *cdhash) {
	// Make sure we at least have a CS_GenericBlob.
	if (size < sizeof(*blob)) {
		ERROR("CSBlob is too small\n");
		return false;
	}
	uint32_t magic = be32toh(blob->magic);
	uint32_t length = be32toh(blob->length);
	DEBUG_TRACE(2, "CS_GenericBlob { %08x, %u }, size = %zu\n", magic, length, size);
	// Make sure the length is sensible.
	if (length > size) {
		ERROR("CSBlob has invalid length\n");
		return false;
	}
	// Handle the blob.
	bool ok;
	switch (magic) {
		case CSMAGIC_EMBEDDED_SIGNATURE:
			ok = cs_superblob_validate((CS_SuperBlob *)blob, length);
			if (!ok) {
				return false;
			}
			return cs_superblob_cdhash((CS_SuperBlob *)blob, length, cdhash);
		case CSMAGIC_CODEDIRECTORY:
			ok = cs_codedirectory_validate((CS_CodeDirectory *)blob, length);
			if (!ok) {
				return false;
			}
			return cs_codedirectory_cdhash((CS_CodeDirectory *)blob, cdhash);
	}
	ERROR("Unrecognized CSBlob magic 0x%08x\n", magic);
	return false;
}

// Compute the cdhash for a Mach-O file.
static bool
compute_cdhash_macho(const struct mach_header_64 *mh, const struct mach_header *mh32, size_t size, struct hashes *cdhash) {
	// Find the code signature command.
	const struct linkedit_data_command *cs_cmd =
		macho_find_load_command(mh, mh32, LC_CODE_SIGNATURE, NULL);
	if (cs_cmd == NULL) {
		ERROR("No code signature\n");
		return false;
	}
	const uint8_t *cs_data, *cs_end;
	// Check that the code signature is in-bounds.
	if (mh != NULL) {
		cs_data = (const uint8_t *)mh + swap(mh, NULL, cs_cmd->dataoff);
		cs_end = cs_data + swap(mh, NULL, cs_cmd->datasize);
		if (!((uint8_t *)mh < cs_data && cs_data < cs_end && cs_end <= (uint8_t *)mh + size)) {
			ERROR("Invalid code signature\n");
			return false;
		}
	} else {
		cs_data = (const uint8_t *)mh32 + swap(mh32, NULL, cs_cmd->dataoff);
		cs_end = cs_data + swap(mh32, NULL, cs_cmd->datasize);
		if (!((uint8_t *)mh32 < cs_data && cs_data < cs_end && cs_end <= (uint8_t *)mh32 + size)) {
			ERROR("Invalid code signature\n");
			return false;
		}
	}
	// Check that the code signature data looks correct.
	return csblob_cdhash((CS_GenericBlob *)cs_data, cs_end - cs_data, cdhash);
}

static bool
compute_cdhash(const void *file, size_t size, struct hashes *cdhash) {
	// Try to compute the cdhash for a Mach-O file.
	const struct mach_header_64 *mh = file;
	const struct mach_header *mh32 = file;
	if (mh->magic == MH_MAGIC_64 || mh->magic == MH_CIGAM_64) {
		mh32 = NULL;
	} else {
		mh = NULL;
	}

	if (macho_identify(mh, mh32, size)) {
		//if (!macho_validate(mh, mh32, size)) {
		//	ERROR("Bad Mach-O file\n");
		//	return false;
		//}
		return compute_cdhash_macho(mh, mh32, size, cdhash);
	}
	// What is it?
	ERROR("Unrecognized file format\n");
	return false;
}

static void
compute_cdhashes(const void *file, size_t size, struct cdhashes *h) {
	const struct fat_header *fh = NULL;
	if (*((uint32_t*)file) == FAT_MAGIC || *((uint32_t*)file) == FAT_CIGAM)
		fh = file;

	if (fh != NULL) {
		struct fat_arch *fa = (struct fat_arch *)(fh + 1);
		h->h = malloc(sizeof(struct hashes) * be32toh(fh->nfat_arch));
		for (uint32_t i = 0; i < be32toh(fh->nfat_arch); i++) {
			if (compute_cdhash(file + be32toh(fa->offset), be32toh(fa->size), &h->h[h->count])) {
				h->count++;
			} else {
				// If any slice is not signed we will just skip the whole binary
				free(h->h);
				h->h = 0;
				h->count = 0;
				return;
			}
			fa++;
		}
	} else {
		h->h = malloc(sizeof(struct hashes));
		h->count = compute_cdhash(file, size, &h->h[0]);
		if (h->count == 0) {
			free(h->h);
			h->h = 0;
		}
	}
}

int
find_cdhash(const char *path, const struct stat *sb, struct cdhashes *h) {
	int success = 0;
	size_t fileoff = 0;

	int fd;
	fd = open(path, O_RDONLY);
	if (fd < 0) {
		ERROR("Could not open \"%s\"\n", path);
		goto fail_0;
	}
	size_t size = sb->st_size;
	// Map the file into memory.
	DEBUG_TRACE(2, "Mapping %s size %zu offset %zu\n", path, size, fileoff);
	size -= fileoff;
	uint8_t *file = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, fileoff);
	if (file == MAP_FAILED) {
		ERROR("Could not map \"%s\"\n", path);
		goto fail_1;
	}
	DEBUG_TRACE(3, "file[0] = %lx\n", *(uint64_t *)file);
	// Compute the cdhash.
	compute_cdhashes(file, size, h);
	success = true;

	munmap(file, size);
fail_1:
	close(fd);
fail_0:
	return success;
}
