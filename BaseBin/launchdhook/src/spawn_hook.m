#import <spawn.h>
#import "../systemhook/src/common.h"
#import "boomerang.h"
#import "substrate.h"
#import <mach-o/dyld.h>
#import <Foundation/Foundation.h>

void *posix_spawn_orig;
int posix_spawn_hook(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	if (path) {
		const char *firstArg = "<none>";
		if (argv[0]) {
			if (argv[1]) {
				firstArg = argv[1];
			}
		}

		char executablePath[1024];
		uint32_t bufsize = sizeof(executablePath);
		_NSGetExecutablePath(&executablePath[0], &bufsize);
		if (!strcmp(path, executablePath)) {
			// This spawn will perform a userspace reboot...
			// Instead of the ordinary hook, we want to reinsert this dylib
			// This has already been done in envp so we only need to call the regular posix_spawn

			// But before, we want to pass the primitives to boomerang
			boomerang_userspaceRebootIncoming();

			//FILE *f = fopen("/var/mobile/launch_log.txt", "a");
			//fprintf(f, "==== USERSPACE REBOOT ====\n");
			//fclose(f);

			// Say goodbye to this process
			int (*orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]) = posix_spawn_orig;
			return orig(pid, path, file_actions, attrp, argv, envp);
		}
	}

	/*if (path) {
		const char *firstArg = "<none>";
		if (argv[0]) {
			if (argv[1]) {
				firstArg = argv[1];
			}
		}
		FILE *f = fopen("/var/mobile/launch_log.txt", "a");
		fprintf(f, "posix_spawn %s %s\n", path, firstArg);
		fclose(f);

		if (!strcmp(path, "/usr/libexec/xpcproxy")) {
			const char *tmpBlacklist[] = {
				"com.apple.logd"
			};
			size_t blacklistCount = sizeof(tmpBlacklist) / sizeof(tmpBlacklist[0]);
			for (size_t i = 0; i < blacklistCount; i++)
			{
				if (!strcmp(tmpBlacklist[i], firstArg)) {
					FILE *f = fopen("/var/mobile/launch_log.txt", "a");
					fprintf(f, "blocked injection %s\n", firstArg);
					fclose(f);
					int (*orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]) = posix_spawn_orig;
					return orig(pid, path, file_actions, attrp, argv, envp);
				}
			}
		}
	}*/

	return spawn_hook_common(pid, path, file_actions, attrp, argv, envp, posix_spawn_orig);
}

void initSpawnHooks(void)
{
	MSHookFunction(&posix_spawn, (void *)posix_spawn_hook, &posix_spawn_orig);
}