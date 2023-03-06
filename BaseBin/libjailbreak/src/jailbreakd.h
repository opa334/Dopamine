#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

typedef enum {
	JBD_MSG_GET_STATUS = 0,
	JBD_MSG_PPL_INIT = 1,
	JBD_MSG_PAC_INIT = 2,
	JBD_MSG_PAC_FINALIZE = 3,

	JBD_MSG_HANDOFF_PPL = 10,
	JBD_MSG_KCALL = 11,

	JBD_MSG_REBUILD_TRUSTCACHE = 20,
	JBD_MSG_UNRESTRICT_VNODE = 21,
	JBD_MSG_UNRESTRICT_PROC = 22,
} JBD_MESSAGE_ID;

uint64_t jbdParseNumUInt64(NSNumber *num);
uint64_t jbdParseNumInt64(NSNumber *num);
bool jbdParseBool(NSNumber *num);

mach_port_t jbdMachPort(void);
xpc_object_t sendJBDMessage(xpc_object_t message);

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid);
void jbdTransferPPLRW(uint64_t magicPage);
uint64_t jbdTransferKcall(uint64_t kernelAllocation);
void jbdFinalizeKcall(void);
int jbdInitPPLRW(void);
uint64_t jbdKcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);
bool jbdUnrestrictProc(pid_t pid);
void jbdRebuildTrustCache(void);
int jbdInitKcall(void);