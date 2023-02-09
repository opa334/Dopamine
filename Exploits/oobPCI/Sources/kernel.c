//
//  kernel.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "kernel.h"

#include "includeme.h"
#include "offsets.h"
#include "badRecovery.h"

kern_return_t pmap_enter_options_addr(uint64_t pmap, uint64_t pa, uint64_t va) {
    uint64_t pmap_enter_options_addr_ptr = SLIDE(gOffsets.pmap_enter_options_addr);
    
    while (1) {
        kern_return_t kr = (kern_return_t) kcall(pmap_enter_options_addr_ptr, pmap, va, pa, VM_PROT_READ | VM_PROT_WRITE, 0, 0, 1, 1);
        if (kr != KERN_RESOURCE_SHORTAGE) {
            return kr;
        }
    }
}

void pmap_remove(uint64_t pmap, uint64_t start, uint64_t end) {
    uint64_t pmap_remove_options_ptr = SLIDE(gOffsets.pmap_remove_options);
    
    kcall(pmap_remove_options_ptr, pmap, start, end, 0x100, 0, 0, 0, 0);
}

void pmap_set_nested(uint64_t pmap) {
    uint64_t pmap_set_nested_ptr = SLIDE(gOffsets.pmap_set_nested);
    
    kcall(pmap_set_nested_ptr, pmap, 0, 0, 0, 0, 0, 0, 0);
}

kern_return_t pmap_nest(uint64_t grand, uint64_t subord, uint64_t vstart, uint64_t size) {
    uint64_t pmap_nest_ptr = SLIDE(gOffsets.pmap_nest);
    
    return (kern_return_t) kcall(pmap_nest_ptr, grand, subord, vstart, size, 0, 0, 0, 0);
}

void pmap_mark_page_as_ppl_page(uint64_t page) {
    uint64_t pmap_mark_page_as_ppl_page_ptr = SLIDE(gOffsets.pmap_mark_page_as_ppl_page);
    
    kcall(pmap_mark_page_as_ppl_page_ptr, page, 1, 0, 0, 0, 0, 0, 0);
}

uint64_t pmap_alloc_page_for_kern(void)
{
    uint64_t pmap_mark_page_as_ppl_page_ptr = SLIDE(gOffsets.pmap_alloc_page_for_kern);
    return kcall(pmap_mark_page_as_ppl_page_ptr, 0, 0, 0, 0, 0, 0, 0, 0);
}
