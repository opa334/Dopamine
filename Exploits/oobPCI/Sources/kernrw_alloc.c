//
//  kernrw_alloc.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "kernrw_alloc.h"

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <mach/mach.h>

#include "includeme.h"
#include "offsets.h"
#include "physrw.h"
#include "virtrw.h"

bool kernread(uint64_t addr, size_t len, void *buf) {
    uint8_t *buffer = (uint8_t*) buf;
    
    while (len) {
        uint64_t page   = addr & ~0x3FFFULL;
        uint64_t off    = addr & 0x3FFFULL;
        uint64_t curLen = 0x4000ULL - off;
        if (len < curLen) {
            curLen = len;
        }
        
        uint64_t phys = translateAddr(page);
        guard (phys != 0) else {
            return false;
        }
        
        guard (physread(phys + off, curLen, (void*) buffer)) else {
            return false;
        }
        
        addr   += curLen;
        buffer += curLen;
        len    -= curLen;
    }
    
    return true;
}

bool kernwrite(uint64_t addr, void *buf, size_t len) {
    uint8_t *buffer = (uint8_t*) buf;
    
    while (len) {
        uint64_t page   = addr & ~0x3FFFULL;
        uint64_t off    = addr & 0x3FFFULL;
        uint64_t curLen = 0x4000ULL - off;
        if (len < curLen) {
            curLen = len;
        }
        
        uint64_t phys = translateAddr(page);
        guard (phys != 0) else {
            return false;
        }
        
        guard (physwrite(phys + off, (void*) buffer, curLen)) else {
            return false;
        }
        
        addr   += curLen;
        buffer += curLen;
        len    -= curLen;
    }
    
    return true;
}

uint64_t kmemAlloc(uint64_t size, void **mappedAddr, bool leak) {
    mach_port_t buffer = IOBufferMemoryDescriptor_create(3, size, 0);
    guard (buffer != 0) else {
        puts("[-] kmemAlloc: Failed to create IOBufferMemoryDescriptor!");
        return 0;
    }
    
    if (mappedAddr) {
        *mappedAddr = (void*) IOMemoryDescriptor_map(buffer, 0, 0);
    }
    
    uint64_t kObject = portKObject(buffer);
    guard (kObject != 0) else {
        puts("[-] kmemAlloc: Failed to get IOBufferMemoryDescriptor kObject!");
        return 0;
    }
    
    // Get ranges
    uint64_t memRanges = kread_ptr(kObject + 0x60);
    guard (memRanges != 0) else {
        puts("[-] kmemAlloc: Failed to get IOBufferMemoryDescriptor _ranges!");
        return 0;
    }
    
    // Leak object if requested
    // XXX: Always leak...
    //if (leak) {
        // Increase refcount
        uint32_t refcount = kread32(kObject + 0x8ULL);
        kwrite32(kObject + 0x8ULL, refcount + 0x1337);
    //}
    
    return kread_ptr(memRanges);
}
