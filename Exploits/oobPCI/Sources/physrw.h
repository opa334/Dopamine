//
//  physrw.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef physrw_h
#define physrw_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

bool buildPhysPrimitive(uint64_t kernelBase);

// R/W
bool physread(uint64_t addr, size_t len, void *buffer);
bool physwrite(uint64_t addr, void *buffer, size_t len);

uint64_t rp64(uint64_t addr);
uint32_t rp32(uint64_t addr);
uint16_t rp16(uint64_t addr);
uint8_t  rp8(uint64_t addr);

// Address translation
uint64_t translateAddr_inTTEP(uint64_t ttep, uint64_t virt);
uint64_t translateAddr(uint64_t virt);

// Internal function
// Can be used once to map arbitrary physical memory
uint64_t physrw_map_once(uint64_t addr);

#endif /* physrw_h */
