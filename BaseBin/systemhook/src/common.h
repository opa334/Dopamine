#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>

int64_t jbdFixSetuid(void);
int64_t jbdProcessBinary(const char *filePath);
int64_t jbdProcessLibrary(const char *filePath);
int64_t jbdDebugMe(void);

char *resolvePath(const char *file, const char *searchPath);
int spawn_hook_common(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict],
					   void *pspawn_org);
int posix_spawnattr_setjetsam_replacement(posix_spawnattr_t *attr, short flags, int priority, int memlimit, void *orig);
int posix_spawnattr_setjetsam_ext_replacement(posix_spawnattr_t *attr, short flags, int priority, int memlimit_active, int memlimit_inactive, void *orig);