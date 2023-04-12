#include "common.h"
#include <xpc/xpc.h>
#include "launchd.h"
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sandbox.h>

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t * __restrict, int * __restrict) __API_AVAILABLE(macos(10.8), ios(6.0));

#define HOOK_DYLIB_PATH "/usr/lib/systemhook.dylib"
#define JBD_MSG_SETUID_FIX 21
#define JBD_MSG_PROCESS_BINARY 22
#define JBD_MSG_DEBUG_ME 24

#define JETSAM_MULTIPLIER 3
#define XPC_TIMEOUT 0.1 * NSEC_PER_SEC

extern char **environ;
kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

bool jbdSystemWideIsReachable(void)
{
	int sbc = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_GLOBAL_NAME | SANDBOX_CHECK_NO_REPORT, "com.opa334.jailbreakd.systemwide");
	return sbc == 0;
}

mach_port_t jbdSystemWideMachPort(void)
{
	mach_port_t outPort = MACH_PORT_NULL;
	kern_return_t kr = KERN_SUCCESS;

	if (getpid() == 1) {
		mach_port_t self_host = mach_host_self();
		kr = host_get_special_port(self_host, HOST_LOCAL_NODE, 16, &outPort);
		mach_port_deallocate(mach_task_self(), self_host);
	}
	else {
		kr = bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd.systemwide", &outPort);
	}

	if (kr != KERN_SUCCESS) return MACH_PORT_NULL;
	return outPort;
}

xpc_object_t sendLaunchdMessageFallback(xpc_object_t xdict)
{
	xpc_dictionary_set_bool(xdict, "jailbreak", true);
	xpc_dictionary_set_bool(xdict, "jailbreak-systemwide", true);

	void* pipePtr = NULL;
	if(_os_alloc_once_table[1].once == -1)
	{
		pipePtr = _os_alloc_once_table[1].ptr;
	}
	else
	{
		pipePtr = _os_alloc_once(&_os_alloc_once_table[1], 472, NULL);
		if (!pipePtr) _os_alloc_once_table[1].once = -1;
	}

	xpc_object_t xreply = nil;
	if (pipePtr) {
		struct xpc_global_data* globalData = pipePtr;
		xpc_object_t pipe = globalData->xpc_bootstrap_pipe;
		if (pipe) {
			int err = xpc_pipe_routine_with_flags(pipe, xdict, &xreply, 0);
			if (err != 0) {
				return nil;
			}
		}
	}
	return xreply;
}

xpc_object_t sendJBDMessageSystemWide(xpc_object_t xdict)
{
	xpc_object_t jbd_xreply = nil;
	if (jbdSystemWideIsReachable()) {
		mach_port_t jbdPort = jbdSystemWideMachPort();
		if (jbdPort != -1) {
			xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);
			if (pipe) {
				int err = xpc_pipe_routine(pipe, xdict, &jbd_xreply);
				if (err != 0) jbd_xreply = nil;
				xpc_release(pipe);
			}
			mach_port_deallocate(mach_task_self(), jbdPort);
		}
	}

	if (!jbd_xreply && getpid() != 1) {
		return sendLaunchdMessageFallback(xdict);
	}

	return jbd_xreply;
}

int64_t jbdswFixSetuid(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_SETUID_FIX);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdswProcessBinary(const char *filePath)
{
	// if file doesn't exist, bail out
	if (access(filePath, F_OK) != 0) return 0;

	// if file is on rootfs mount point, it doesn't need to be
	// processed as it's guaranteed to be in static trust cache
	// same goes for our /usr/lib bind mount
	struct statfs fs;
	int sfsret = statfs(filePath, &fs);
	if (sfsret == 0) {
		if (!strcmp(fs.f_mntonname, "/") || !strcmp(fs.f_mntonname, "/usr/lib")) return -1;
	}

	char absolutePath[PATH_MAX];
	if (realpath(filePath, absolutePath) == NULL) return -1;

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROCESS_BINARY);
	xpc_dictionary_set_string(message, "filePath", absolutePath);

	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdswProcessLibrary(const char *filePath)
{
	if (_dyld_shared_cache_contains_path(filePath)) return 0;
	return jbdswProcessBinary(filePath);
}

int64_t jbdswDebugMe(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DEBUG_ME);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}


