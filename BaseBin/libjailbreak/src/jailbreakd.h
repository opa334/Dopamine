#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

typedef enum {
	JBD_MSG_GET_STATUS = 0,
	JBD_MSG_PPL_INIT = 1,
	JBD_MSG_PAC_INIT = 2,
	JBD_MSG_PAC_FINALIZE = 3,

	JBD_MSG_HANDOFF_PPL = 10,
	JBD_MSG_DO_KCALL = 11,

	JBD_MSG_REMOTELOG = 15,

	JBD_MSG_REBUILD_TRUSTCACHE = 20,
	JBD_MSG_ENTITLE_VNODE = 21,
	JBD_MSG_ENTITLE_PROC = 22,
	JBD_MSG_PROC_SET_DEBUGGED = 23,
} JBD_MESSAGE_ID;

typedef enum {
	JBD_ERR_PRIMITIVE_NOT_INITIALIZED = 0,
} JBD_ERR_ID;

extern bool gIsJailbreakd;

uint64_t jbdParseNumUInt64(NSNumber *num);
uint64_t jbdParseNumInt64(NSNumber *num);
bool jbdParseBool(NSNumber *num);

mach_port_t jbdMachPort(void);
xpc_object_t sendJBDMessage(xpc_object_t message);

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid);
void jbdTransferPPLRW(uint64_t magicPage);
uint64_t jbdTransferKcall();
void jbdFinalizeKcall(void);

uint64_t jbdGetPPLRWPage(int64_t* errOut);
int jbdInitPPLRW(void);
uint64_t jbdKcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);

void jbdRemoteLog(uint64_t verbosity, NSString *fString, ...);

void jbdRebuildTrustCache(void);
bool jbdEntitleVnode(pid_t pid, int fd);
bool jbdEntitleProc(pid_t pid);
bool jbdProcSetDebugged(pid_t pid);