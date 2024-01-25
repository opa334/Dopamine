#ifndef PRIMITIVES_EXTERNAL_H
#define PRIMITIVES_EXTERNAL_H

struct kernel_primitives {
	int (*kreadbuf)(uint64_t kaddr, void* output, size_t size);
	int (*kwritebuf)(uint64_t kaddr, const void* input, size_t size);
	int (*physreadbuf)(uint64_t physaddr, void* output, size_t size);
	int (*physwritebuf)(uint64_t physaddr, const void* input, size_t size);
	uint64_t (*kcall)(uint64_t func, int argc, const uint64_t *argv);
	int (*kalloc_global)(uint64_t *addr, uint64_t size);
	int (*kalloc_user)(uint64_t *addr, uint64_t size);
	int (*kfree_global)(uint64_t addr, uint64_t size);
	int (*kmap)(uint64_t pa, uint64_t size, void **uaddr);
	uint64_t (*vtophys)(uint64_t ttep, uint64_t va);
	uint64_t (*phystokv)(uint64_t pa);
};

extern struct kernel_primitives gPrimitives;

#endif
