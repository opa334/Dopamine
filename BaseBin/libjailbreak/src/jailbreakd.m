#import "jailbreakd.h"

#import <mach/mach.h>
#import <unistd.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import "pplrw.h"

bool gIsJailbreakd = false;

kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

mach_port_t jbdMachPort(void)
{
	mach_port_t outPort = -1;

	if (getpid() == 1) {
		host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 16, &outPort);
	}
	else {
		bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd", &outPort);
	}

	return outPort;
}

xpc_object_t sendJBDMessage(xpc_object_t message)
{
	mach_port_t jbdPort = jbdMachPort();
	xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);

	xpc_object_t reply = nil;
	int err = xpc_pipe_routine(pipe, message, &reply);
	if (err != 0) {
		NSLog(@"xpc_pipe_routine error on sending message to jailbreakd: %d", err);
		return nil;
	}

	return reply;
}

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_GET_STATUS);

	xpc_object_t response = sendJBDMessage(message);
	if (!response) return;

	audit_token_t auditToken = {};
	xpc_dictionary_get_audit_token(response, &auditToken);
    pid_t serverPid = audit_token_to_pid(auditToken);

	if (PPLRWStatus) *PPLRWStatus = xpc_dictionary_get_uint64(response, "pplrwStatus");
	if (kcallStatus) *kcallStatus = xpc_dictionary_get_uint64(response, "kcallStatus");
	if (pid) *pid = serverPid;
}

void jbdTransferPPLRW(uint64_t magicPage)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PPL_INIT);
	xpc_dictionary_set_uint64(message, "magicPage", magicPage);
	sendJBDMessage(message);
}

uint64_t jbdTransferKcall(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PAC_INIT);
	xpc_object_t reply = sendJBDMessage(message);
	return xpc_dictionary_get_uint64(reply, "arcContext");
}

void jbdFinalizeKcall(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PAC_FINALIZE);
	sendJBDMessage(message);
}

uint64_t jbdGetPPLRWPage(int64_t* errOut)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_HANDOFF_PPL);
	xpc_object_t reply = sendJBDMessage(message);

	int64_t errorCode = xpc_dictionary_get_int64(reply, "errorCode");
	uint64_t magicPage = xpc_dictionary_get_uint64(reply, "magicPage");

	if (errOut) *errOut = errorCode;
	return magicPage;
}

int jbdInitPPLRW(void)
{
	int64_t errorCode = 0;
	uint64_t magicPage = jbdGetPPLRWPage(&errorCode);
	if (errorCode) return errorCode;
	initPPLPrimitives(magicPage);
	return 0;
}

uint64_t jbdKcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DO_KCALL);
	xpc_dictionary_set_uint64(message, "func", func);
	xpc_dictionary_set_uint64(message, "a1", a1);
	xpc_dictionary_set_uint64(message, "a2", a2);
	xpc_dictionary_set_uint64(message, "a3", a3);
	xpc_dictionary_set_uint64(message, "a4", a4);
	xpc_dictionary_set_uint64(message, "a5", a5);
	xpc_dictionary_set_uint64(message, "a6", a6);
	xpc_dictionary_set_uint64(message, "a7", a7);
	xpc_dictionary_set_uint64(message, "a8", a8);

	xpc_object_t reply = sendJBDMessage(message);
	return xpc_dictionary_get_uint64(reply, "ret");
}

void jbdRemoteLog(uint64_t verbosity, NSString *fString, ...)
{
	va_list va;
	va_start(va, fString);
	NSString* msg = [[NSString alloc] initWithFormat:fString arguments:va];
	va_end(va);

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_REMOTELOG);
	xpc_dictionary_set_uint64(message, "verbosity", verbosity);
	xpc_dictionary_set_string(message, "log", [msg UTF8String]);

	sendJBDMessage(message);
}


bool jbdEntitleVnode(pid_t pid, int fd)
{
	return NO;
}

void jbdRebuildTrustCache(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_REBUILD_TRUSTCACHE);
	sendJBDMessage(message);
}

bool jbdEntitleProc(pid_t pid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_ENTITLE_PROC);
	xpc_dictionary_set_int64(message, "pid", pid);

	xpc_object_t reply = sendJBDMessage(message);
	return xpc_dictionary_get_bool(reply, "success");
}

bool jbdProcSetDebugged(pid_t pid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROC_SET_DEBUGGED);
	xpc_dictionary_set_int64(message, "pid", pid);

	xpc_object_t reply = sendJBDMessage(message);
	return xpc_dictionary_get_bool(reply, "success");
}