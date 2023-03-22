#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include <xpc/xpc.h>

#include <dlfcn.h>
void* dlopen_from(const char* path, int mode, void* addressInCaller);
void* dlopen_audited(const char* path, int mode);
bool dlopen_preflight(const char* path);

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
			__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };
#define HOOK_DYLIB_PATH "/var/jb/basebin/systemhook.dylib"
#define JBD_MSG_PROCESS_BINARY 22
#define JBD_MSG_DEBUG_ME 24

extern char **environ;
kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

mach_port_t jbdSystemWideMachPort(void)
{
	mach_port_t outPort = -1;

	if (getpid() == 1) {
		host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 16, &outPort);
	}
	else {
		bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd.systemwide", &outPort);
	}

	return outPort;
}

xpc_object_t sendJBDMessageSystemWide(xpc_object_t message)
{
	mach_port_t jbdMachPort = jbdSystemWideMachPort();
	xpc_object_t pipe = xpc_pipe_create_from_port(jbdMachPort, 0);
	xpc_object_t reply = nil;
	int err = xpc_pipe_routine(pipe, message, &reply);
	if (err != 0) {
		return nil;
	}
	return reply;
}

int64_t jbdProcessBinary(const char *filePath)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROCESS_BINARY);
	xpc_dictionary_set_string(message, "filePath", filePath);

	xpc_object_t reply = sendJBDMessageSystemWide(message);
	return xpc_dictionary_get_int64(reply, "result");
}

int64_t jbdDebugMe(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DEBUG_ME);

	xpc_object_t reply = sendJBDMessageSystemWide(message);
	return xpc_dictionary_get_int64(reply, "result");
}

char *resolve_path(const char *file, const char *searchPath)
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

int spawn_hook_common(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	if (!path) {
		return posix_spawn(pid, path, file_actions, attrp, argv, envp);
	}

	// Jailbreakd: Trustcache binary and give it entitlements
	jbdProcessBinary(path);

	// Insert hook dylib via environment
	char **ogEnv = NULL;
	if (envp == NULL) {
		// If envp is NULL, environ is inherited, so we want to use that instead
		ogEnv = environ;
	}
	else {
		ogEnv = (char **)envp;
	}
	size_t envpCount = 0;
	if (ogEnv) {
		while (ogEnv[envpCount] != NULL) {
			envpCount++;
		}
	}
	char **envpCopy = malloc((envpCount + 2) * sizeof(char *));
	int existingLibraryInsert = -1;
	const char *insertEnv = "DYLD_INSERT_LIBRARIES=";
	for (int i = 0; i < envpCount; i++) {
		if(strncmp(ogEnv[i], insertEnv, strlen(insertEnv)) == 0) {
			existingLibraryInsert = i;
		}
		envpCopy[i] = strdup(ogEnv[i]);
	}
	if (existingLibraryInsert != -1) {
		char *const existingEnv = ogEnv[existingLibraryInsert];

		// Avoid adding the dylib twice
		bool isAlreadyAdded = false;
		char *existingStart = strstr(existingEnv, HOOK_DYLIB_PATH);
		if (existingStart) {
			char before = 0;
			if (existingStart > existingEnv) {
				before = existingStart[-1];
			}
			char after = existingStart[strlen(HOOK_DYLIB_PATH)];
			isAlreadyAdded = (before == '=' || before == ':') && (after == '\0' || after == ':');
		}

		if (!isAlreadyAdded) {
			free(envpCopy[existingLibraryInsert]);
			const char *hookDylibInsert = HOOK_DYLIB_PATH ":";
			size_t hookDylibInsertLen = strlen(hookDylibInsert);
			char *newEnv = malloc(strlen(existingEnv) + hookDylibInsertLen + 1);

			size_t insertEnvLen = strlen(insertEnv);
			char *const existingEnvPrefix = &existingEnv[strlen(insertEnv)];
			size_t existingEnvPrefixLen = strlen(existingEnvPrefix);

			strncpy(&newEnv[0], insertEnv, insertEnvLen);
			strncpy(&newEnv[insertEnvLen], hookDylibInsert, hookDylibInsertLen);
			strncpy(&newEnv[insertEnvLen+hookDylibInsertLen], &existingEnv[insertEnvLen], existingEnvPrefixLen+1);

			envpCopy[existingLibraryInsert] = newEnv;
			envpCopy[envpCount] = NULL;
		}
	}
	else {
		envpCopy[envpCount] = strdup("DYLD_INSERT_LIBRARIES=" HOOK_DYLIB_PATH);
		envpCopy[envpCount + 1] = NULL;
	}

	int orgReturn = posix_spawn(pid, path, file_actions, attrp, argv, envpCopy);

	// Free new environment
	for (int i = 0; i < envpCount + (int)(existingLibraryInsert != -1); i++) {
		free(envpCopy[i]);
	}
	free(envpCopy);

	return orgReturn;
}

