#import "common.h"
#import "unrestrict.h"

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
	return spawn_hook_common(pid, resolvePath(file, NULL), file_actions, attrp, argv, envp, (void *)posix_spawn);
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

	return execve_hook(resolvePath(file, NULL), argv, NULL);
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
	return execve_hook(resolvePath(file, NULL), argv, NULL);
}

int execvP_hook(const char *file, const char *search_path, char *const argv[])
{
	return execve_hook(resolvePath(file, search_path), argv, NULL);
}


void* dlopen_hook(const char* path, int mode)
{
	if (path) {
		jbdProcessLibrary(path);
	}
	return dlopen(path, mode);
}

void* dlopen_from_hook(const char* path, int mode, void* addressInCaller)
{
	if (path) {
		jbdProcessLibrary(path);
	}
	return dlopen_from(path, mode, addressInCaller);
}

void* dlopen_audited_hook(const char* path, int mode)
{
	if (path) {
		jbdProcessLibrary(path);
	}
	return dlopen_audited(path, mode);
}

bool dlopen_preflight_hook(const char* path)
{
	if (path) {
		jbdProcessLibrary(path);
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

__attribute__((constructor)) static void initializer(void)
{
	//printf("systemhook init (%d)\n", getpid());
	unrestrict();
	if(access("/var/jb/usr/lib/TweakLoader.dylib", F_OK) != -1)
	{
		dlopen_hook("/var/jb/usr/lib/TweakLoader.dylib", RTLD_NOW);
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