char *resolvePath(const char *file, const char *searchPath)
{
	if (!file) return NULL;

	if (access(file, X_OK) == 0) {
		return strdup(file);
	}

	const char *searchPathToUse = searchPath;
	if (!searchPathToUse) {
		searchPathToUse = getenv("PATH");
	}

	char *dir = strtok((char *)searchPathToUse, ":");
	char fullpath[1024];

	while (dir != NULL) {
		sprintf(fullpath, "%s/%s", dir, file);
		if (access(fullpath, X_OK) == 0) {
			return strdup(fullpath);
		}
		dir = strtok(NULL, ":");
	}

	return NULL;
}

bool stringEndsWith(const char* str, const char* suffix)
{
	size_t str_len = strlen(str);
	size_t suffix_len = strlen(suffix);

	if (str_len < suffix_len) {
		return 0;
	}

	return !strcmp(str + str_len - suffix_len, suffix);
}

// I don't like the idea of blacklisting certain processes
// But for some it seems neccessary

typedef enum 
{
	kBinaryConfigDontInject = 1 << 0,
	kBinaryConfigDontProcess = 1 << 1
} kBinaryConfig;

kBinaryConfig configForBinary(const char* path, char *const argv[restrict])
{
	// Don't do anything for jailbreakd because this wanting to launch implies it's not running currently
	if (stringEndsWith(path, "/jailbreakd")) {
		return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
	}

	// Don't do anything for xpcproxy if it's called on jailbreakd because this also implies jbd is not running currently
	if (!strcmp(path, "/usr/libexec/xpcproxy")) {
		if (argv) {
			if (argv[0]) {
				if (argv[1]) {
					if (!strcmp(argv[1], "com.opa334.jailbreakd")) {
						return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
					}
				}
			}
		}
	}

	// Blacklist to ensure general system stability
	// I don't like this but it seems neccessary
	const char *processBlacklist[] = {
		"/System/Library/Frameworks/GSS.framework/Helpers/GSSCred",
		"/System/Library/PrivateFrameworks/IDSBlastDoorSupport.framework/XPCServices/IDSBlastDoorService.xpc/IDSBlastDoorService"
	};
	size_t blacklistCount = sizeof(processBlacklist) / sizeof(processBlacklist[0]);
	for (size_t i = 0; i < blacklistCount; i++)
	{
		if (!strcmp(processBlacklist[i], path)) return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
	}

	return 0;
}

// Make sure the about to be spawned binary and all of it's dependencies are trust cached
// Insert "DYLD_INSERT_LIBRARIES=/usr/lib/systemhook.dylib" into all binaries spawned

