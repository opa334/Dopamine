#include "jbserver_global.h"

static bool platform_domain_allowed(audit_token_t clientToken)
{
	return true;
}

static int platform_set_process_debugged(uint64_t pid)
{
	return 0;
}

static int platform_jailbreak_update(const char *updateTar)
{
	return 0;
}

static int platform_set_jailbreak_visible(bool visible)
{
	return 0;
}

struct jbserver_domain gPlatformDomain = {
	.permissionHandler = platform_domain_allowed,
	.actions = {
		// JBS_PLATFORM_SET_PROCESS_DEBUGGED
		{
			.handler = platform_set_process_debugged,
			.args = (jbserver_arg[]){
				{ .name = "pid", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_JAILBREAK_UPDATE
		{
			.handler = platform_jailbreak_update,
			.args = (jbserver_arg[]){
				{ .name = "update-tar", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_SET_JAILBREAK_VISIBLE
		{
			.handler = platform_set_jailbreak_visible,
			.args = (jbserver_arg[]){
				{ .name = "visible", .type = JBS_TYPE_BOOL, .out = false },
				{ 0 },
			},
		},
		{ 0 },
	},
};