#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include <xpc/xpc.h>
#include "private.h"
#include "inline.h"

// RootHide port Build 3: HOOK_DYLIB_PATH is now a RUNTIME variable instead of
// a compile-time constant. The jailbreak publishes systemhook into /usr/lib
// under a randomized name (systemhook-<jbrand>.dylib) through the kernel
// namecache — the old well-known "/usr/lib/systemhook.dylib" path is exactly
// what jailbreak detection probes for and no longer exists.
//
// Definition (exactly one per binary that links this file):
//   - systemhook.dylib:   roothider_main.c (set in roothide_init() from the
//                         dyld image path systemhook was actually loaded from)
//   - launchdhook.dylib:  roothider.m (set in the launchdhook constructor by
//                         scanning <jbroot>/basebin for systemhook-*.dylib)
//
// NULL means "injection path not resolved (yet)": every consumer MUST treat
// NULL as "do not inject" so a spawn degrades to clean instead of inserting
// a garbage DYLD_INSERT_LIBRARIES path that would make dyld kill the child.
extern const char *HOOK_DYLIB_PATH;

typedef enum
{
	kSpawnConfigInject = 1 << 0,
	kSpawnConfigTrust = 1 << 1,
	// RootHide port: roothider_main.c's posthook uses this bit to decide
	// whether the child takes the suspended-spawn + jbdSpawnPatchChild
	// exec-trace path (stock-dyld mode). The local spawn config always
	// sets it for injectable children (upstream roothide parity: every
	// such child gets its jbenv patched before its constructors run).
	kSpawnConfigPatchProcess = 1 << 2,
} kSpawnConfig;

int __posix_spawn(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);
int __execve(const char *path, char *const argv[], char *const envp[]);

bool string_has_prefix(const char *str, const char* prefix);
bool string_has_suffix(const char* str, const char* suffix);

int __posix_spawn_orig(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char * const envp[restrict]);
int __execve_orig(const char *path, char *const argv[], char *const envp[]);

int resolvePath(const char *file, const char *searchPath, int (^attemptHandler)(char *path));
kern_return_t vm_allocate_nearby(vm_map_t target_task, vm_address_t from_area, vm_size_t from_area_size, vm_address_t *address, vm_size_t size, uint64_t limit);

int posix_spawn_hook_shared(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict], void *orig, int (*trust_binary)(const char *path), int (*set_process_debugged)(uint64_t pid, bool fullyDebugged), double jetsamMultiplier);
int execve_hook_shared(const char *path, char *const argv[], char *const envp[], void *orig, int (*trust_binary)(const char *path));

volatile void *get_tpidrr0_el0(void);
kern_return_t litehook_hook_memory_hookd(void *target, void *source, size_t sourceSize);
kern_return_t mach_vm_protect_fixed(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);