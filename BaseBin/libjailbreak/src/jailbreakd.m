#import "jailbreakd.h"

#import <mach/mach.h>
#import <unistd.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#include <sys/param.h>
#include <sys/mount.h>
#import "log.h"
#import "pplrw.h"

bool gIsJailbreakd = false;

kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

mach_port_t jbdMachPort(void)
{
	mach_port_t outPort = -1;

	if (getpid() == 1) {
		mach_port_t self_host = mach_host_self();
		host_get_special_port(self_host, HOST_LOCAL_NODE, 16, &outPort);
		mach_port_deallocate(mach_task_self(), self_host);
	}
	else {
		bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd", &outPort);
	}

	return outPort;
}

xpc_object_t sendJBDMessage(xpc_object_t xdict)
{
	xpc_object_t xreply = nil;
	mach_port_t jbdPort = jbdMachPort();
	if (jbdPort != -1) {
		xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);
		if (pipe) {
			int err = xpc_pipe_routine(pipe, xdict, &xreply);
			if (err != 0) {
				JBLogError("xpc_pipe_routine error on sending message to jailbreakd: %d / %s", err, xpc_strerror(err));
				xreply = nil;
			};
		}
		mach_port_deallocate(mach_task_self(), jbdPort);
	}
	return xreply;
}

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_GET_STATUS);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return;

	audit_token_t auditToken = {};
	xpc_dictionary_get_audit_token(reply, &auditToken);
    pid_t serverPid = audit_token_to_pid(auditToken);

	if (PPLRWStatus) *PPLRWStatus = xpc_dictionary_get_uint64(reply, "pplrwStatus");
	if (kcallStatus) *kcallStatus = xpc_dictionary_get_uint64(reply, "kcallStatus");
	if (pid) *pid = serverPid;
}

void jbdTransferPPLRW(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PPL_INIT);
	sendJBDMessage(message);
}

uint64_t jbdTransferKcall(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PAC_INIT);
	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_uint64(reply, "arcContext");
}

void jbdFinalizeKcall(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PAC_FINALIZE);
	sendJBDMessage(message);
}

int64_t jbdGetPPLRW(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_HANDOFF_PPL);
	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;

	int64_t errorCode = xpc_dictionary_get_int64(reply, "errorCode");

	return errorCode;
}

int jbdInitPPLRW(void)
{
	int64_t errorCode = jbdGetPPLRW();
	if (errorCode) return errorCode;
	initPPLPrimitives();
	return 0;
}

uint64_t jbdKcallThreadState(KcallThreadState *threadState, bool raw)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DO_KCALL_THREADSTATE);

	xpc_dictionary_set_uint64(message, "lr", threadState->lr);
	xpc_dictionary_set_uint64(message, "sp", threadState->sp);
	xpc_dictionary_set_uint64(message, "pc", threadState->pc);

	xpc_object_t registers = xpc_array_create_empty();
	for (uint64_t i = 0; i < 29; i++) {
		xpc_array_set_uint64(registers, XPC_ARRAY_APPEND, threadState->x[i]);
	}
	xpc_dictionary_set_value(message, "x", registers);
	xpc_dictionary_set_bool(message, "raw", raw);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_uint64(reply, "ret");
}

uint64_t jbdKcall(uint64_t func, uint64_t argc, const uint64_t *argv)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DO_KCALL);
	xpc_dictionary_set_uint64(message, "func", func);

	xpc_object_t args = xpc_array_create_empty();
	for (uint64_t i = 0; i < argc; i++) {
		xpc_array_set_uint64(args, XPC_ARRAY_APPEND, argv[i]);
	}
	xpc_dictionary_set_value(message, "args", args);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_uint64(reply, "ret");
}

uint64_t jbdKcall8(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	return jbdKcall(func, 8, (uint64_t[]){a1, a2, a3, a4, a5, a6, a7, a8});
}

int64_t jbdInitEnvironment(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_INIT_ENVIRONMENT);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}

int64_t jbdUpdateFromTIPA(NSString *pathToTIPA, bool rebootWhenDone)
{
	NSString *standardizedPath = [[pathToTIPA stringByResolvingSymlinksInPath] stringByStandardizingPath];

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_JBUPDATE);
	xpc_dictionary_set_string(message, "tipaPath", standardizedPath.fileSystemRepresentation);
	xpc_dictionary_set_bool(message, "rebootWhenDone", rebootWhenDone);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}

int64_t jbdUpdateFromBasebinTar(NSString *pathToBasebinTar, bool rebootWhenDone)
{
	NSString *standardizedPath = [[pathToBasebinTar stringByResolvingSymlinksInPath] stringByStandardizingPath];

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_JBUPDATE);
	xpc_dictionary_set_string(message, "basebinPath", standardizedPath.fileSystemRepresentation);
	xpc_dictionary_set_bool(message, "rebootWhenDone", rebootWhenDone);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}


int64_t jbdRebuildTrustCache(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_REBUILD_TRUSTCACHE);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}

int64_t jbdProcessBinary(const char *filePath)
{
	// if file doesn't exist, bail out
	if (access(filePath, F_OK) != 0) return 0;

	// if file is on rootfs mount point, it doesn't need to be
	// processed as it's guaranteed to be in static trust cache
	// same goes for our /usr/lib bind mount
	struct statfs fs;
	int sfsret = statfs(filePath, &fs);
	if (sfsret == 0) {
		if (!strcmp(fs.f_mntonname, "/") || !strcmp(fs.f_mntonname, "/usr/lib")) return -1;
	}

	char absolutePath[PATH_MAX];
	if (realpath(filePath, absolutePath) == NULL) return -1;

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROCESS_BINARY);
	xpc_dictionary_set_string(message, "filePath", absolutePath);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");;
}

int64_t jbdProcSetDebugged(pid_t pid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROC_SET_DEBUGGED);
	xpc_dictionary_set_int64(message, "pid", pid);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}


int64_t jbdSetFakelibVisible(bool visible)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_SET_FAKELIB_VISIBLE);
	xpc_dictionary_set_bool(message, "visible", visible);

	xpc_object_t reply = sendJBDMessage(message);
	if (!reply) return -10;
	return xpc_dictionary_get_int64(reply, "result");
}
