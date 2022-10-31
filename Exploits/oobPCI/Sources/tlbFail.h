//
//  tlbFail.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef tlbFail_h
#define tlbFail_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

bool pplBypass(void);

void* getPhysMapWindow(uint64_t phys);

bool physwrite_PPL(uint64_t addr, void *buffer, size_t len);
bool kernwrite_PPL(uint64_t addr, void *buffer, size_t len);

uint64_t pmap_lv2(uint64_t pmap, uint64_t virt);

#endif /* tlbFail_h */
