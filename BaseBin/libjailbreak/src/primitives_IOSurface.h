#ifndef PRIMITIVES_IOSURFACE_H
#define PRIMITIVES_IOSURFACE_H

void *IOSurface_map(uint64_t phys, uint64_t size);
uint64_t IOSurface_kalloc(uint64_t size, bool leak);
int IOSurface_kalloc_global(uint64_t *addr, uint64_t size);
int IOSurface_kalloc_local(uint64_t *addr, uint64_t size);
void libjailbreak_IOSurface_primitives_init(void);

#endif
