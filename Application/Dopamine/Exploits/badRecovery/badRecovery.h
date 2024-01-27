//
//  badRecovery.h
//  Dopamine
//
//  Created by Lars Fröder on 25.01.24.
//

#ifndef badRecovery_h
#define badRecovery_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>
#include <libjailbreak/kcall_Fugu14.h>

typedef struct {
    bool inited;
    thread_t gExploitThread;
    uint64_t gScratchMemKern;
    volatile uint64_t *gScratchMemMapped;
    volatile uint64_t *gReturnValMemMapped;
    arm_thread_state64_t gExploitThreadState;
    uint64_t gSpecialMemRegion;
    uint64_t gIntStack;
    uint64_t gOrigIntStack;
    uint64_t gReturnContext;
    uint64_t gACTPtr;
    uint64_t gACTVal;
    uint64_t gCPUData;
} exploitThreadInfo;

bool breakCFI(void);
void deinitFugu15PACBypass(void);

void fugu15_kexec_on_thread(exploitThreadInfo *info, kRegisterState *state);

bool kexec_on_new_thread(kRegisterState *kState, thread_t *thread);

uint64_t fugu15_kcall(uint64_t func, int argc, const uint64_t *argv);
void fugu15_kexec(kRegisterState state);

#endif /* badRecovery_h */
