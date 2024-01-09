#include "jbserver_xpc.h"

static bool root_domain_allowed(audit_token_t clientToken)
{
	return true;
}

static int root_get_physrw(audit_token_t *clientToken)
{

}

static int root_get_kcall(audit_token_t *clientToken)
{

}

static int root_get_sysinfo(void)
{

}

static int root_add_cdhash(uint8_t *cdhashData, size_t cdHashLen)
{

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
				{ 0 },
			},
		},
		// JBS_ROOT_GET_SYSINFO
		{
			.handler = root_get_sysinfo,
			.args = (jbserver_arg[]){
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