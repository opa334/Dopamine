#include <signal.h>
#include "jbserver_global.h"

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>
#include <libjailbreak/codesign.h>

int roothide_unsupport_request()
{
	JBLogError("**************************** Unsupported request ****************************");
	return -1;
}

bool roothide_domain_allowed(audit_token_t clientToken)
{
	//its fast enough
	if(isBlacklistedToken(&clientToken)) {
		JBLogDebug("ignore xpc message from blacklisted process (%d),%s", audit_token_to_pid(clientToken), proc_get_path(audit_token_to_pid(clientToken),NULL));
		return false;
	}

	return true;
}

typedef struct {
	uint32_t Count;
	uint32_t* Types;
	uint32_t* Subtypes;
} preferredArchInfo;
void recurse_collect_untrusted_cdhashes(const char *path, const char *callerImagePath, const char *callerExecutablePath, const char *workingDir, preferredArchInfo* preferredArch, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut);

static int trust_macho_recurse(const char *machoPath, const char *dlopenCallerImagePath, const char *dlopenCallerExecutablePath, const char *workingDir, xpc_object_t preferredArchsArray)
{
	if(!machoPath || !dlopenCallerExecutablePath) return -1;
	
	size_t preferredArchCount = 0;
	if (preferredArchsArray) preferredArchCount = xpc_array_get_count(preferredArchsArray);
	uint32_t preferredArchTypes[preferredArchCount];
	uint32_t preferredArchSubtypes[preferredArchCount];
	for (size_t i = 0; i < preferredArchCount; i++) {
		preferredArchTypes[i] = 0;
		preferredArchSubtypes[i] = UINT32_MAX;
		xpc_object_t arch = xpc_array_get_value(preferredArchsArray, i);
		if (xpc_get_type(arch) == XPC_TYPE_DICTIONARY) {
			preferredArchTypes[i] = xpc_dictionary_get_uint64(arch, "type");
			preferredArchSubtypes[i] = xpc_dictionary_get_uint64(arch, "subtype");
		}
	}
	
	preferredArchInfo preferredArch = {preferredArchCount, preferredArchTypes, preferredArchSubtypes};

	cdhash_t *cdhashes = NULL;
	uint32_t cdhashesCount = 0;
	recurse_collect_untrusted_cdhashes(machoPath, dlopenCallerImagePath, dlopenCallerExecutablePath, workingDir, &preferredArch, &cdhashes, &cdhashesCount);
	if (cdhashes && cdhashesCount > 0) {
		jb_trustcache_add_cdhashes(cdhashes, cdhashesCount);
		free(cdhashes);
	}
	return 0;
}

int roothide_trust_executable_recurse(const char *executablePath, const char *processWorkingDir, xpc_object_t preferredArchsArray)
{
	return trust_macho_recurse(executablePath, NULL, executablePath, processWorkingDir, preferredArchsArray);
}

static int roothide_trust_library_recurse(const char *libraryPath, const char *callerLibraryPath, const char *callerExecutablePath, const char *currentWorkingDir)
{
	// When trusting a library that's dlopened at runtime, we need to pass the caller path
	// This is to support dlopen("@executable_path/whatever", RTLD_NOW) and stuff like that
	// (Yes that is a thing >.<)
	// Also we need to pass the path of the image that called dlopen due to @loader_path, sigh...
	return trust_macho_recurse(libraryPath, callerLibraryPath, callerExecutablePath, currentWorkingDir, NULL);
}

static int roothide_jailbroken_check(audit_token_t *callerToken, bool* jailbroken)
{
	*jailbroken = true;
	return 0;
}

static int roothide_palehide_present(audit_token_t *callerToken, bool* palehide)
{
	static bool result = false;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		if(jbinfo(palera1n)=='hide') {
			result = true;
		} else {
			// hang forver on iphone7p ios15.8.2
			// mach_port_t tfp0 = MACH_PORT_NULL;
			// kern_return_t kr = task_for_pid(mach_task_self(), 0, &tfp0);
			// if(kr == KERN_SUCCESS && MACH_PORT_VALID(tfp0)) {
			// 	mach_port_deallocate(mach_task_self(), tfp0);
			// 	result = true;
			// }
		}
	});

	*palehide = result;
	return 0;
}

static int roothide_blacklist_check(audit_token_t *callerToken, const char* checktype, xpc_object_t checkvalue, bool* blacklisted)
{
	if(strcmp(checktype, "pid")==0) {
		pid_t pid = (pid_t)xpc_uint64_get_value(checkvalue);
		if(pid > 1) {
			*blacklisted = isBlacklistedPid(pid);
			return 0;
		}
	} else if(strcmp(checktype, "path")==0) {
		const char* path = xpc_string_get_string_ptr(checkvalue);
		if(path) {
			*blacklisted = isBlacklistedPath(path);
			return 0;
		}
	} else if(strcmp(checktype, "bundle")==0) {
		const char* bundle = xpc_string_get_string_ptr(checkvalue);
		if(bundle) {
			*blacklisted = isBlacklistedApp(bundle);
			return 0;
		}
	} else {
		JBLogError("Invalid checktype: %s", checktype);
		return -1;
	}
	JBLogError("Failed to check blacklist for %s : %s", checktype, xpc_type_get_name(xpc_get_type(checkvalue)));
	return -1;
}

