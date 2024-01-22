#include "jbserver_global.h"
#include <libjailbreak/info.h>
#include <sandbox.h>
#include <libproc.h>
#include <libproc_private.h>

#include <libjailbreak/signatures.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/util.h>
#include <libjailbreak/primitives.h>

static bool systemwide_domain_allowed(audit_token_t clientToken)
{
	return true;
}

static int systemwide_get_jb_root(char **pathOut)
{
	*pathOut = strdup(jbinfo(rootPath));
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

static int trust_file(const char *filePath, const char *callerPath)
{
	// Shared logic between client and server, implemented in client
	// This should essentially mean these files never reach us in the first place
	// But you know, never trust the client :D
	extern bool can_skip_trusting_file(const char *filePath);

	if (!filePath) return -1;
	if (can_skip_trusting_file(filePath)) return -1;

	cdhash_t *cdhashes = NULL;
	uint32_t cdhashesCount = 0;
	macho_collect_untrusted_cdhashes(filePath, callerPath, &cdhashes, &cdhashesCount);
	if (cdhashesCount > 0) {
		jb_trustcache_add_cdhashes(cdhashes, cdhashesCount);
	}
	return 0;
}

// Not static because launchd will directly call this from it's posix_spawn hook
int systemwide_trust_binary(const char *binaryPath)
{
	return trust_file(binaryPath, NULL);
}

static int systemwide_trust_library(audit_token_t *processToken, const char *libraryPath)
{
	// Fetch process info
	pid_t pid = audit_token_to_pid(*processToken);
	char callerPath[4*MAXPATHLEN];
	if (proc_pidpath(pid, callerPath, sizeof(callerPath)) < 0) {
		return -1;
	}

	// When trusting a library that's dlopened at runtime, we need to pass the caller path
	// This is to support dlopen("@executable_path/whatever", RTLD_NOW) and stuff like that
	// (Yes that is a thing >.<)
	return trust_file(libraryPath, callerPath);
}

static int systemwide_process_checkin(audit_token_t *processToken, char **rootPathOut, char **jbBootUUIDOut, char **sandboxExtensionsOut)
{
	// Fetch process info
	pid_t pid = audit_token_to_pid(*processToken);
	uint64_t proc = proc_find(pid);
	char procPath[4*MAXPATHLEN];
	if (proc_pidpath(pid, procPath, sizeof(procPath)) < 0) {
		return -1;
	}

	// Pass jbroot and boot uuid
	systemwide_get_jb_root(rootPathOut);
	systemwide_get_boot_uuid(jbBootUUIDOut);

	// Generate sandbox extensions for the requesting process
	char *readExtension = sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read", JBRootPath(""), 0, *processToken);
	char *execExtension = sandbox_extension_issue_file_to_process("com.apple.sandbox.executable", JBRootPath(""), 0, *processToken);
	if (readExtension && execExtension) {
		char extensionBuf[strlen(readExtension) + 1 + strlen(execExtension) + 1];
		strcat(extensionBuf, readExtension);
		strcat(extensionBuf, "|");
		strcat(extensionBuf, execExtension);
		free(readExtension);
		free(execExtension);
		*sandboxExtensionsOut = strdup(extensionBuf);
	}

	// Allow invalid pages
	cs_allow_invalid(proc, false);

	// Fix setuid
	struct stat sb;
	if (stat(procPath, &sb) == 0) {
		if (S_ISREG(sb.st_mode) && (sb.st_mode & (S_ISUID | S_ISGID))) {
			uint64_t ucred = proc_ucred(proc);
			if ((sb.st_mode & (S_ISUID))) {
				kwrite32(proc + koffsetof(proc, svuid), sb.st_uid);
				kwrite32(ucred + koffsetof(ucred, svuid), sb.st_uid);
				kwrite32(ucred + koffsetof(ucred, uid), sb.st_uid);
			}
			if ((sb.st_mode & (S_ISGID))) {
				kwrite32(proc + koffsetof(proc, svgid), sb.st_gid);
				kwrite32(ucred + koffsetof(ucred, svgid), sb.st_gid);
				kwrite32(ucred + koffsetof(ucred, groups), sb.st_gid);
			}
			uint32_t flag = kread32(proc + koffsetof(proc, flag));
			if ((flag & P_SUGID) != 0) {
				flag &= ~P_SUGID;
				kwrite32(proc + koffsetof(proc, flag), flag);
			}
		}
	}

	return 0;
}

static int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid)
{
	return 0;
}

struct jbserver_domain gSystemwideDomain = {
	.permissionHandler = systemwide_domain_allowed,
	.actions = {
		// JBS_SYSTEMWIDE_GET_JB_ROOT
		{
			.handler = systemwide_get_jb_root,
			.args = (jbserver_arg[]){
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_GET_BOOT_UUID
		{
			.handler = systemwide_get_boot_uuid,
			.args = (jbserver_arg[]){
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_TRUST_BINARY
		{
			.handler = systemwide_trust_binary,
			.args = (jbserver_arg[]){
				{ .name = "binary-path", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_TRUST_LIBRARY
		{
			.handler = systemwide_trust_library,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "library-path", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_PROCESS_CHECKIN
		{
			.handler = systemwide_process_checkin,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "sandbox-extensions", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_FORK_FIX
		{
			.handler = systemwide_fork_fix,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		{ 0 },
	},
};