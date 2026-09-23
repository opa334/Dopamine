#include <libjailbreak/memory_hooks.h>
#include <libjailbreak/hookd.h>
#include <libkern/OSCacheControl.h>
#include <stdbool.h>
#include <stdatomic.h>

#include "common.h"

static atomic_bool gMemoryHooksReady = false;

static kern_return_t patch_code(void *address, const void *data, size_t size)
{
	/* Leave each request small enough for the existing hookd message format. */
	const size_t maxChunk = (HOOKD_MSG_MAX_SIZE - sizeof(struct hookd_mach_msg)
		- sizeof(struct hookd_encoded_hook)) & ~(size_t)3;

	if (size == 0) return KERN_SUCCESS;
	if (!address || !data || size > UINTPTR_MAX - (uintptr_t)address) return KERN_INVALID_ARGUMENT;
	if (((uintptr_t)address & 3) || (size & 3)) return KERN_INVALID_ARGUMENT;

	for (size_t offset = 0; offset < size;) {
		size_t chunk = size - offset;
		if (chunk > maxChunk) chunk = maxChunk;
		kern_return_t kr = hookd_hook(mach_task_self_, (uintptr_t)address + offset,
			(uint8_t *)data + offset, chunk);
		if (kr != KERN_SUCCESS) return kr;
		sys_icache_invalidate((uint8_t *)address + offset, chunk);
		offset += chunk;
	}
	return KERN_SUCCESS;
}

static const struct jb_memory_hooks gMemoryHooks = {
	.version = JB_MEMORY_HOOKS_VERSION,
	.size = sizeof(struct jb_memory_hooks),
	.patch_code = patch_code,
	.protect = mach_vm_protect_fixed,
};

void init_memory_hooks(void)
{
	atomic_store_explicit(&gMemoryHooksReady, true, memory_order_release);
}

const struct jb_memory_hooks *jb_get_memory_hooks(uint32_t version)
{
	if (version != JB_MEMORY_HOOKS_VERSION || !atomic_load_explicit(&gMemoryHooksReady, memory_order_acquire)) return NULL;
	return &gMemoryHooks;
}
