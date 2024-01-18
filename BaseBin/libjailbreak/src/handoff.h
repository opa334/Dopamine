#ifndef HANDOFF_H
#define HANDOFF_H

#include <stdint.h>
#include <stdlib.h>

#define PERM_KRW_URW 0x7 // R/W for kernel and user
#define L1_BLOCK_SIZE 0x1000000000
#define L1_BLOCK_MASK (L1_BLOCK_SIZE-1)
#define L2_BLOCK_SIZE 0x2000000
#define L2_BLOCK_PAGECOUNT (L2_BLOCK_SIZE / PAGE_SIZE)
#define L2_BLOCK_MASK (L2_BLOCK_SIZE-1)

uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va);
int handoff_ppl_primitives(pid_t pid);

#endif
