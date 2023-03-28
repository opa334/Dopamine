#import "common.h"
#include <xpc/xpc.h>
#import <mach-o/dyld.h>

#define HOOK_DYLIB_PATH "/usr/lib/systemhook.dylib"
#define JBD_MSG_SETUID_FIX 21
#define JBD_MSG_PROCESS_BINARY 22
#define JBD_MSG_DEBUG_ME 24

#define JETSAM_MULTIPLIER 3

extern char **environ;
kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

mach_port_t jbdSystemWideMachPort(void)
{
	mach_port_t outPort = -1;

	if (getpid() == 1) {
		mach_port_t self_host = mach_host_self();
		host_get_special_port(self_host, HOST_LOCAL_NODE, 16, &outPort);
		mach_port_deallocate(mach_task_self(), self_host);
	}
	else {
		bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd.systemwide", &outPort);
	}

	return outPort;
}

xpc_object_t sendJBDMessageSystemWide(xpc_object_t message)
{
	mach_port_t jbdPort = jbdSystemWideMachPort();
	xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);

	xpc_object_t reply = nil;
	int err = xpc_pipe_routine(pipe, message, &reply);
	xpc_release(pipe);
	mach_port_deallocate(mach_task_self(), jbdPort);
	if (err != 0) {
		return nil;
	}

	return reply;
}

int64_t jbdFixSetuid(void)
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

int64_t jbdProcessBinary(const char *filePath)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROCESS_BINARY);
	xpc_dictionary_set_string(message, "filePath", filePath);

	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdProcessLibrary(const char *filePath)
{
	if (_dyld_shared_cache_contains_path(filePath)) return 0;
	return jbdProcessBinary(filePath);
}

int64_t jbdDebugMe(void)
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

// I don't like the idea of blacklisting certain processes
// But for some it seems neccessary
bool processIsBlacklisted(const char* path)
{
	const char *processBlacklist[] = {
		"/System/Library/Frameworks/GSS.framework/Helpers/GSSCred"
	};

	size_t blacklistCount = sizeof(processBlacklist) / sizeof(processBlacklist[0]);
	for (size_t i = 0; i < blacklistCount; i++)
	{
		if (!strcmp(processBlacklist[i], path)) return true;
	}
	return false;
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

	if (processIsBlacklisted(path)) {
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);
	}

	// jailbreakd: Make sure binary is in trustcache
	jbdProcessBinary(path);

	// Determine length envp passed
	char **ogEnv = (char **)envp;
	size_t ogEnvCount = 0;
	if (ogEnv) {
		while (ogEnv[ogEnvCount++] != NULL);
	}

	// Check if we can find a _SafeMode or _MSSafeMode variable
	// In this case we do not want to inject anything
	// But we also want to remove the variables before spawning the process
	int existingSafeMode = -1;
	const char *safeModeVar = "_SafeMode=1";
	if (ogEnvCount > 0) {
		for (int i = 0; i < ogEnvCount-1; i++) {
			if(strncmp(ogEnv[i], safeModeVar, strlen(safeModeVar)) == 0) {
				existingSafeMode = i;
				break;
			}
		}
	}
	int existingMSSafeMode = -1;
	const char *msSafeModeVar = "_MSSafeMode=1";
	if (ogEnvCount > 0) {
		for (int i = 0; i < ogEnvCount-1; i++) {
			if(strncmp(ogEnv[i], msSafeModeVar, strlen(msSafeModeVar)) == 0) {
				existingMSSafeMode = i;
				break;
			}
		}
	}
	if (existingSafeMode != -1 || existingMSSafeMode != -1) {
		size_t noSafeModeEnvCount = ogEnvCount - (existingSafeMode != -1) - (existingMSSafeMode != -1);
		char **noSafeModeEnv = malloc(noSafeModeEnvCount * sizeof(char *));
		int ci = 0;
		for (int i = 0; i < ogEnvCount; i++) {
			if (existingSafeMode != -1) {
				if (i == existingSafeMode) continue;
			}
			if (existingMSSafeMode != -1) {
				if (i == existingMSSafeMode) continue;
			}
			noSafeModeEnv[ci++] = ogEnv[i];
		}
		int ret = pspawn_orig(pid, path, file_actions, attrp, argv, noSafeModeEnv);
		free(noSafeModeEnv);
		return ret;
	}

	// Check if we can find an existing "DYLD_INSERT_LIBRARIES" env variable
	int existingLibraryInsert = -1;
	const char *insertVarPrefix = "DYLD_INSERT_LIBRARIES=";
	if (ogEnvCount > 0) {
		for (int i = 0; i < ogEnvCount-1; i++) {
			if(strncmp(ogEnv[i], insertVarPrefix, strlen(insertVarPrefix)) == 0) {
				existingLibraryInsert = i;
				break;
			}
		}
	}

	// If we have found an existing DYLD_INSERT_LIBRARIES variable, check if the systemwide.dylib is already in there
	bool isAlreadyAdded = false;
	if (existingLibraryInsert != -1) {
		char *const existingEnv = ogEnv[existingLibraryInsert];
		char *existingStart = strstr(existingEnv, HOOK_DYLIB_PATH);
		if (existingStart) {
			char before = 0;
			if (existingStart > existingEnv) {
				before = existingStart[-1];
			}
			char after = existingStart[strlen(HOOK_DYLIB_PATH)];
			isAlreadyAdded = (before == '=' || before == ':') && (after == '\0' || after == ':');
		}
	}

	// If it's already in it, we can skip the rest of this hook and just call the original implementation
	if (isAlreadyAdded) {
		//printf("DYLD_INSERT_LIBRARIES with our dylib already exists, skipping...\n");
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);;
	}

	// If not, continue to add it

	// If we did not find an existing variable, new size is one bigger than the old size
	size_t newEnvCount = ogEnvCount + (existingLibraryInsert == -1);
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

	if (existingLibraryInsert == -1) {
		//printf("No DYLD_INSERT_LIBRARIES exists, inserting...\n");
		// No DYLD_INSERT_LIBRARIES exists, insert our own at position newEnvCount-2 as we have allocated extra space for it there
		newEnv[newEnvCount-2] = strdup("DYLD_INSERT_LIBRARIES=" HOOK_DYLIB_PATH);
	}
	else {
		//printf("DYLD_INSERT_LIBRARIES already exists, replacing...\n");
		// DYLD_INSERT_LIBRARIES already exists, append systemwide.dylib to existing one
		char *const existingEnv = ogEnv[existingLibraryInsert];
		//printf("Existing env variable: %s\n", existingEnv);

		free(newEnv[existingLibraryInsert]);
		const char *hookDylibInsert = HOOK_DYLIB_PATH ":";
		size_t hookDylibInsertLen = strlen(hookDylibInsert);
		char *newInsertVar = malloc(strlen(existingEnv) + hookDylibInsertLen + 1);

		size_t insertEnvLen = strlen(insertVarPrefix);
		char *const existingEnvPrefix = &existingEnv[strlen(insertVarPrefix)];
		size_t existingEnvPrefixLen = strlen(existingEnvPrefix);

		strncpy(&newInsertVar[0], insertVarPrefix, insertEnvLen);
		strncpy(&newInsertVar[insertEnvLen], hookDylibInsert, hookDylibInsertLen);
		strncpy(&newInsertVar[insertEnvLen+hookDylibInsertLen], &existingEnv[insertEnvLen], existingEnvPrefixLen+1);

		newEnv[existingLibraryInsert] = newInsertVar;
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
