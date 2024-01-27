#include "jbserver_global.h"
#include <libjailbreak/jbserver_boomerang.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/info.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/primitives.h>

static bool root_domain_allowed(audit_token_t clientToken)
{
	return (audit_token_to_euid(clientToken) == 0);
}

static int root_get_physrw(audit_token_t *clientToken)
{
	return boomerang_get_physrw(clientToken);
}

static int root_sign_thread(audit_token_t *clientToken, mach_port_t threadPort)
{
	return boomerang_sign_thread(clientToken, threadPort);
}

static int root_get_sysinfo(xpc_object_t *sysInfoOut)
{
	return boomerang_get_sysinfo(sysInfoOut);
}

static int root_steal_ucred(audit_token_t *clientToken, uint64_t ucred, uint64_t *orgUcred)
{
	if (!ucred) {
		// Passing 0 to this means kernel ucred
		uint64_t kernproc = proc_find(0);
		ucred = proc_ucred(kernproc);
	}

	pid_t pid = audit_token_to_pid(*clientToken);
	uint64_t proc = proc_find(pid);

	*orgUcred = proc_ucred(proc);
	if (gSystemInfo.kernelStruct.proc_ro.exists) {
		uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
		kwrite64(proc_ro + koffsetof(proc_ro, ucred), ucred);
	}
	else {
		// TODO: 15.0 - 15.1.1: Data PAC
	}

	return 0;
}

static int root_add_cdhash(uint8_t *cdhashData, size_t cdhashLen)
{
	if (cdhashLen != CS_CDHASH_LEN) return -1;
	return jb_trustcache_add_cdhashes((cdhash_t *)cdhashData, 1);
}

struct jbserver_domain gRootDomain = {
	.permissionHandler = root_domain_allowed,
	.actions = {
		// JBS_ROOT_GET_PHYSRW
		{
			.handler = root_get_physrw,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOT_SIGN_THREAD
		{
			.handler = root_sign_thread,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "thread-port", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOT_GET_SYSINFO
		{
			.handler = root_get_sysinfo,
			.args = (jbserver_arg[]){
				{ .name = "sysinfo", .type = JBS_TYPE_DICTIONARY, .out = true },
				{ 0 },
			},
		},
		// JBS_ROOT_ADD_CDHASH
		{
			.handler = root_add_cdhash,
			.args = (jbserver_arg[]){
				{ .name = "cdhash", .type = JBS_TYPE_DATA, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOT_STEAL_UCRED
		{
			.handler = root_steal_ucred,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "ucred", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "org-ucred", .type = JBS_TYPE_UINT64, .out = true },
				{ 0 },
			},
		},
		{ 0 },
	},
};