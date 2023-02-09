//
//  kernel.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef kernel_h
#define kernel_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

kern_return_t pmap_enter_options_addr(uint64_t pmap, uint64_t pa, uint64_t va);
void pmap_remove(uint64_t pmap, uint64_t start, uint64_t end);

void pmap_set_nested(uint64_t pmap);
kern_return_t pmap_nest(uint64_t grand, uint64_t subord, uint64_t vstart, uint64_t size);

void pmap_mark_page_as_ppl_page(uint64_t page);
uint64_t pmap_alloc_page_for_kern(void);

#endif /* kernel_h */

