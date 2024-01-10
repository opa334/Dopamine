struct kernel_primitives {
	int (*kreadbuf)(uint64_t kaddr, void* output, size_t size);
	int (*kwritebuf)(uint64_t kaddr, const void* input, size_t size);
	int (*physreadbuf)(uint64_t physaddr, void* output, size_t size);
	int (*physwritebuf)(uint64_t physaddr, const void* input, size_t size);
	int (*kalloc_global)(uint64_t *addr, uint64_t size);
	int (*kalloc_user)(uint64_t *addr, uint64_t size);
	int (*kfree_global)(uint64_t addr, uint64_t size);
	int (*kmap)(uint64_t page, uint64_t *uaddr);
	int (*vtophys)(uint64_t ttep, uint64_t addr);
	int (*phystokv)(uint64_t pa);
};