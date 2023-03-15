#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <Foundation/Foundation.h>

int memcmp_masked(const void *str1, const void *str2, unsigned char *mask, size_t n)
{
	const unsigned char *p = (const unsigned char*)str1;
	const unsigned char *q = (const unsigned char*)str2;

	if (p == q) return 0;

	for (int i = 0; i < n; i++) {
		unsigned char cMask = mask[i];
		if ((p[i] & cMask) != (q[i] & cMask)) {
			// we do not care about 1 / -1
			return -1;
		}
	}

	return 0;
}

void *_patchfind_in_region(vm_address_t startAddr, vm_offset_t regionLength, unsigned char *bytesToSearch, unsigned char *byteMask, size_t byteCount)
{
	if (byteCount < 1) {
		return NULL;
	}

	unsigned int firstByteIndex = 0;
	if (byteMask != NULL) {
		for (size_t i = 0; i < byteCount; i++) {
			if (byteMask[i] == 0xFF) {
				firstByteIndex = i;
				break;
			}
		}
	}

	unsigned char firstByte = bytesToSearch[firstByteIndex];
	vm_address_t curAddr = startAddr;

	while(curAddr < startAddr + regionLength) {
		size_t searchSize = (startAddr - curAddr) + regionLength;
		void *foundPtr = memchr((void*)curAddr,firstByte,searchSize);

		if (foundPtr == NULL) {
			break;
		}

		vm_address_t foundAddr = (vm_address_t)foundPtr;

		// correct foundPtr in respect of firstByteIndex
		foundPtr = (void*)((intptr_t)foundPtr - firstByteIndex);        

		size_t remainingBytes = regionLength - (foundAddr - startAddr);

		if (remainingBytes >= byteCount) {
			int memcmp_res;
			if (byteMask != NULL) {
				memcmp_res = memcmp_masked(foundPtr, bytesToSearch, byteMask, byteCount);
			}
			else {
				memcmp_res = memcmp(foundPtr, bytesToSearch, byteCount);
			}

			if (memcmp_res == 0) {
				return foundPtr;
			}
		}
		else {
			break;
		}

		curAddr = foundAddr + 1;
	}

	return NULL;
}

void *patchfind_seek_back(void *startPtr, uint32_t toInstruction, uint32_t mask, unsigned int maxSearch)
{
	vm_address_t startAddr = (vm_address_t)startPtr;
	vm_address_t curAddr = startAddr;

	while((startAddr - curAddr) < maxSearch) {
		void *curPtr = (void*)curAddr;
		uint32_t curInst = *(uint32_t*)curPtr;

		if ((curInst & mask) == (toInstruction & mask)) {
			return curPtr;
		}

		curAddr = curAddr - 1;
	}

	return NULL;
}

void *patchfind_find(int imageIndex, unsigned char *bytesToSearch, unsigned char *byteMask, size_t byteCount)
{
	intptr_t baseAddr = _dyld_get_image_vmaddr_slide(imageIndex);
	struct mach_header_64 *header = (struct mach_header_64*)_dyld_get_image_header(imageIndex);

	const struct segment_command_64 *cmd;

	uintptr_t addr = (uintptr_t)(header + 1);
	uintptr_t endAddr = addr + header->sizeofcmds;

	for (int ci = 0; ci < header->ncmds && addr <= endAddr; ci++) {
		cmd = (typeof(cmd))addr;

		addr = addr + cmd->cmdsize;

		if (cmd->cmd != LC_SEGMENT_64 || strcmp(cmd->segname, "__TEXT")) {
			continue;
		}

		return _patchfind_in_region(cmd->vmaddr + baseAddr, cmd->vmsize, bytesToSearch, byteMask, byteCount);
	}

	return NULL;
}