int posix_spawn_hook(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	return spawn_hook_common(pid, path, file_actions, attrp, argv, envp);
}

int posix_spawnp_hook(pid_t *restrict pid, const char *restrict file,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	return spawn_hook_common(pid, resolve_path(file, NULL), file_actions, attrp, argv, envp);
}


int execve_hook(const char *path, char *const argv[], char *const envp[])
{
	posix_spawnattr_t attr;
	posix_spawnattr_init(&attr);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
	return spawn_hook_common(NULL, path, NULL, &attr, argv, envp);
}



int execle_hook(const char *path, const char *arg0, ... /*, (char *)0, char *const envp[] */)
{
	va_list args;
    va_start(args, arg0);

    // Get argument count
    va_list args_copy;
    va_copy(args_copy, args);
    int arg_count = 0;
    for (char *arg = va_arg(args_copy, char *); arg != NULL; arg = va_arg(args_copy, char *)) {
        arg_count++;
    }
    va_end(args_copy);

	char *argv[arg_count+1];
    for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i] = arg;
    }
	argv[arg_count] = NULL;

	char *nullChar = va_arg(args, char*);
	if (nullChar != NULL)
	{
		printf("FAILURE\n");
	}

	char **envp = va_arg(args, char**);
	return execve_hook(path, argv, envp);
}

int execlp_hook(const char *file, const char *arg0, ... /*, (char *)0 */)
{
	va_list args;
    va_start(args, arg0);

    // Get argument count
    va_list args_copy;
    va_copy(args_copy, args);
    int arg_count = 0;
    for (char *arg = va_arg(args_copy, char*); arg != NULL; arg = va_arg(args_copy, char*)) {
        arg_count++;
    }
    va_end(args_copy);

	char *argv[arg_count+1];
    for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i] = arg;
    }
	argv[arg_count] = NULL;

	return execve_hook(resolve_path(file, NULL), argv, NULL);
}

int execl_hook(const char *path, const char *arg0, ... /*, (char *)0 */)
{
	va_list args;
    va_start(args, arg0);

    // Get argument count
    va_list args_copy;
    va_copy(args_copy, args);
    int arg_count = 0;
    for (char *arg = va_arg(args_copy, char*); arg != NULL; arg = va_arg(args_copy, char*)) {
        arg_count++;
    }
    va_end(args_copy);

	char *argv[arg_count+1];
    for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i] = arg;
    }
	argv[arg_count] = NULL;

	return execve_hook(path, argv, NULL);
}


int execv_hook(const char *path, char *const argv[])
{
	return execve_hook(path, argv, NULL);
}


int execvp_hook(const char *file, char *const argv[])
{
	return execve_hook(resolve_path(file, NULL), argv, NULL);
}

int execvP_hook(const char *file, const char *search_path, char *const argv[])
{
	return execve_hook(resolve_path(file, search_path), argv, NULL);
}


void* dlopen_hook(const char* path, int mode)
{
	if (path) {
		jbdProcessBinary(path);
	}
	return dlopen(path, mode);
}

void* dlopen_from_hook(const char* path, int mode, void* addressInCaller)
{
	if (path) {
		jbdProcessBinary(path);
	}
	return dlopen_from(path, mode, addressInCaller);
}

void* dlopen_audited_hook(const char* path, int mode)
{
	if (path) {
		jbdProcessBinary(path);
	}
	return dlopen_audited(path, mode);
}

bool dlopen_preflight_hook(const char* path)
{
	if (path) {
		jbdProcessBinary(path);
	}
	return dlopen_preflight(path);
}

__attribute__((constructor)) static void initializer(void)
{
	printf("systemhook init (%d)\n", getpid());
	jbdDebugMe();
}

DYLD_INTERPOSE(posix_spawn_hook, posix_spawn)
DYLD_INTERPOSE(posix_spawnp_hook, posix_spawnp)
DYLD_INTERPOSE(execve_hook, execve)
DYLD_INTERPOSE(execle_hook, execle)
DYLD_INTERPOSE(execlp_hook, execlp)
DYLD_INTERPOSE(execv_hook, execv)
DYLD_INTERPOSE(execvp_hook, execvp)
DYLD_INTERPOSE(execvP_hook, execvP)
DYLD_INTERPOSE(dlopen_hook, dlopen)
DYLD_INTERPOSE(dlopen_from_hook, dlopen_from)
DYLD_INTERPOSE(dlopen_audited_hook, dlopen_audited)
DYLD_INTERPOSE(dlopen_preflight_hook, dlopen_preflight)