static int roothide_jailbreakd_lookup(audit_token_t *callerToken, xpc_object_t *portOut)
{
	*portOut = xpc_mach_send_create(jailbreakdClientPort());
	return 0;
}

static int roothide_jailbreakd_checkin(audit_token_t *callerToken, xpc_object_t *portOut)
{
	pid_t pid = audit_token_to_pid(*callerToken);
	uid_t uid = audit_token_to_euid(*callerToken);

	if(uid != 0) return -1;

	setJailbreakdProcess(pid);

	*portOut = xpc_mach_recv_create(jailbreakdServerPort());
	return 0;
}

static int roothide_dyld_patch_enabled(audit_token_t *callerToken, bool* enabled)
{
	*enabled = jbinfo(dyld_patch_enabled);
	return 0;
}

static int roothide_set_dyld_patch(audit_token_t *callerToken, bool enabled)
{
	pid_t pid = audit_token_to_pid(*callerToken);
	uid_t uid = audit_token_to_euid(*callerToken);

    uint32_t csFlags = 0;
    csops(getpid(), CS_OPS_STATUS, &csFlags, sizeof(csFlags));

	if(uid != 0 && (csFlags & CS_PLATFORM_BINARY)==0) {
		JBLogError("roothide_set_dyld_patch: denying request from %d,%d", pid, uid);
		return -1;
	}
	
#ifdef __arm64e__
	if (!__builtin_available(iOS 16.0, *))
	{
		if(roothide_config_set_spinlock_fix(enabled) != 0) {
			JBLogError("roothide_config_set_spinlock_fix failed");
			return -1;
		}
	}
#endif

	jbinfo(dyld_patch_enabled) = enabled;
	
	return 0;
}

struct jbserver_domain gRootHideDomain = {
	.permissionHandler = roothide_domain_allowed,
	.actions = {
		//JBS_ROOTHIDE_JAILBROKEN_CHECK
        {
            .handler = roothide_jailbroken_check,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "jailbroken", .type = JBS_TYPE_BOOL, .out = true },
                    { 0 },
            },
        },
		//JBS_ROOTHIDE_PALEHIDE_PRESENT
        {
            .handler = roothide_palehide_present,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "palehide", .type = JBS_TYPE_BOOL, .out = true },
                    { 0 },
            },
        },
		//JBS_ROOTHIDE_BLACKLIST_CHECK
        {
            .handler = roothide_blacklist_check,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
					{ .name = "checktype", .type = JBS_TYPE_STRING, .out = false },
					{ .name = "checkvalue", .type = JBS_TYPE_XPC_GENERIC, .out = false },
                    { .name = "blacklisted", .type = JBS_TYPE_BOOL, .out = true },
                    { 0 },
            },
        },
		//JBS_ROOTHIDE_JAILBREAKD_LOOKUP
        {
            .handler = roothide_jailbreakd_lookup,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "port", .type = JBS_TYPE_XPC_GENERIC, .out = true },
                    { 0 },
            },
        },
		//JBS_ROOTHIDE_JAILBREAKD_CHECKIN
        {
            .handler = roothide_jailbreakd_checkin,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "port", .type = JBS_TYPE_XPC_GENERIC, .out = true },
                    { 0 },
            },
        },
		// JBS_ROOTHIDE_TRUST_LIBRARY_RECURSE
		{
			.handler = roothide_trust_library_recurse,
			.args = (jbserver_arg[]){
				{ .name = "library-path", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "caller-library-path", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "caller-executable-path", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "current-working-dir", .type = JBS_TYPE_STRING, .out = false },
				{ 0 },
			},
		},
		// JBS_ROOTHIDE_TRUST_EXECUTABLE_RECURSE
		{
			.handler = roothide_trust_executable_recurse,
			.args = (jbserver_arg[]){
				{ .name = "executable-path", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "process-working-dir", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "preferred-archs", .type = JBS_TYPE_ARRAY, .out = false },
				{ 0 },
			},
		},
		//JBS_ROOTHIDE_DYLD_PATCH_ENABLED_GET
        {
            .handler = roothide_dyld_patch_enabled,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "enabled", .type = JBS_TYPE_BOOL, .out = true },
                    { 0 },
            },
        },
		//JBS_ROOTHIDE_DYLD_PATCH_ENABLED_SET
        {
            .handler = roothide_set_dyld_patch,
            .args = (jbserver_arg[]) {
                    { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                    { .name = "enabled", .type = JBS_TYPE_BOOL, .out = false },
                    { 0 },
            },
        },
		{ 0 },
	},
};