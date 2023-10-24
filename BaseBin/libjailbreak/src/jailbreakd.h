#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

typedef enum {
	JBD_MSG_GET_STATUS = 0,
	JBD_MSG_PPL_INIT = 1,
	JBD_MSG_PAC_INIT = 2,
	JBD_MSG_PAC_FINALIZE = 3,

	JBD_MSG_HANDOFF_PPL = 10,
	JBD_MSG_DO_KCALL = 11,
	JBD_MSG_DO_KCALL_THREADSTATE = 12,
	JBD_MSG_INIT_ENVIRONMENT = 13,
	JBD_MSG_JBUPDATE = 14,

	JBD_MSG_REBUILD_TRUSTCACHE = 20,
	JBD_MSG_SETUID_FIX = 21,
	JBD_MSG_PROCESS_BINARY = 22,
	JBD_MSG_PROC_SET_DEBUGGED = 23,
	JBD_MSG_DEBUG_ME = 24,
	JBD_MSG_FORK_FIX = 25,
	JBD_MSG_INTERCEPT_USERSPACE_PANIC = 26,

	JBD_SET_FAKELIB_VISIBLE = 30,
} JBD_MESSAGE_ID;

typedef enum {
	JBD_ERR_PRIMITIVE_NOT_INITIALIZED = 0,
	JBD_ERR_NOT_PERMITTED = 1,
} JBD_ERR_ID;

typedef struct {
	uint64_t x[29];
	uint64_t lr;
	uint64_t sp;
	uint64_t pc;
} KcallThreadState;

extern bool gIsJailbreakd;

uint64_t jbdParseNumUInt64(NSNumber *num);
uint64_t jbdParseNumInt64(NSNumber *num);
bool jbdParseBool(NSNumber *num);

mach_port_t jbdMachPort(void);
xpc_object_t sendJBDMessage(xpc_object_t message);

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid);
void jbdTransferPPLRW(void);
uint64_t jbdTransferKcall();
void jbdFinalizeKcall(void);

uint64_t jbdGetPPLRWPage(int64_t* errOut);
int jbdInitPPLRW(void);
uint64_t jbdKcallThreadState(KcallThreadState *threadState, bool raw);
uint64_t jbdKcall(uint64_t func, uint64_t argc, const uint64_t *argv);
uint64_t jbdKcall8(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);
int64_t jbdInitEnvironment(void);

int64_t jbdUpdateFromTIPA(NSString *pathToTIPA, bool rebootWhenDone);
int64_t jbdUpdateFromBasebinTar(NSString *pathToBasebinTar, bool rebootWhenDone);

int64_t jbdRebuildTrustCache(void);
int64_t jbdProcessBinary(const char *filePath);
int64_t jbdProcSetDebugged(pid_t pid);