#include "jbserver_xpc.h"

static bool watchdog_domain_allowed(audit_token_t clientToken)
{
	return true;
}

static int watchdog_intercept_userspace_panic(const char *panicMessage)
{
	return 0;
}

struct jbserver_domain gWatchdogDomain = {
	.permissionHandler = watchdog_domain_allowed,
	.actions = {
		// JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC
		{
			.handler = watchdog_intercept_userspace_panic,
			.args = (jbserver_arg[]){
				{ .name = "panic-message", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		{ 0 },
	},
};