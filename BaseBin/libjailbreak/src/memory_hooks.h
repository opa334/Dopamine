#ifndef JB_MEMORY_HOOKS_H
#define JB_MEMORY_HOOKS_H

#include <mach/mach.h>
#include <stddef.h>
#include <stdint.h>

/* Optional process-local ABI, discovered through dlsym(RTLD_DEFAULT, ...). */
#define JB_MEMORY_HOOKS_VERSION 1

struct jb_memory_hooks {
	uint32_t version;
	uint32_t size;
	/* Address and size must be four-byte aligned. The caller synchronizes threads;
	 * a failure may leave earlier chunks applied. Successful writes restore RX. */
	kern_return_t (*patch_code)(void *address, const void *data, size_t size);
	/* Mach VM semantics, using task-port names from the calling process. */
	kern_return_t (*protect)(mach_port_t task, mach_vm_address_t address,
		mach_vm_size_t size, boolean_t set_maximum, vm_prot_t protection);
};

/* Returns a process-lifetime table, or NULL when unavailable/unsupported. */
const struct jb_memory_hooks *jb_get_memory_hooks(uint32_t version);

#endif
