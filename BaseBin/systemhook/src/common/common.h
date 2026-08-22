#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include <xpc/xpc.h>
#include "private.h"
#include "inline.h"

// #define HOOK_DYLIB_PATH "/usr/lib/systemhook.dylib"
extern const char* HOOK_DYLIB_PATH;

typedef enum 
{
	kSpawnConfigInject = 1 << 0,
	kSpawnConfigTrust = 1 << 1,
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