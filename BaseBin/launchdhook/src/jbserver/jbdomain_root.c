#include "jbserver_global.h"
#include <libjailbreak/jbserver_boomerang.h>
#include <libjailbreak/trustcache.h>

static bool root_domain_allowed(audit_token_t clientToken)
{
	return (audit_token_to_euid(clientToken) == 0);
}

static int root_get_physrw(audit_token_t *clientToken)
{
	return boomerang_get_physrw(clientToken);
}

static int root_get_kcall(audit_token_t *clientToken, uint64_t stackAllocation, uint64_t *arcContextOut)
{
	return boomerang_get_kcall(clientToken, stackAllocation, arcContextOut);
}

static int root_get_sysinfo(xpc_object_t *sysInfoOut)
{
	return boomerang_get_sysinfo(sysInfoOut);
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
		// JBS_ROOT_GET_KCALL
		{
			.handler = root_get_kcall,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "stack-allocation", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "arc-context", .type = JBS_TYPE_UINT64, .out = true },
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
		{ 0 },
	},
};