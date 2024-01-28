#ifndef HANDOFF_H
#define HANDOFF_H

#include <stdint.h>
#include <stdlib.h>

#define PERM_KRW_URW 0x7 // R/W for kernel and user

uint64_t _alloc_page_table(void);
uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va);
int handoff_ppl_primitives(pid_t pid);

#endif
