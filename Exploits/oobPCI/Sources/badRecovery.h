//
//  badRecovery.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef badRecovery_h
#define badRecovery_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

typedef struct {
    uint64_t unk;
    uint64_t x[29];
    uint64_t fp;
    uint64_t lr;
    uint64_t sp;
    uint64_t pc;
    uint32_t cpsr;
    // Other stuff
    uint64_t other[70];
} kRegisterState;

typedef struct {
    bool inited;
    thread_t gExploitThread;
    uint64_t gScratchMemKern;
    volatile uint64_t *gScratchMemMapped;
    arm_thread_state64_t gExploitThreadState;
    uint64_t gSpecialMemRegion;
    uint64_t gIntStack;
    uint64_t gOrigIntStack;
    uint64_t gReturnContext;
    uint64_t gACTPtr;
    uint64_t gACTVal;
    uint64_t gCPUData;
} exploitThreadInfo;

typedef struct {
    bool inited;
    thread_t thread;
    uint64_t actContext;
    kRegisterState signedState;
    uint64_t kernelStack;
    kRegisterState *mappedState;
    uint64_t scratchMemory;
    uint64_t *scratchMemoryMapped;
} Fugu14KcallThread;

bool breakCFI(uint64_t kernelBase);
void deinitFugu15PACBypass(void);

bool setupFugu14Kcall(void);

void pac_exploit_thread(void);
void pac_exploit_doIt(void);
void pac_loop(void);

void ppl_loop(void);
void ppl_done(void);

void kexec(kRegisterState *state, exploitThreadInfo *info);
uint64_t kcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);

bool kexec_on_new_thread(kRegisterState *kState, thread_t *thread);

#endif /* badRecovery_h */
