#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/libjailbreak.h>
#include <libproc.h>

static char *read_file_to_string(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return NULL;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        return NULL;
    }
    rewind(fp);

    char *buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fclose(fp);
        return NULL;
    }

    size_t read_bytes = fread(buffer, 1, (size_t)size, fp);
    fclose(fp);

    if (read_bytes != (size_t)size) {
        free(buffer);
        return NULL;
    }

    buffer[size] = '\0';
    return buffer;
}


bool dopamine_domain_allowed(audit_token_t clientToken)
{
	char path[PATH_MAX];
	if (proc_pidpath_audittoken(&clientToken, path, PATH_MAX) <= 0) return false;
	return is_dopamine_app(path);
}

bool dopamine_is_jailbroken(char **outVersion)
{
	*outVersion = read_file_to_string(JBROOT_PATH("/basebin/.version"));
	return true;
}

int dopamine_get_root(audit_token_t *processToken)
{
	pid_t pid = audit_token_to_pid(*processToken);
	uint64_t proc = proc_find(pid);
	uint64_t ucred = proc_ucred(proc);

	if (kread32(ucred + koffsetof(ucred, uid)) == 501) {
		kwrite32(ucred + koffsetof(ucred, uid), 0);
		kwrite32(ucred + koffsetof(ucred, groups), 0);

		if (gSystemInfo.kernelStruct.proc_ro.exists) {
			uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));

			if (koffsetof(proc_ro, task_tokens)) {
				uint64_t auditToken = proc_ro + koffsetof(proc_ro, task_tokens) + koffsetof(task_token_ro_data, audit_token);
				kwrite32(auditToken + 4, 0); // uid
				kwrite32(auditToken + 8, 0); // gid
			}
		}

		return 0;
	}

	return 1;
}

int dopamine_drop_root(audit_token_t *processToken)
{
	pid_t pid = audit_token_to_pid(*processToken);
	uint64_t proc = proc_find(pid);
	uint64_t ucred = proc_ucred(proc);

	if (kread32(ucred + koffsetof(ucred, uid)) == 0) {
		kwrite32(ucred + koffsetof(ucred, uid), 501);
		kwrite32(ucred + koffsetof(ucred, groups), 501);

		if (gSystemInfo.kernelStruct.proc_ro.exists) {
			uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));

			if (koffsetof(proc_ro, task_tokens)) {
				uint64_t auditToken = proc_ro + koffsetof(proc_ro, task_tokens) + koffsetof(task_token_ro_data, audit_token);
				kwrite32(auditToken + 4, 501); // uid
				kwrite32(auditToken + 8, 501); // gid
			}
		}

		return 0;
	}

	return 1;
}

// FIX REMOVE-JAILBREAK EPERM (Issue 2) — dopamine-bundled unsandbox action.
//
// BUG (user screenshot: "rm /var/containers/Bundle/Application/.jbroot-XXXX (1)"
// = EPERM on every unlink/rmdir inside the jbroot while jailbroken):
//
// DOEnvironmentManager.deleteBootstrap (jailbroken path) runs the rmrf
// inside runAsRoot { runUnsandboxed { ... } }. runUnsandboxed unsandboxes
// the app via JBS_ROOT_SET_MAC_LABEL (ROOT domain). But the ROOT domain
// checks `audit_token_to_euid(caller) == 0`, and the euid the audit token
// reports is STALE unless dopamine_get_root's proc_ro task_tokens fixup
// ran and took effect (only possible when kernelStruct.proc_ro.exists &&
// the task_tokens offset is known). On kernels where the fixup doesn't
// apply, the token still says euid 501. A permission failure in the
// dispatcher returns -2 WITHOUT an XPC reply, so the client sees a NULL
// reply → jbclient_root_set_mac_label returns -1 → and runUnsandboxed
// IGNORED that return value and ran the block anyway, SANDBOXED.
//
// The sandbox state at that moment comes from systemwide_process_checkin:
// only com.apple.app-sandbox.read + com.apple.sandbox.executable were
// issued for the actual jbroot (Bundle/Application/.jbroot-<brand>); the
// ONLY read-write extension covers <jbroot>/var/mobile. lstat/open/
// readdir succeed through the read extension — which is why the rmrf gets
// far enough to enumerate the whole tree — but every unlink/rmdir OUTSIDE
// <jbroot>/var/mobile fails with EPERM(1) on the first file. That is the
// user's error verbatim.
//
// FIX: an unsandbox action INSIDE the DOPAMINE domain. Permission here is
// is_dopamine_app(bundle-id), which does NOT depend on the audit-token
// euid at all, so it cannot be denied by the stale-token race. The handler
// body is identical to root_set_mac_label (find the caller's proc from the
// audit-token pid and patch ITS label — never the server's). Restricting
// it to the Dopamine app keeps the security posture unchanged: only the
// app that could already call get_root can unsandbox itself.
int dopamine_set_mac_label(audit_token_t *processToken, uint64_t slot, uint64_t newLabel, uint64_t *orgLabel)
{
	if (slot >= 3) return -1;

	pid_t pid = audit_token_to_pid(*processToken);
	uint64_t proc = proc_find(pid);
	if (!proc) return -1;
	uint64_t ucred = proc_ucred(proc);
	if (!ucred) return -1;

	uint64_t label = kread_ptr(ucred + koffsetof(ucred, label));

	*orgLabel = mac_label_get(label, slot);
	mac_label_set(label, slot, newLabel);

	return 0;
}

struct jbserver_domain gDopamineDomain = {
	.permissionHandler = dopamine_domain_allowed,
	.actions = {
		// JBS_DOPAMINE_IS_JAILBROKEN
		{
			.handler = dopamine_is_jailbroken,
			.args = (jbserver_arg[]){
				{ .name = "version", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_DOPAMINE_GET_ROOT
		{
			.handler = dopamine_get_root,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_DOPAMINE_DROP_ROOT
		{
			.handler = dopamine_drop_root,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_DOPAMINE_SET_MAC_LABEL
		{
			.handler = dopamine_set_mac_label,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "slot", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "label", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "org-label", .type = JBS_TYPE_UINT64, .out = true },
				{ 0 },
			},
		},
		{ 0 },
	},
};