int spawn_hook_common(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict],
					   void *orig)
{
	int (*pspawn_orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]) = orig;
	if (!path) {
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);
	}

	kBinaryConfig binaryConfig = configForBinary(path, argv);

	if (!(binaryConfig & kBinaryConfigDontProcess)) {
		// jailbreakd: Upload binary to trustcache if needed
		jbdswProcessBinary(path);
	}

	// Determine length envp passed
	char **ogEnv = (char **)envp;
	size_t ogEnvCount = 0;
	if (ogEnv) {
		while (ogEnv[ogEnvCount++] != NULL);
	}

	bool shouldInject = true;
	int existingSafeModeIndex = -1;
	int existingMSSafeModeIndex = -1;

	if (shouldInject) {
		// Check if we can find a _SafeMode or _MSSafeMode variable
		// In this case we do not want to inject anything
		// But we also want to remove the variables before spawning the process
		
		const char *safeModeVar = "_SafeMode=1";
		if (ogEnvCount > 0) {
			for (int i = 0; i < ogEnvCount-1; i++) {
				if(strncmp(ogEnv[i], safeModeVar, strlen(safeModeVar)) == 0) {
					shouldInject = false;
					existingSafeModeIndex = i;
					break;
				}
			}
		}
		
		const char *msSafeModeVar = "_MSSafeMode=1";
		if (ogEnvCount > 0) {
			for (int i = 0; i < ogEnvCount-1; i++) {
				if(strncmp(ogEnv[i], msSafeModeVar, strlen(msSafeModeVar)) == 0) {
					shouldInject = false;
					existingMSSafeModeIndex = i;
					break;
				}
			}
		}
	}
	
	if (binaryConfig & kBinaryConfigDontInject) {
		shouldInject = false;
	}
	
	if (attrp) {
		int proctype = 0;
		posix_spawnattr_getprocesstype_np(attrp, &proctype);
		if (proctype == POSIX_SPAWN_PROC_TYPE_DRIVER) {
			// Do not inject hook into DriverKit drivers
			shouldInject = false;
		}
	}
	
	if (shouldInject) {
		if (access(HOOK_DYLIB_PATH, F_OK) != 0) {
			// If the hook dylib doesn't exist, don't try to inject it (would crash the process)
			shouldInject = false;
		}
	}

	// Check if we can find an existing "DYLD_INSERT_LIBRARIES" env variable
	int existingLibraryInsertIndex = -1;
	const char *insertVarPrefix = "DYLD_INSERT_LIBRARIES=";
	if (ogEnvCount > 0) {
		for (int i = 0; i < ogEnvCount-1; i++) {
			if(strncmp(ogEnv[i], insertVarPrefix, strlen(insertVarPrefix)) == 0) {
				existingLibraryInsertIndex = i;
				break;
			}
		}
	}

	// If we have found an existing DYLD_INSERT_LIBRARIES variable, check if the systemwide.dylib is already in there
	bool isAlreadyInjected = false;
	if (existingLibraryInsertIndex != -1) {
		char *const existingEnv = ogEnv[existingLibraryInsertIndex];
		char *existingStart = strstr(existingEnv, HOOK_DYLIB_PATH);
		if (existingStart) {
			char before = 0;
			if (existingStart > existingEnv) {
				before = existingStart[-1];
			}
			char after = existingStart[strlen(HOOK_DYLIB_PATH)];
			isAlreadyInjected = (before == '=' || before == ':') && (after == '\0' || after == ':');
		}
	}

	if (shouldInject == isAlreadyInjected && (existingSafeModeIndex == -1 && existingMSSafeModeIndex == -1)) {
		// we already good, just call orig
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);
	}
	else {
		// the state we want is not the state we are in right now

		if (shouldInject) {
			// Add dylib insert environment variable
			// If we did not find an existing variable, new size is one bigger than the old size
			size_t newEnvCount = ogEnvCount + (existingLibraryInsertIndex == -1);
			if (ogEnvCount == 0) newEnvCount = 2; // if og is 0, new needs to be 2 (our var + NULL)

			// Create copy of environment to pass to posix_spawn
			// Unlike the environment passed to here, this has to be deallocated later
			char **newEnv = malloc(newEnvCount * sizeof(char *));
			if (ogEnvCount > 0) {
				for (int i = 0; i < ogEnvCount-1; i++) {
					newEnv[i] = strdup(ogEnv[i]);
				}
			}
			newEnv[newEnvCount-1] = NULL;

			if (existingLibraryInsertIndex == -1) {
				//printf("No DYLD_INSERT_LIBRARIES exists, inserting...\n");
				// No DYLD_INSERT_LIBRARIES exists, insert our own at position newEnvCount-2 as we have allocated extra space for it there
				newEnv[newEnvCount-2] = strdup("DYLD_INSERT_LIBRARIES=" HOOK_DYLIB_PATH);
			}
			else {
				//printf("DYLD_INSERT_LIBRARIES already exists, replacing...\n");
				// DYLD_INSERT_LIBRARIES already exists, append systemwide.dylib to existing one
				char *const existingEnv = ogEnv[existingLibraryInsertIndex];
				//printf("Existing env variable: %s\n", existingEnv);

				free(newEnv[existingLibraryInsertIndex]);
				const char *hookDylibInsert = HOOK_DYLIB_PATH ":";
				size_t hookDylibInsertLen = strlen(hookDylibInsert);
				char *newInsertVar = malloc(strlen(existingEnv) + hookDylibInsertLen + 1);

				size_t insertEnvLen = strlen(insertVarPrefix);
				char *const existingEnvPrefix = &existingEnv[strlen(insertVarPrefix)];
				size_t existingEnvPrefixLen = strlen(existingEnvPrefix);

				strncpy(&newInsertVar[0], insertVarPrefix, insertEnvLen);
				strncpy(&newInsertVar[insertEnvLen], hookDylibInsert, hookDylibInsertLen);
				strncpy(&newInsertVar[insertEnvLen+hookDylibInsertLen], &existingEnv[insertEnvLen], existingEnvPrefixLen+1);

				newEnv[existingLibraryInsertIndex] = newInsertVar;
			}

			// Call posix_spawn with new environment
			int orgReturn = pspawn_orig(pid, path, file_actions, attrp, argv, newEnv);

			// Free new environment
			for (int i = 0; i < newEnvCount; i++) {
				free(newEnv[i]);
			}
			free(newEnv);

			return orgReturn;
		}
		else {
			// Remove any existing modifications of environment
			char *replacementLibraryInsertStr = NULL;
			
			if (existingLibraryInsertIndex != -1) {
				
				// If there is an existing DYLD_INSERT_LIBRARIES variable and there is other dylibs in it, just remove systemhook
				// If there are no other dylibs in it, remove it entirely
				
				char *const existingLibraryInsertStr = ogEnv[existingLibraryInsertIndex];
				char *existingLibraryStart = strstr(existingLibraryInsertStr, HOOK_DYLIB_PATH);
				if (existingLibraryStart) {
					size_t hookDylibLen = strlen(HOOK_DYLIB_PATH);
					
					char *afterStart = &existingLibraryStart[hookDylibLen+1];
					
					char charBefore = existingLibraryStart[-1];
					char charAfter = afterStart[-1];
					
					bool hasPathBefore = charBefore == ':';
					bool hasPathAfter = charAfter == ':';
					
					if (hasPathBefore || hasPathAfter) {
						
						size_t newVarSize = (strlen(existingLibraryInsertStr)+1) - (hookDylibLen+1);
						replacementLibraryInsertStr = malloc(newVarSize);
						
						if (hasPathBefore && !hasPathAfter) {
							strncpy(&replacementLibraryInsertStr[0], existingLibraryInsertStr, existingLibraryStart-existingLibraryInsertStr-1);
							replacementLibraryInsertStr[existingLibraryStart-existingLibraryInsertStr-1] = '\0';
						}
						else {
							strncpy(&replacementLibraryInsertStr[0], existingLibraryInsertStr, existingLibraryStart-existingLibraryInsertStr);
							strncpy(&replacementLibraryInsertStr[strlen(replacementLibraryInsertStr)], afterStart, strlen(afterStart));
						}
					}
				}
				else {
					replacementLibraryInsertStr = strdup(existingLibraryInsertStr);
				}
			}
			
			size_t noSafeModeEnvCount = ogEnvCount - (existingSafeModeIndex != -1) - (existingMSSafeModeIndex != -1) - (replacementLibraryInsertStr == NULL);
			char **noSafeModeEnv = malloc(noSafeModeEnvCount * sizeof(char *));
			int ci = 0;
			for (int i = 0; i < ogEnvCount; i++) {
				if (existingSafeModeIndex != -1) {
					if (i == existingSafeModeIndex) continue;
				}
				if (existingMSSafeModeIndex != -1) {
					if (i == existingMSSafeModeIndex) continue;
				}
				if (existingLibraryInsertIndex != -1) {
					if (i == existingLibraryInsertIndex) {
						if (replacementLibraryInsertStr) {
							noSafeModeEnv[ci++] = replacementLibraryInsertStr;
						}
						continue;
					}
				}
				noSafeModeEnv[ci++] = ogEnv[i];
			}
			int ret = pspawn_orig(pid, path, file_actions, attrp, argv, noSafeModeEnv);
			if (replacementLibraryInsertStr) {
				free(replacementLibraryInsertStr);
			}
			free(noSafeModeEnv);
			return ret;
		}
	}
}

// Increase Jetsam limits by a factor of JETSAM_MULTIPLIER

int posix_spawnattr_setjetsam_replacement(posix_spawnattr_t *attr, short flags, int priority, int memlimit, void *orig)
{
	int (*posix_spawnattr_setjetsam_orig)(posix_spawnattr_t *, short, int, int) = orig;
	return posix_spawnattr_setjetsam_orig(attr, flags, priority, memlimit * JETSAM_MULTIPLIER);
}

int posix_spawnattr_setjetsam_ext_replacement(posix_spawnattr_t *attr, short flags, int priority, int memlimit_active, int memlimit_inactive, void *orig)
{
	int (*posix_spawnattr_setjetsam_ext_replacement)(posix_spawnattr_t *, short, int, int, int) = orig;
	return posix_spawnattr_setjetsam_ext_replacement(attr, flags, priority, memlimit_active * JETSAM_MULTIPLIER, memlimit_inactive * JETSAM_MULTIPLIER);
}
