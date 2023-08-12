#include "litehook.h"
#include <stdarg.h>
#include <stdbool.h>
#include <sys/types.h>
#include <string.h>
#include <sys/fcntl.h>
#include <mach/mach.h>
#include <mach/arm/kern_return.h>
#include <mach/port.h>
#include <mach/vm_prot.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <libkern/OSCacheControl.h>

static uint64_t __attribute((naked)) __xpaci(uint64_t a)
{
	asm(".long        0xDAC143E0"); // XPACI X0
	asm("ret");
}

uint64_t xpaci(uint64_t a)
{
	// If a looks like a non-pac'd pointer just return it
	if ((a & 0xFFFFFF0000000000) == 0xFFFFFF0000000000) {
		return a;
	}
	return __xpaci(a);
}

uint32_t movk(uint8_t x, uint16_t val, uint16_t lsl)
{
	uint32_t base = 0b11110010100000000000000000000000;

	uint32_t hw = 0;
	if (lsl == 16) {
		hw = 0b01 << 21;
	}
	else if (lsl == 32) {
		hw = 0b10 << 21;
	}
	else if (lsl == 48) {
		hw = 0b11 << 21;
	}

	uint32_t imm16 = (uint32_t)val << 5;
	uint32_t rd = x & 0x1F;

	return base | hw | imm16 | rd;
}

uint32_t br(uint8_t x)
{
	uint32_t base = 0b11010110000111110000000000000000;
	uint32_t rn = ((uint32_t)x & 0x1F) << 5;
	return base | rn;
}

__attribute__((noinline, naked)) volatile kern_return_t litehook_vm_protect(mach_port_name_t target, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection)
{
	__asm("mov x16, #0xFFFFFFFFFFFFFFF2");
	__asm("svc 0x80");
	__asm("ret");
}

kern_return_t litehook_unprotect(vm_address_t addr, vm_size_t size)
{
	return litehook_vm_protect(mach_task_self(), addr, size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
}

kern_return_t litehook_protect(vm_address_t addr, vm_size_t size)
{
	return litehook_vm_protect(mach_task_self(), addr, size, false, VM_PROT_READ | VM_PROT_EXECUTE);
}

int _dyld_image_index_for_header(const void *header)
{
	for (int i = 0; i < _dyld_image_count(); i++) {
		const struct mach_header *checkHeader = _dyld_get_image_header(i);
		if (header == checkHeader) {
			return i;
		}
	}
	return -1;
}

int getSectionBounds(const void *address, mach_vm_address_t *startOut, mach_vm_address_t *endOut) {
	Dl_info info;
	int dlr = dladdr((void *)address, &info);
	if (dlr == 0) return 1;
	const struct mach_header_64 *header = info.dli_fbase;

	int imageIndex = _dyld_image_index_for_header(header);
	
	if (header && imageIndex != -1) {
		intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
		uint64_t unslidAddress = ((uint64_t)address) - slide;
		
		const struct segment_command_64 *segmentCmd = NULL;
		uint32_t segmentCount = 0;
		if (header->magic == MH_MAGIC || header->magic == MH_MAGIC_64) {
			segmentCmd = (const struct segment_command_64 *)(((const char *)header) + sizeof(struct mach_header_64));
			segmentCount = header->ncmds;
		}
		
		for (uint32_t i = 0; i < segmentCount; i++) {
			if (segmentCmd->cmd == LC_SEGMENT || segmentCmd->cmd == LC_SEGMENT_64) {
				if (unslidAddress >= segmentCmd->vmaddr &&
					unslidAddress < segmentCmd->vmaddr + segmentCmd->vmsize) {
					mach_vm_address_t subsectionStart = segmentCmd->vmaddr + slide;
					mach_vm_address_t subsectionEnd = segmentCmd->vmsize;
					*startOut = subsectionStart;
					*endOut = subsectionEnd;
					return 0;
				}
			}
			segmentCmd = (const struct segment_command_64 *)(((const char *)segmentCmd) + segmentCmd->cmdsize);
		}
	}

	return 1;
}

kern_return_t litehook_hook_function(void *source, void *target)
{
	kern_return_t kr = KERN_SUCCESS;

	uint32_t *toHook = (uint32_t*)xpaci((uint64_t)source);
	uint64_t target64 = (uint64_t)xpaci((uint64_t)target);

	mach_vm_address_t regionStart = 0;
	mach_vm_address_t regionSize = 0;
	int suc = getSectionBounds(toHook, &regionStart, &regionSize);
	if (suc != 0) return suc;

	vm_address_t preWarmAllocation = 0;
	kr = vm_allocate(mach_task_self_, &preWarmAllocation, regionSize*2, VM_FLAGS_ANYWHERE);
	if (kr != KERN_SUCCESS) return kr;
	vm_address_t preWarmAllocationEnd = preWarmAllocation + (regionSize*2);
	for (vm_address_t page = preWarmAllocation; page < preWarmAllocationEnd; page += PAGE_SIZE) {
		// page in
		*((volatile uint64_t *)page);
	}
	kr = vm_deallocate(mach_task_self_, preWarmAllocation, regionSize*2);
	if (kr != KERN_SUCCESS) return kr;


	kr = litehook_unprotect((vm_address_t)toHook, 5*4);
	if (kr != KERN_SUCCESS) return kr;

	toHook[0] = movk(16, target64 >> 0, 0);
	toHook[1] = movk(16, target64 >> 16, 16);
	toHook[2] = movk(16, target64 >> 32, 32);
	toHook[3] = movk(16, target64 >> 48, 48);
	toHook[4] = br(16);
	uint32_t hookSize = 5 * sizeof(uint32_t);

	kr = litehook_protect((vm_address_t)toHook, hookSize);
	if (kr != KERN_SUCCESS) return kr;

	sys_icache_invalidate(toHook, hookSize);

	for (mach_vm_address_t page = regionStart; page < regionSize; page += PAGE_SIZE) {
		// page in
		*((volatile uint64_t *)page);
	}

	return KERN_SUCCESS;
}