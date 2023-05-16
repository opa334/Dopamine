#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>

bool stringStartsWith(const char *str, const char* prefix);
bool stringEndsWith(const char* str, const char* suffix);

int64_t jbdswFixSetuid(void);
int64_t jbdswProcessBinary(const char *filePath);
int64_t jbdswProcessLibrary(const char *filePath);
int64_t jbdswDebugMe(void);
int64_t jbdswInterceptUserspacePanic(const char *messageString);

int resolvePath(const char *file, const char *searchPath, int (^attemptHandler)(char *path));
int spawn_hook_common(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict],
					   void *pspawn_org);