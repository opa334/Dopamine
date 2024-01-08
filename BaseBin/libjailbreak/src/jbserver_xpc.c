#include "jbserver_xpc.h"

static bool systemwide_domain_allowed(audit_token_t clientToken)
{
	return true;
}

static int systemwide_get_jb_root(char **pathOut)
{
	*pathOut = strdup("/var/jb");
	return 0;
}

static int systemwide_get_boot_uuid(char **uuidOut)
{
	const char *launchdUUID = getenv("LAUNCHD_UUID");
	if (launchdUUID) {
		*uuidOut = strdup(launchdUUID);
	}
	else {
		*uuidOut = NULL;
	}
	return 0;
}

static int systemwide_trust_binary(char *binaryPath)
{
	return 0;
}

static int systemwide_process_checkin(audit_token_t *processToken)
{
	return 0;
}

static int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid)
{
	return 0;
}

struct jbserver_domain gSystemwideDomain = {
	.permissionHandler = systemwide_domain_allowed,
	.actionCount = 2,
	.actions = {
		// JBS_SYSTEMWIDE_GET_JB_ROOT
		{
			.handler = systemwide_get_jb_root,
			.argCount = 1,
			.args = (jbserver_arg[]){
				{ .name = "jb-path", .type = JBS_TYPE_STRING, .out = true },
			},
		},
		// JBS_SYSTEMWIDE_GET_BOOT_UUID
		{
			.handler = systemwide_get_boot_uuid,
			.argCount = 1,
			.args = (jbserver_arg[]){
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
			},
		},
		// JBS_SYSTEMWIDE_TRUST_BINARY
		{
			.handler = systemwide_trust_binary,
			.argCount = 1,
			.args = (jbserver_arg[]){
				{ .name = "binary-path", .type = JBS_TYPE_STRING, .out = false },
			},
		},
		// JBS_SYSTEMWIDE_PROCESS_CHECKIN
		{
			.handler = systemwide_process_checkin,
			.argCount = 1,
			.args = (jbserver_arg[]) {
				{ .name = NULL, .type = JBS_TYPE_CALLER_TOKEN, .out = false },
			},
		},
		// JBS_SYSTEMWIDE_FORK_FIX
		{
			.handler = systemwide_fork_fix,
			.argCount = 1,
			.args = (jbserver_arg[]) {
				{ .name = NULL, .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
			},
		},
	},
};

struct jbserver_impl gGlobalServer = {
    .maxDomain = 1,
    .domains = (struct jbserver_domain*[]){
        &gSystemwideDomain,
    }
};

int jbserver_received_xpc_message(struct jbserver_impl *server, xpc_object_t xmsg)
{
	if (!xpc_dictionary_get_value(xmsg, "jb-domain")) return -1;
	if (!xpc_dictionary_get_value(xmsg, "action")) return -1;

	// TODO: Fix underflow when passed 0
	uint64_t domainIdx = xpc_dictionary_get_uint64(xmsg, "jb-domain") - 1;
	uint64_t actionIdx = xpc_dictionary_get_uint64(xmsg, "action") - 1;
	audit_token_t clientToken = { 0 };
	xpc_dictionary_get_audit_token(xmsg, &clientToken);

	if (domainIdx >= server->maxDomain) return -1;
	struct jbserver_domain *domain = server->domains[domainIdx];
	if (!domain) return -1;

	if (actionIdx >= domain->actionCount) return -1;
	struct jbserver_action *action = &domain->actions[actionIdx];

	int (*handler)(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8) = action->handler;
	void *args[8] = { NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL };
	void *argsOut[8] = { NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL };

	for (uint64_t i = 0; i < action->argCount; i++) {
		jbserver_arg *cArg = &action->args[i];
		if (!cArg->out) {
			switch (cArg->type) {
				case JBS_TYPE_STRING:
				args[i] = (void *)xpc_dictionary_get_string(xmsg, cArg->name);
				break;
				case JBS_TYPE_UINT64:
				args[i] = (void *)xpc_dictionary_get_uint64(xmsg, cArg->name);
				break;
				case JBS_TYPE_CALLER_TOKEN:
				args[i] = (void *)&clientToken;
				break;
			}
		}
		else {
			args[i] = &argsOut[i];
		}
	}

	int result = handler(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
	
	xpc_object_t xreply = xpc_dictionary_create_reply(xmsg);
	for (uint64_t i = 0; i < action->argCount; i++) {
		jbserver_arg *cArg = &action->args[i];
		if (cArg->out) {
			switch (cArg->type) {
				case JBS_TYPE_STRING: {
					if (argsOut[i]) {
						xpc_dictionary_set_string(xreply, cArg->name, (char *)argsOut[i]);
						free(argsOut[i]);
					}
					break;
				}
				case JBS_TYPE_UINT64:
				xpc_dictionary_set_uint64(xreply, cArg->name, (uint64_t)argsOut[i]);
				break;
				default:
				break;
			}
		}
	}
	xpc_dictionary_set_int64(xreply, "result", result);
	xpc_pipe_routine_reply(xreply);
	return 0;
}