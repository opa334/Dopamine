//
//  offsets.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "offsets.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include "includeme.h"
#include "offsets.h"
#include "virtrw.h"

KernelOffsetInfo gOffsets;

uint64_t gOurProc    = 0;
uint64_t gKernelProc = 0;
uint64_t gOurTask    = 0;
uint64_t gKernelTask = 0;
uint64_t gIS_TABLE   = 0;
uint64_t gOurPmap    = 0;
uint64_t gKernelPmap = 0;

bool resolveKernelOffsets(uint64_t kernelBase) {
    bool (*getOffsets)(uint64_t kernelBase, KernelOffsetInfo *info) = (bool(*)(uint64_t, KernelOffsetInfo*)) DBG_GETOFFSETS_FUNC;
    bool ok = getOffsets(kernelBase, &gOffsets);
    if (!ok) {
        puts("[-] resolveKernelOffsets: getOffsets failed!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(gOffsets.slide);
    
    // Find our proc
    uint64_t curProc    = kread64(SLIDE(gOffsets.allproc));
    uint64_t ourProc    = 0;
    uint64_t kernelProc = 0;
    uint32_t myPid      = getpid();
    while (curProc) {
        if (PROC_PID(curProc) == myPid) {
            ourProc = curProc;
        } else if (PROC_PID(curProc) == 0) {
            kernelProc = curProc;
        }
        
        if (ourProc != 0 && kernelProc != 0) {
            break;
        }
        
        curProc = PROC_NEXT(curProc);
    }
    
    guard (ourProc != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find our proc!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourProc);
    
    guard (kernelProc != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find kernel proc!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(kernelProc);
    
    // Get task
    uint64_t ourTask = PROC_TASK(ourProc);
    guard (ourTask != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find our task!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourTask);
    
    // Get kernel task
    uint64_t kernelTask = PROC_TASK(kernelProc);
    guard (kernelTask != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find kernel task!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(kernelTask);
    
    // Get itk_space
    uint64_t itk_space = TASK_ITK_SPACE(ourTask);
    guard (itk_space != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find itk_space!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(itk_space);
    
    // Get is_table
    uint64_t is_table = SPACE_IS_TABLE(itk_space);
    guard (is_table != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find is_table!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(is_table);
    
    // Get vm map
    uint64_t vmMap = TASK_VM_MAP(ourTask);
    guard (vmMap != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find vmMap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(vmMap);
    
    // Get pmap
    uint64_t ourPmap = VM_MAP_PMAP(vmMap);
    guard (ourPmap != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find our pmap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(ourPmap);
    
    // Get kernel vm map
    uint64_t kernelVmMap = TASK_VM_MAP(kernelTask);
    guard (kernelVmMap != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find kernel vmMap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(kernelVmMap);
    
    // Get kernel pmap
    uint64_t kernelPmap = VM_MAP_PMAP(kernelVmMap);
    guard (kernelPmap != 0) else {
        puts("[-] resolveKernelOffsets: Failed to find kernel pmap!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(kernelPmap);
    
    gOurProc    = ourProc;
    gKernelProc = kernelProc;
    gOurTask    = ourTask;
    gKernelTask = kernelTask;
    gIS_TABLE   = is_table;
    gOurPmap    = ourPmap;
    gKernelPmap = kernelPmap;
    
    return true;
}

void reloadIsTable(void) {
    uint64_t itk_space = TASK_ITK_SPACE(gOurTask);
    guard (itk_space != 0) else {
        puts("[-] reloadIsTable: Failed to find itk_space!");
        return;
    }
    
    uint64_t is_table = SPACE_IS_TABLE(itk_space);
    guard (is_table != 0) else {
        puts("[-] reloadIsTable: Failed to find is_table!");
        return;
    }
    
    gIS_TABLE = is_table;
}

uint64_t portGetKPort(mach_port_t port) {
    reloadIsTable();
    
    uint64_t kPort = IS_TABLE_PORT(gIS_TABLE, port);
    guard (kPort != 0) else {
        printf("[-] portGetKPort: IS_TABLE_PORT(%p, %p): NULL!\n", (void*) gIS_TABLE, (void*) (uint64_t) port);
        return 0;
    }
    
    return kPort;
}

uint64_t portKObject(mach_port_t port) {
    reloadIsTable();
    
    uint64_t kPort = IS_TABLE_PORT(gIS_TABLE, port);
    guard (kPort != 0) else {
        printf("[-] portKObject: IS_TABLE_PORT(%p, %p): NULL!\n", (void*) gIS_TABLE, (void*) (uint64_t) port);
        return 0;
    }
    
    // Don't need to check for labels anymore - Apple changed that stuff
    return PORT_KOBJECT(kPort);
}

uint64_t task_is_table(uint64_t task, uint64_t itkSpaceOffset) {
    // Get itk_space
    uint64_t itk_space = kread_ptr(task + itkSpaceOffset);
    guard (itk_space != 0) else {
        puts("[-] task_is_table: Failed to find itk_space!");
        return 0;
    }
    
    DBGPRINT_ADDRVAR(itk_space);
    
    // Get is_table
    uint64_t is_table = SPACE_IS_TABLE(itk_space);
    guard (is_table != 0) else {
        puts("[-] task_is_table: Failed to find is_table!");
        return 0;
    }
    
    return is_table;
}
