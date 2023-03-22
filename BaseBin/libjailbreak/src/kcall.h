#import <Foundation/Foundation.h>
#import "jailbreakd.h"

typedef enum {
	kKcallStatusNotInitialized = 0,
	kKcallStatusPrepared = 1,
	kKcallStatusFinalized = 2
} KcallStatus;

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

extern KcallStatus gKCallStatus;

void pac_loop(void);

uint64_t kcall(uint64_t func, uint64_t argc, uint64_t *argv);
uint64_t kcall8(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);
uint64_t kcall_with_raw_thread_state(KcallThreadState threadState);
uint64_t kcall_with_thread_state(KcallThreadState threadState);
uint64_t initPACPrimitives(uint64_t kernelAllocation);
void finalizePACPrimitives(void);
int signState(uint64_t actContext);
int recoverPACPrimitives();
void destroyPACPrimitives(void);