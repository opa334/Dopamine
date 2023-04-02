#import "common.h"
#import "unsandbox.h"

#include <mach-o/dyld.h>
#include <dlfcn.h>

void* dlopen_from(const char* path, int mode, void* addressInCaller);
void* dlopen_audited(const char* path, int mode);
bool dlopen_preflight(const char* path);
int posix_spawnattr_setjetsam(posix_spawnattr_t *attr, short flags, int priority, int memlimit);
int posix_spawnattr_setjetsam_ext(posix_spawnattr_t *attr, short flags, int priority, int memlimit_active, int memlimit_inactive);

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
			__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

int posix_spawn_hook(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	return spawn_hook_common(pid, path, file_actions, attrp, argv, envp, (void *)posix_spawn);
}

int posix_spawnp_hook(pid_t *restrict pid, const char *restrict file,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	char *resolvedPath = resolvePath(file, NULL);
	int ret = spawn_hook_common(pid, resolvedPath, file_actions, attrp, argv, envp, (void *)posix_spawn);
	if (resolvedPath) free(resolvedPath);
	return ret;
}


int execve_hook(const char *path, char *const argv[], char *const envp[])
{
	posix_spawnattr_t attr;
	posix_spawnattr_init(&attr);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
	return spawn_hook_common(NULL, path, NULL, &attr, argv, envp, (void *)posix_spawn);
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

	char *resolvedPath = resolvePath(file, NULL);
	int ret = execve_hook(resolvedPath, argv, NULL);
	if (resolvedPath) free(resolvedPath);
	return ret;
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
	char *resolvedPath = resolvePath(file, NULL);
	int ret = execve_hook(resolvedPath, argv, NULL);
	if (resolvedPath) free(resolvedPath);
	return ret;
}

int execvP_hook(const char *file, const char *search_path, char *const argv[])
{
	char *resolvedPath = resolvePath(file, search_path);
	int ret = execve_hook(resolvedPath, argv, NULL);
	if (resolvedPath) free(resolvedPath);
	return ret;
}


void* dlopen_hook(const char* path, int mode)
{
	if (path) {
		jbdswProcessLibrary(path);
	}
	return dlopen(path, mode);
}

void* dlopen_from_hook(const char* path, int mode, void* addressInCaller)
{
	if (path) {
		jbdswProcessLibrary(path);
	}
	return dlopen_from(path, mode, addressInCaller);
}

void* dlopen_audited_hook(const char* path, int mode)
{
	if (path) {
		jbdswProcessLibrary(path);
	}
	return dlopen_audited(path, mode);
}

bool dlopen_preflight_hook(const char* path)
{
	if (path) {
		jbdswProcessLibrary(path);
	}
	return dlopen_preflight(path);
}


int posix_spawnattr_setjetsam_hook(posix_spawnattr_t *attr, short flags, int priority, int memlimit, void *orig)
{
	return posix_spawnattr_setjetsam_replacement(attr, flags, priority, memlimit, &posix_spawnattr_setjetsam);
}

int posix_spawnattr_setjetsam_ext_hook(posix_spawnattr_t *attr, short flags, int priority, int memlimit_active, int memlimit_inactive, void *orig)
{
	return posix_spawnattr_setjetsam_ext_replacement(attr, flags, priority, memlimit_active, memlimit_inactive, &posix_spawnattr_setjetsam_ext);
}

int setuid_hook(uid_t uid)
{
	if (uid == 0) {
		jbdswFixSetuid();
		setuid(uid);
		return setuid(uid);
	}
	return setuid(uid);
}

bool shouldEnableTweaks()
{
	bool tweaksEnabled = true;

	uint32_t bufsize = 0;
	_NSGetExecutablePath(NULL, &bufsize);
	char *executablePath = malloc(bufsize);
	_NSGetExecutablePath(executablePath, &bufsize);
	if (!strcmp(executablePath, "/usr/libexec/xpcproxy")) {
		tweaksEnabled = false;
	}
	free(executablePath);

	return tweaksEnabled;
}

bool gListenForImageLoads = false;
void imageLoadListener(const struct mach_header *header, intptr_t slide)
{
    if (!gListenForImageLoads) return;

    Dl_info dlInfo;
    dladdr(header, &dlInfo);
    
    void *imageHandle = dlopen(dlInfo.dli_fname, RTLD_NOLOAD);

	// If something with the ability to hook C functions is loaded into the process
	// Make the process get CS_DEBUGGED through XPC with jailbreakd
	if (dlsym(imageHandle, "MSHookFunction") || dlsym(imageHandle, "SubHookFunctions") || dlsym(imageHandle, "LHHookFunctions")) {
		jbdswDebugMe();
		gListenForImageLoads = false;
	}
}

__attribute__((constructor)) static void initializer(void)
{
	unsandbox();
	if (shouldEnableTweaks()) {
		_dyld_register_func_for_add_image(imageLoadListener);
		gListenForImageLoads = true;
		if(access("/var/jb/usr/lib/TweakLoader.dylib", F_OK) != -1)
		{
			dlopen_hook("/var/jb/usr/lib/TweakLoader.dylib", RTLD_NOW);
		}
	}
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
DYLD_INTERPOSE(posix_spawnattr_setjetsam_hook, posix_spawnattr_setjetsam)
DYLD_INTERPOSE(posix_spawnattr_setjetsam_ext_hook, posix_spawnattr_setjetsam_ext)
DYLD_INTERPOSE(setuid_hook, setuid)
