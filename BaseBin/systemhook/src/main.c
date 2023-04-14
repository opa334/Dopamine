#include "common.h"
#include "unsandbox.h"

#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <sys/sysctl.h>
#include <sys/stat.h>

void* dlopen_from(const char* path, int mode, void* addressInCaller);
void* dlopen_audited(const char* path, int mode);
bool dlopen_preflight(const char* path);
int posix_spawnattr_setjetsam(posix_spawnattr_t *attr, short flags, int priority, int memlimit);
int posix_spawnattr_setjetsam_ext(posix_spawnattr_t *attr, short flags, int priority, int memlimit_active, int memlimit_inactive);

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
			__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

static char *gExecutablePath = NULL;
static void loadExecutablePath(void)
{
	uint32_t bufsize = 0;
	_NSGetExecutablePath(NULL, &bufsize);
	char *executablePath = malloc(bufsize);
	_NSGetExecutablePath(executablePath, &bufsize);
	if (executablePath) {
		gExecutablePath = realpath(executablePath, NULL);
		free(executablePath);
	}
}
static void freeExecutablePath(void)
{
	if (gExecutablePath) {
		free(gExecutablePath);
		gExecutablePath = NULL;
	}
}

void killall(const char *executablePathToKill, bool softly)
{
	static int maxArgumentSize = 0;
	if (maxArgumentSize == 0) {
		size_t size = sizeof(maxArgumentSize);
		if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
			perror("sysctl argument size");
			maxArgumentSize = 4096; // Default
		}
	}
	int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
	struct kinfo_proc *info;
	size_t length;
	int count;
	
	if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
		return;
	if (!(info = malloc(length)))
		return;
	if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
		free(info);
		return;
	}
	count = length / sizeof(struct kinfo_proc);
	for (int i = 0; i < count; i++) {
		pid_t pid = info[i].kp_proc.p_pid;
		if (pid == 0) {
			continue;
		}
		size_t size = maxArgumentSize;
		char* buffer = (char *)malloc(length);
		if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
			char *executablePath = buffer + sizeof(int);
			if (strcmp(executablePath, executablePathToKill) == 0) {
				if(softly)
				{
					kill(pid, SIGTERM);
				}
				else
				{
					kill(pid, SIGKILL);
				}
			}
		}
		free(buffer);
	}
	free(info);
}

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

bool shouldEnableTweaks(void)
{
	bool tweaksEnabled = true;

	if (gExecutablePath) {
		if (!strcmp(gExecutablePath, "/usr/libexec/xpcproxy") ||
			!strcmp(gExecutablePath, "/sbin/mount") ||
			!strcmp(gExecutablePath, "/System/Library/PrivateFrameworks/MobileSoftwareUpdate.framework/XPCServices/com.apple.MobileSoftwareUpdate.CleanupPreparePathService.xpc/com.apple.MobileSoftwareUpdate.CleanupPreparePathService")) {
			tweaksEnabled = false;
		}
		else {
			/*
			Disable Tweaks for anything inside /var/jb except for stuff in /var/jb/Applications
			Explanation: Hooking C functions inside a process breaks fork() because the child process will not have wx_allowed
						 so any modified TEXT mapping will be mapped in as r--, causing the process to crash when anything in it
						 gets called, this is probably fixable in some way, but for now this solution has to suffice
			*/
			const char *pp = "/private/preboot";
			if (strncmp(gExecutablePath, pp, strlen(pp)) == 0) {
				char *varJB = realpath("/var/jb", NULL);
				if (varJB) {
					if (strncmp(gExecutablePath, varJB, strlen(varJB)) == 0) {
						char *varJBApps = realpath("/var/jb/Applications", NULL);
						if (varJBApps) {
							if (strncmp(gExecutablePath, varJBApps, strlen(varJBApps)) != 0) {
								tweaksEnabled = false;
							}
							free(varJBApps);
						}
						else {
							tweaksEnabled = false;
						}
					}
					free(varJB);
				}
			}
		}
	}

	return tweaksEnabled;
}

void applyKbdFix(void)
{
	// For whatever reason after SpringBoard has restarted, AutoFill and other stuff stops working
	// The fix is to always also restart the kbd daemon alongside SpringBoard
	// Seems to be something sandbox related where kbd doesn't have the right extensions until restarted
	killall("/System/Library/TextInput/kbd", false);
}

__attribute__((constructor)) static void initializer(void)
{
	unsandbox();
	loadExecutablePath();

	struct stat sb;
	if(stat(gExecutablePath, &sb) == 0) {
		if (S_ISREG(sb.st_mode) && (sb.st_mode & S_ISUID)) {
			jbdswFixSetuid();
			setuid(sb.st_uid);
		}
	}

	if (gExecutablePath) {
		if (strcmp(gExecutablePath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0) {
			applyKbdFix();
		}
	}

	if (shouldEnableTweaks()) {
		int64_t debugErr = jbdswDebugMe();
		if (debugErr == 0) {
			if(access("/var/jb/usr/lib/TweakLoader.dylib", F_OK) == 0)
			{
				dlopen_hook("/var/jb/usr/lib/TweakLoader.dylib", RTLD_NOW);
			}
		}
	}
	freeExecutablePath();
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
