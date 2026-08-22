#include <spawn.h>
#include "common/private.h"

#include <libjailbreak/jbroot.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/roothider/jailbreakd.h>

#define OS_REASON_DYLD          6
#define DYLD_EXIT_REASON_OTHER  9
void abort_with_reason(uint32_t reason_namespace, uint64_t reason_code, const char *reason_string, uint64_t reason_flags);

#define ABORT(...) do { \
	const char* info = NULL; \
	asprintf(&info, __VA_ARGS__); \
	fprintf(stderr, "%s:%d: abort `%s'\n", __FILE_NAME__, __LINE__, info); \
	abort_with_reason(OS_REASON_DYLD, DYLD_EXIT_REASON_OTHER, info, 0); \
} while(0)

#define	ASSERT(e)	(__builtin_expect(!(e), 0) ?\
 ((void)fprintf(stderr, "%s:%d: failed ASSERTion `%s'\n", __FILE_NAME__, __LINE__, #e),\
 abort_with_reason(OS_REASON_DYLD,DYLD_EXIT_REASON_OTHER, #e, 0)), abort() : (void)0)

#include <stdlib.h>
#include <os/log.h>
#include <sys/syslog.h>
#define SYSLOG(...) do {openlog("systemhook",LOG_PID,LOG_AUTH);syslog(LOG_DEBUG, __VA_ARGS__);closelog();} while(0)
#define PROCLOG(progname, ...) do { const char* name=getprogname(); if(name && strcmp(name, progname)==0) {SYSLOG(__VA_ARGS__);} } while(0)
#define PROCASSERT(progname, e) do { const char* name=getprogname(); if(name && strcmp(name, progname)==0) {ASSERT(e);} } while(0)

pid_t __getppid();

bool hasTrollstoreMarker(const char* path);
bool isRemovableBundlePath(const char* path);
bool allowInjectWithSafeMode(const char* path);

void roothide_init();
void roothide_init_with_checkin(const char* rootdir);
void roothide_init_with_executable(const char* executable);

int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int __sysctlbyname_hook(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

int roothide_systemhook___execve_prehook(const char *path, char *const argv[], char *const envp[], void *orig, int (*trust_binary)(const char *path));
int roothide_systemhook___execve_posthook(const char *path, char *const argv[], char *const envp[]);

int roothide_systemhook___posix_spawn_prehook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict], void *orig, int (*trust_binary)(const char *path), int (*set_process_debugged)(uint64_t pid, bool fullyDebugged), double jetsamMultiplier);
int roothide_systemhook___posix_spawn_posthook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);

