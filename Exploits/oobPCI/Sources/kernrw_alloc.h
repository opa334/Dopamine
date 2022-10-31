//
//  kernrw_alloc.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef kernrw_alloc_h
#define kernrw_alloc_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

bool kernread (uint64_t addr, size_t len, void *buffer);
bool kernwrite(uint64_t addr, void *buffer, size_t len);

uint64_t kmemAlloc(uint64_t size, void **mappedAddr, bool leak);

#endif /* kernrw_alloc_h */
