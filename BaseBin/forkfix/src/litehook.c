#include "litehook.h"

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

kern_return_t litehook_hook_function(void *source, void *target)
{
	uint32_t *toHook = (uint32_t*)xpaci((uint64_t)source);
	uint64_t target64 = (uint64_t)xpaci((uint64_t)target);

	kern_return_t kr = litehook_unprotect((vm_address_t)toHook, 5*4);
	if (kr != KERN_SUCCESS) return kr;

	toHook[0] = movk(16, target64 >> 0, 0);
	toHook[1] = movk(16, target64 >> 16, 16);
	toHook[2] = movk(16, target64 >> 32, 32);
	toHook[3] = movk(16, target64 >> 48, 48);
	toHook[4] = br(16);

	kr = litehook_protect((vm_address_t)toHook, 5*4);
	if (kr != KERN_SUCCESS) return kr;

	return KERN_SUCCESS;
}