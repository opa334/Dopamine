#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/libjailbreak.h>

extern void systemwide_domain_set_enabled(bool enabled);

static bool platform_domain_allowed(audit_token_t clientToken)
{
	pid_t pid = audit_token_to_pid(clientToken);
	uint32_t csflags = 0;
	if (csops_audittoken(pid, CS_OPS_STATUS, &csflags, sizeof(csflags), &clientToken) != 0) return false;
	return (csflags & CS_PLATFORM_BINARY);
}

int platform_clear_process_noattach(uint64_t pid, bool preflight, bool hideTraced)
{
    uint64_t proc = proc_find(pid);
    if (!proc) return -1;
    // p_lflag stands next to p_flag
    off_t off_lflag = koffsetof(proc, flag) + sizeof(uint32_t);
    uint32_t flag = kread32(proc + off_lflag);
    if (preflight) {
        if ((flag & P_LNOATTACH) == 0) return 0;
        // clear P_LNOATTACH for ptrace
        // borrow an unused flag bit to indicate we cleared deny-attach
        flag &= ~P_LNOATTACH;
        flag |= P_LCLEARED_NOATTACH;
    } else {
        if ((flag & P_LCLEARED_NOATTACH) != 0) {
            // restore P_LNOATTACH
            flag &= ~P_LCLEARED_NOATTACH;
            flag |= P_LNOATTACH;
        }
        if (hideTraced) {
            // hide the fact that the process is being traced
            // FIXME: this might cause undefined behavior with debugger?
            flag &= ~P_LTRACED;
        }
    }
    kwrite32(proc + off_lflag, flag);
    return 0;
}

int platform_set_process_debugged(uint64_t pid, bool fullyDebugged)
{
	uint64_t proc = proc_find(pid);
	if (!proc) return -1;
	cs_allow_invalid(proc, fullyDebugged);
	return 0;
}

static int platform_stage_jailbreak_update(const char *updateTar)
{
	if (!access(updateTar, F_OK)) {
		setenv("STAGED_JAILBREAK_UPDATE", updateTar, 1);
		return 0;
	}
	return 1;
}

struct jbserver_domain gPlatformDomain = {
	.permissionHandler = platform_domain_allowed,
	.actions = {
		// JBS_PLATFORM_SET_PROCESS_DEBUGGED
		{
			.handler = platform_set_process_debugged,
			.args = (jbserver_arg[]){
				{ .name = "pid", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "fully-debugged", .type = JBS_TYPE_BOOL, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_STAGE_JAILBREAK_UPDATE
		{
			.handler = platform_stage_jailbreak_update,
			.args = (jbserver_arg[]){
				{ .name = "update-tar", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_JBSETTINGS_SET
		{
			.handler = jbsettings_set,
			.args = (jbserver_arg[]){
				{ .name = "key", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "value", .type = JBS_TYPE_XPC_GENERIC, .out = false },
				{ 0 },
			},
		},
		// JBS_PLATFORM_SET_SYSTEMWIDE_DOMAIN_ENABLED
		{
			.handler = systemwide_domain_set_enabled,
			.args = (jbserver_arg[]){
				{ .name = "enabled", .type = JBS_TYPE_BOOL, .out = false },
				{ 0 },
			},
		},
        // JBS_PLATFORM_CLEAR_PROCESS_NOATTACH
        {
            .handler = platform_clear_process_noattach,
            .args = (jbserver_arg[]){
                { .name = "pid", .type = JBS_TYPE_UINT64, .out = false },
                { .name = "preflight", .type = JBS_TYPE_BOOL, .out = false },
                { .name = "hide-traced", .type = JBS_TYPE_BOOL, .out = false },
                { 0 },
            },
        },
		{ 0 },
	},
};