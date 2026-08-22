#include <spawn.h>
#include <unistd.h>
#include <stdbool.h>
#include <xpc/xpc.h>

extern bool launchdhookFirstLoad;

/* as abort_with_* causes a SIGABRT, we need to use this instead */
void launchd_panic(const char* fmt, ...);

bool dyld_patch_enabled();
bool process_force_dyld_patch(const char* path, const char** argv);
int roothide_config_set_spinlock_fix(bool enabled);

int wait_for_exit(pid_t pid);

bool proc_cantrace(pid_t pid);
int proc_patch_dyld(pid_t pid);
int proc_fix_spinlock(pid_t pid);
int proc_patch_csflags(pid_t pid);
pid_t proc_get_ppid(pid_t pid);
int proc_get_pidversion(pid_t pid);
int proc_paused(pid_t pid, bool* paused);
char* proc_get_path(pid_t pid, char buffer[PATH_MAX]);
char* proc_get_identifier(pid_t pid, char buffer[255]);

uint64_t show_dyld_regions(mach_port_t task, bool more);

bool isBlacklistedApp(const char* identifier);
bool isBlacklistedPath(const char* path);

bool isBlacklistedToken(audit_token_t* token);
bool isBlacklistedPid(pid_t pid);

pid_t* allocBlacklistProcessId();
void commitBlacklistProcessId(pid_t* pidp);

bool isRemovableBundlePath(const char* path);
bool isSubPathOf(const char* parent, const char* child);

bool string_has_prefix(const char *str, const char* prefix);
bool string_has_suffix(const char* str, const char* suffix);

bool hasTrollstoreMarker(const char* path);
bool hasTrollstoreLiteMarker(const char* path);

void ensure_jbroot_symlink(const char* filepath);

int roothide_patch_proc(pid_t pid);

int unrestrict(pid_t pid, int (*callback)(pid_t), bool resume);

int unsandbox(const char* dir, const char* file);

int ensure_dyld_trustcache(const char* path);

int ensure_randomized_cdhash(const char* inputPath, void* cdhashOut);
int ensure_randomized_cdhash_for_slice(const char* inputPath, uint64_t offset, void* cdhashOut);

char* generate_sandbox_extensions(audit_token_t *processToken, bool writable);

int randomizeAndLoadBasebinTrustcache(const char* basebinPath);

bool otherJailbreakActived(bool postexploit);

void hideDeveloperMode();

void exec_set_patch(bool enabled);
int exec_cmd_roothide_spawn(pid_t* pidp, const char* path, const posix_spawn_file_actions_t *fap, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]);

void roothide_handle_xpc_msg(xpc_object_t xmsg);

void loadAppStoredIdentifiers();

bool is_safe_bundle_identifier(const char* identifier);
bool is_sensitive_app_identifier(const char* identifier);
bool is_apple_internal_identifier(const char* identifier);

#define APPLE_INTERNAL_IDENTIFIERS @[\
    @"com.apple.atrun",\
    @"com.apple.kdumpd",\
    @"com.apple.Terminal",\
]

//these apps may be signed with a (fake) certificate
#define SENSITIVE_APP_IDENTIFIERS @[\
    @"com.icraze.gtatracker",\
    @"com.Alfie.TrollInstallerX",\
    @"com.opa334.Dopamine",\
    @"com.opa334.Dopamine.roothide",\
    @"com.opa334.Dopamine-roothide",\
]

