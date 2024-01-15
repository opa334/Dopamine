#include "jbclient_xpc.h"
#include "jbserver.h"
#include <dispatch/dispatch.h>

#define OS_ALLOC_ONCE_KEY_MAX    100

struct _os_alloc_once_s {
	long once;
	void *ptr;
};

struct xpc_global_data {
	uint64_t    a;
	uint64_t    xpc_flags;
	mach_port_t    task_bootstrap_port;  /* 0x10 */
#ifndef _64
	uint32_t    padding;
#endif
	xpc_object_t    xpc_bootstrap_pipe;   /* 0x18 */
};

extern struct _os_alloc_once_s _os_alloc_once_table[];
extern void* _os_alloc_once(struct _os_alloc_once_s *slot, size_t sz, os_function_t init);

xpc_object_t jbserver_xpc_send(uint64_t domain, uint64_t action, xpc_object_t xargs)
{
	bool ownsXargs = false;
	if (!xargs) {
		xargs = xpc_dictionary_create_empty();
		ownsXargs = true;
	}

	struct xpc_global_data* globalData = NULL;
	if (_os_alloc_once_table[1].once == -1) {
		globalData = _os_alloc_once_table[1].ptr;
	}
	else {
		globalData = _os_alloc_once(&_os_alloc_once_table[1], 472, NULL);
		if (!globalData) _os_alloc_once_table[1].once = -1;
	}
	if (!globalData) return NULL;
	if (!globalData->xpc_bootstrap_pipe) {
		mach_port_t *initPorts;
		mach_msg_type_number_t initPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &initPorts, &initPortsCount) == 0) {
			globalData->task_bootstrap_port = initPorts[0];
			globalData->xpc_bootstrap_pipe = xpc_pipe_create_from_port(globalData->task_bootstrap_port, 0);
		}
	}
	xpc_object_t serverPipe = globalData->xpc_bootstrap_pipe;
	if (!serverPipe) return NULL;

	xpc_dictionary_set_uint64(xargs, "jb-domain", domain);
	xpc_dictionary_set_uint64(xargs, "action", action);

	xpc_object_t xreply;
	int err = xpc_pipe_routine_with_flags(serverPipe, xargs, &xreply, 0);
	if (ownsXargs) {
		xpc_release(xargs);
	}

	if (err != 0) {
		return NULL;
	}

	return xreply;
}

char *jbclient_get_root_path(void)
{
	static char jbRootPath[PATH_MAX] = { 0 };
	static dispatch_once_t dot;

	dispatch_once(&dot, ^{
		xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_SYSTEMWIDE, JBS_SYSTEMWIDE_GET_JB_ROOT, NULL);
		if (xreply) {
			const char *replyJBRootPath = xpc_dictionary_get_string(xreply, "root-path");
			if (replyJBRootPath) {
				strlcpy(&jbRootPath[0], replyJBRootPath, sizeof(jbRootPath));
			}
			xpc_release(xreply);
		}
	});

	if (jbRootPath[0] == '\0') return NULL;
	return (char *)&jbRootPath[0];
}

char *jbclient_get_boot_uuid(void)
{
	static char jbBootUUID[37] = { 0 };
	static dispatch_once_t dot;

	dispatch_once(&dot, ^{
		xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_SYSTEMWIDE, JBS_SYSTEMWIDE_GET_BOOT_UUID, NULL);
		if (xreply) {
			const char *replyJBBootUUID = xpc_dictionary_get_string(xreply, "boot-uuid");
			if (replyJBBootUUID) {
				strlcpy(&jbBootUUID[0], replyJBBootUUID, sizeof(jbBootUUID));
			}
			xpc_release(xreply);
		}
	});

	if (jbBootUUID[0] == '\0') return NULL;
	return (char *)&jbBootUUID[0];
}

int jbclient_trust_binary(const char *binaryPath)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_string(xargs, "binary-path", binaryPath);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_SYSTEMWIDE, JBS_SYSTEMWIDE_TRUST_BINARY, xargs);
	xpc_release(xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_process_checkin(void)
{
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_SYSTEMWIDE, JBS_SYSTEMWIDE_PROCESS_CHECKIN, NULL);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_fork_fix(uint64_t childPid)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(xargs, "child-pid", childPid);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_SYSTEMWIDE, JBS_SYSTEMWIDE_FORK_FIX, xargs);
	xpc_release(xargs);
	if (xreply) {
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_platform_set_process_debugged(uint64_t pid)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(xargs, "pid", pid);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_PLATFORM, JBS_PLATFORM_SET_PROCESS_DEBUGGED, xargs);
	xpc_release(xargs);
	if (xreply) {
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_platform_jailbreak_update(const char *updateTar)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_string(xargs, "update-tar", updateTar);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_PLATFORM, JBS_PLATFORM_JAILBREAK_UPDATE, xargs);
	xpc_release(xargs);
	if (xreply) {
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_platform_set_jailbreak_visible(bool visible)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(xargs, "visible", visible);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_PLATFORM, JBS_PLATFORM_SET_JAILBREAK_VISIBLE, xargs);
	xpc_release(xargs);
	if (xreply) {
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_watchdog_intercept_userspace_panic(const char *panicMessage)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_string(xargs, "panic-message", panicMessage);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_WATCHDOG, JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC, xargs);
	xpc_release(xargs);
	if (xreply) {
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_root_get_physrw(void)
{
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOT, JBS_ROOT_GET_PHYSRW, NULL);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_root_get_kcall(uint64_t stackAllocation, uint64_t *arcContextOut)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(xargs, "stack-allocation", stackAllocation);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOT, JBS_ROOT_GET_KCALL, xargs);
	xpc_release(xargs);
	if (xreply) {
		if (arcContextOut) *arcContextOut = xpc_dictionary_get_int64(xreply, "arc-context");
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_root_get_sysinfo(xpc_object_t *sysInfoOut)
{
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOT, JBS_ROOT_GET_KCALL, NULL);
	if (xreply) {
		if (sysInfoOut) *sysInfoOut = xpc_dictionary_get_dictionary(xreply, "sysinfo");
		int result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

int jbclient_root_add_cdhash(uint8_t *cdhashData, size_t cdhashLen)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_data(xargs, "cdhash", cdhashData, cdhashLen);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOT, JBS_ROOT_ADD_CDHASH, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}