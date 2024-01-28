#ifndef PRIMITIVES_EXTERNAL_H
#define PRIMITIVES_EXTERNAL_H

typedef struct {
    uint64_t unk;
    uint64_t x[29];
    uint64_t fp;
    uint64_t lr;
    uint64_t sp;
    uint64_t pc;
    uint32_t cpsr;
    // Other stuff
    uint64_t other[70];
} kRegisterState;

struct kernel_primitives {
	int (*kreadbuf)(uint64_t kaddr, void* output, size_t size);
	int (*kwritebuf)(uint64_t kaddr, const void* input, size_t size);
	int (*physreadbuf)(uint64_t physaddr, void* output, size_t size);
	int (*physwritebuf)(uint64_t physaddr, const void* input, size_t size);
	uint64_t (*kcall)(uint64_t func, int argc, const uint64_t *argv);
	void (*kexec)(kRegisterState *state);
	int (*kalloc_global)(uint64_t *addr, uint64_t size);
	int (*kalloc_local)(uint64_t *addr, uint64_t size);
	int (*kfree_global)(uint64_t addr, uint64_t size);
	int (*kmap)(uint64_t pa, uint64_t size, void **uaddr);
	uint64_t (*vtophys)(uint64_t ttep, uint64_t va);
	uint64_t (*phystokv)(uint64_t pa);
};

extern struct kernel_primitives gPrimitives;

#endif
