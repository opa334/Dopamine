#include "common/common.h"

#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <stdio.h>
#include <limits.h>
#include <paths.h>
#include <util.h>
#include <ptrauth.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/codesign.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/hookd.h>
// RootHide integration for selective injection and path randomization
#include <libjailbreak/libjailbreak.h>
#include "../dyldhook/src/dyld_jbinfo.h"
#include "common/hookd_external.h"
#include <choma/CSBlob.h>
#include "litehook.h"
// RootHide port (Relaxin upstream): per-process hiding subsystem
// (roothide_init / roothide_init_with_checkin / roothide_init_with_executable).
#include "roothider.h"
#include "sandbox.h"
#include "common/private.h"
#include "common/inline.h"

bool gFullyDebugged = false;
static void *gLibSandboxHandle;
char *JB_BootUUID = NULL;
char *JB_RootPath = NULL;
char *get_jbroot(void) { return JB_RootPath; }

static char gExecutablePath[PATH_MAX];
static int load_executable_path(void)
{
        char executablePath[PATH_MAX];
        uint32_t bufsize = PATH_MAX;
        if (_NSGetExecutablePath(executablePath, &bufsize) == 0) {
                if (realpath(executablePath, gExecutablePath) != NULL) return 0;
        }
        return -1;
}

static char *JB_SandboxExtensions = NULL;

void consume_tokenized_sandbox_extensions(char *sandboxExtensions)
{
        if (sandboxExtensions[0] == '\0') return;

        char *it = sandboxExtensions;
        char *last = sandboxExtensions;
        while (*(++it) != '\0') {
                if (*it == '|') {
                        *it = '\0';
                        sandbox_extension_consume(last);
                        last = &it[1];
                        *it = '|';
                }
        }
        sandbox_extension_consume(last);
}

void *(*sandbox_apply_orig)(void *) = NULL;
void *sandbox_apply_hook(void *a1)
{
        void *r = sandbox_apply_orig(a1);
        consume_tokenized_sandbox_extensions(JB_SandboxExtensions);
        return r;
}

int dyld_hook_routine(void **dyld, int idx, void *hook, void **orig, uint16_t pacSalt)
{
        if (!dyld) return -1;

        uint64_t dyldPacDiversifier = ((uint64_t)dyld & ~(0xFFFFull << 48)) | (0x63FAull << 48);
        void **dyldFuncPtrs = ptrauth_auth_data(*dyld, ptrauth_key_process_independent_data, dyldPacDiversifier);
        if (!dyldFuncPtrs) return -1;

        if (vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ | VM_PROT_WRITE) == 0) {
                uint64_t location = (uint64_t)&dyldFuncPtrs[idx];
                uint64_t pacDiversifier = (location & ~(0xFFFFull << 48)) | ((uint64_t)pacSalt << 48);

                *orig = ptrauth_auth_and_resign(dyldFuncPtrs[idx], ptrauth_key_process_independent_code, pacDiversifier, ptrauth_key_function_pointer, 0);
                dyldFuncPtrs[idx] = ptrauth_auth_and_resign(hook, ptrauth_key_function_pointer, 0, ptrauth_key_process_independent_code, pacDiversifier);
                vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ);
                return 0;
        }

        return -1;
}

// dlsym calls use __builtin_return_address(0) to determine what library called it
// Since we hook them, if we just call the original function on our own, the return address will always point to systemhook
// Therefore we must ensure the call to the original function is a tail call, which ensures that the stack and lr are restored and the compiler turns the call into a direct branch
// This is done via __attribute__((musttail)), this way __builtin_return_address(0) will point to the original calling library instead of systemhook

void *(*dyld_dlsym_orig)(void *dyld, void *handle, const char *name);
void *dyld_dlsym_hook(void *dyld, void *handle, const char *name)
{
        if (handle == gLibSandboxHandle && !strcmp(name, "sandbox_apply")) {
                // We abuse the fact that libsystem_sandbox will call dlsym to get the sandbox_apply pointer here
                // Because we can just return a different pointer, we avoid doing instruction replacements
                return sandbox_apply_hook;
        }
        __attribute__((musttail)) return dyld_dlsym_orig(dyld, handle, name);
}

int ptrace_hook(int request, pid_t pid, caddr_t addr, int data)
{
        int r = ptrace_inline(request, pid, addr, data);

        // ptrace works on any process when the caller is unsandboxed,
        // but when the victim process does not have the get-task-allow entitlement,
        // it will fail to set the debug flags, therefore we patch ptrace to manually apply them
        // processes that have tweak injection enabled will have their debug flags already set
        // this is only relevant for ones that don't, e.g. if you disable tweak injection on an app via choicy
        // but still want to be able to attach a debugger to them
        if (r == 0 && (request == PT_ATTACHEXC || request == PT_ATTACH)) {
                jbclient_platform_set_process_debugged(pid, true);
                jbclient_platform_set_process_debugged(getpid(), true);
        }

        return r;
}

#ifndef __arm64e__

// The NECP subsystem is the only thing in the kernel that ever checks CS_VALID on userspace processes (Only on iOS >=16)
// In order to not break system functionality, we need to readd CS_VALID before any of these are invoked

int necp_match_policy_hook(uint8_t *parameters, size_t parameters_size, void *returned_result)
{
        jbclient_cs_revalidate();
        return syscall(SYS_necp_match_policy, parameters, parameters_size, returned_result);
}

int necp_open_hook(int flags)
{
        jbclient_cs_revalidate();
        return syscall(SYS_necp_open, flags);
}

int necp_client_action_hook(int necp_fd, uint32_t action, uuid_t client_id, size_t client_id_len, uint8_t *buffer, size_t buffer_size)
{
        jbclient_cs_revalidate();
        return syscall(SYS_necp_client_action, necp_fd, action, client_id, client_id_len, buffer, buffer_size);
}

int necp_session_open_hook(int flags)
{
        jbclient_cs_revalidate();
        return syscall(SYS_necp_session_open, flags);
}

int necp_session_action_hook(int necp_fd, uint32_t action, uint8_t *in_buffer, size_t in_buffer_length, uint8_t *out_buffer, size_t out_buffer_length)
{
        jbclient_cs_revalidate();
        return syscall(SYS_necp_session_action, necp_fd, action, in_buffer, in_buffer_length, out_buffer, out_buffer_length);
}

// For the userland, there are multiple processes that will check CS_VALID for one reason or another
// As we inject system wide (or at least almost system wide), we can just patch the source of the info though - csops itself
// Additionally we also remove CS_DEBUGGED while we're at it, as on arm64e this also is not set and everything is fine
// That way we have unified behaviour between both arm64 and arm64e

int csops_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize)
{
        int rv = syscall(SYS_csops, pid, ops, useraddr, usersize);
        if (rv != 0) return rv;
        if (ops == CS_OPS_STATUS) {
                if (useraddr && usersize == sizeof(uint32_t)) {
                        uint32_t* csflag = (uint32_t *)useraddr;
                        *csflag |= CS_VALID;
                        *csflag &= ~CS_DEBUGGED;
                        if (pid == getpid() && gFullyDebugged) {
                                *csflag |= CS_DEBUGGED;
                        }
                }
        }
        return rv;
}

int csops_audittoken_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, audit_token_t *token)
{
        int rv = syscall(SYS_csops_audittoken, pid, ops, useraddr, usersize, token);
        if (rv != 0) return rv;
        if (ops == CS_OPS_STATUS) {
                if (useraddr && usersize == sizeof(uint32_t)) {
                        uint32_t* csflag = (uint32_t *)useraddr;
                        *csflag |= CS_VALID;
                        *csflag &= ~CS_DEBUGGED;
                        if (pid == getpid() && gFullyDebugged) {
                                *csflag |= CS_DEBUGGED;
                        }
                }
        }
        return rv;
}

#endif

bool should_enable_tweaks(void)
{
        // ========== ROOTHIDE CLEAN MODE CHECK ==========
        // Check if this process is in RootHide clean mode
        // If so, disable ALL tweak injection and jailbreak traces
        if (getenv(ROOTHIDE_CLEAN_MODE_ENV)) {
                const char *cleanMode = getenv(ROOTHIDE_CLEAN_MODE_ENV);
                if (cleanMode && strcmp(cleanMode, "1") == 0) {
                        return false; // Blacklisted app - no tweaks
                }
        }

        // Also check ROOTHIDE_MODE for legacy support
        if (getenv(ROOTHIDE_MODE_ENV)) {
                const char *roothideMode = getenv(ROOTHIDE_MODE_ENV);
                if (roothideMode && strcmp(roothideMode, "hide") == 0) {
                        return false;
                }
        }
        // ========== END ROOTHIDE CHECK ==========

        // FIX BLACKLIST INPUT BUG (defense in depth — matches the launchd-side
        // fix in spawn_hook.c):
        // Env var check ở trên CHỈ hiệu quả khi spawn_hook của launchd đã set
        // env var đúng trước khi spawn child. Tuy nhiên có nhiều path mà env
        // var không được truyền đúng:
        //   1. App launch từ SpringBoard (SpringBoard execve trực tiếp, không qua launchd)
        //   2. App launch từ BackBoard / FrontBoard
        //   3. xpcproxy spawn daemon (xpcproxy nhận env từ launchd, nhưng launchd
        //      không biết app nào sắp chạy)
        //   4. App được mở từ Notification / Widget / Quick Action
        //
        // Để đảm bảo app banking/detection luôn được skip injection, query động
        // blacklist từ launchd. Nhược điểm: +1 XPC round-trip mỗi launch, nhưng
        // chi phí ~0.5ms, không đáng kể so với thời gian load dylib.
        //
        // FIX: The old code extracted the app bundle DIRECTORY NAME (e.g. "iBank")
        // and passed it to jbclient_blacklist_check_bundle(). The server side
        // (isBlacklistedApp, blacklist.m:76) looks up by CFBundleIdentifier
        // (e.g. "com.vietinbank.iBank") in RootHideConfig.plist appconfig — so
        // the lookup NEVER matched and tweaks were still loaded into blacklisted
        // apps. Fix: pass the FULL executable path via jbclient_blacklist_check_path();
        // the server resolves path -> Info.plist -> CFBundleIdentifier -> appconfig
        // (isBlacklistedPath, blacklist.m:99), exactly like the official
        // Dopamine2-roothide does.
        //
        // Fail-safe: nếu không kết nối được tới launchd (early boot, trong
        // xpcproxy đầu tiên), return true (cho phép tweaks) để tránh bootloop.
        // Sau khi launchdhook install xong, lần query sau sẽ thành công.
        // Nếu là system binary (trong /usr/, /bin/, /sbin/) → skip query.
        {
                if (gExecutablePath[0] != '\0' &&
                    strstr(gExecutablePath, "/var/containers/Bundle/Application/") != NULL) {
                        // Đây là app user-installed → query blacklist động theo FULL PATH
                        // (server tự resolve bundle ID từ Info.plist của .app bundle)
                        if (jbclient_blacklist_check_path(gExecutablePath)) {
                                // FIX (RootHide leak): REMOVED setenv(ROOTHIDE_CLEAN_MODE_ENV, "1", 1).
                                //
                                // ROOTHIDE CLEAN MODE ENV VAR LEAK — ROOT CAUSE OF BANKING APP
                                // DETECTION (despite RootHide app blacklist being enabled):
                                //
                                // The old code set this process-wide env var BEFORE returning false
                                // from should_enable_tweaks(). Banking apps calling
                                // getenv("ROOTHIDE_CLEAN_MODE") during their initialization would
                                // see "1" and immediately detect the jailbreak — even though the
                                // blacklist was correctly configured and tweaks were properly
                                // disabled for this process.
                                //
                                // The env var is unnecessary here because:
                                //   1. spawn_hook.c already propagates clean-mode to children via
                                //      the ROOTHIDE_CLEAN_MODE_ENV check (spawn_hook.c:248-253).
                                //   2. The child inherits env from launchd (which may already
                                //      have it set), not from this process's setenv().
                                //   3. Other dylibs loaded before this check were already loaded
                                //      by dyld during process startup (before any constructor),
                                //      so they don't need an env-var signal.
                                //
                                // Removing this setenv() eliminates the most common banking app
                                // jailbreak detection vector while preserving all functional
                                // behavior: tweaks are still disabled (return false) and the
                                // blacklist is still checked dynamically.
                                return false;
                        }
                }
        }

        if (access(JBROOT_PATH("/basebin/.safe_mode"), F_OK) == 0) {
                return false;
        }

        char *tweaksDisabledEnv = getenv("DISABLE_TWEAKS");
        if (tweaksDisabledEnv) {
                if (!strcmp(tweaksDisabledEnv, "1")) {
                        return false;
                }
        }

        if (jbclient_dopamine_is_jailbroken(NULL)) {
                // Probe whether we are the Dopamine app
                // Only the Dopamine app is allowed to contact this domain
                // In this case we want to disable tweak injection to prevent jailbreak detections etc messing with the app functionality
                return false;
        }

        const char *tweaksDisabledPathSuffixes[] = {
                // System binaries
                "/usr/libexec/xpcproxy",
        };
        for (size_t i = 0; i < sizeof(tweaksDisabledPathSuffixes) / sizeof(const char*); i++) {
                if (string_has_suffix(gExecutablePath, tweaksDisabledPathSuffixes[i])) return false;
        }

        if (__builtin_available(iOS 16.0, *)) {
                // These seem to be problematic on iOS 16+ (dyld gets stuck in a weird way when opening TweakLoader)
                const char *iOS16TweaksDisabledPaths[] = {
                        "/usr/libexec/logd",
                        "/usr/sbin/notifyd",
                        "/usr/libexec/usermanagerd",
                };
                for (size_t i = 0; i < sizeof(iOS16TweaksDisabledPaths) / sizeof(const char*); i++) {
                        if (!strcmp(gExecutablePath, iOS16TweaksDisabledPaths[i])) return false;
                }
        }

        return true;
}

int __posix_spawn_hook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char * const envp[restrict])
{
        // RootHide port (Dopamine2-roothide main.c parity): dispatch through
        // the roothide pre/post hook pair instead of plain
        // posix_spawn_hook_shared. The posthook performs, per spawned child:
        //   - jbclient_trust_executable_recurse(path, preferredArchs):
        //     recursive trust of the executable AND its dependent dylibs
        //     (bash -> libvrootapi -> libvroot -> libroothide -> roothideinit
        //     for every RootHide bootstrap binary) with roothide
        //     randomized-cdhash normalization. Flat trust of only the main
        //     binary left the libvroot chain untrusted, so AMFI killed the
        //     process during dyld load and RootHidePatcher's patch.sh never
        //     ran (silent "select deb -> convert -> nothing" symptom).
        //   - DYLD_IN_CACHE=0 handling + trust_insert_libraries
        //   - jbdSpawnExecStart/jbdSpawnPatchChild exec-trace so the child
        //     gets its jbenv patched before main.
        return roothide_systemhook___posix_spawn_prehook(pid, path, desc, argv, envp, (void *)roothide_systemhook___posix_spawn_posthook, jbclient_trust_file_by_path, jbclient_platform_set_process_debugged, jbclient_jbsettings_get_double("jetsamMultiplier"));
}

int __posix_spawn_hook_with_filter(pid_t *restrict pid, const char *restrict path, char *const argv[restrict], char * const envp[restrict], struct _posix_spawn_args_desc *desc, int *ret)
{
        // RootHide port: same roothide dispatch as __posix_spawn_hook above.
        *ret = roothide_systemhook___posix_spawn_prehook(pid, path, desc, argv, envp, (void *)roothide_systemhook___posix_spawn_posthook, jbclient_trust_file_by_path, jbclient_platform_set_process_debugged, jbclient_jbsettings_get_double("jetsamMultiplier"));
        return 1;
}

int __execve_hook(const char *path, char *const argv[], char *const envp[])
{
        // RootHide port: roothide pre/post pair (prehook first retries the
        // exec via POSIX_SPAWN_SETEXEC posix_spawn, falling back to
        // execve_hook_shared only for fork-restricted callers; the posthook
        // exec-traces the child so its jbenv gets patched).
        return roothide_systemhook___execve_prehook(path, argv, envp, (void *)roothide_systemhook___execve_posthook, jbclient_trust_file_by_path);
}

xpc_object_t copy_entitlements_xpc(void)
{
        pid_t pid = getpid();
        CS_GenericBlob hdr = {0};

        // Get size (will fail with ERANGE)
        if (csops(pid, CS_OPS_ENTITLEMENTS_BLOB, &hdr, sizeof(hdr)) != 0) {
                if (errno != ERANGE) {
                        return NULL;
                }
        }

        if (hdr.length <= sizeof(hdr)) {
                // No entitlements
                return NULL;
        }

        // Get blob
        void *buf = malloc(hdr.length);
        if (!buf)
                return NULL;

        if (csops(pid, CS_OPS_ENTITLEMENTS_BLOB, buf, hdr.length) != 0) {
                free(buf);
                return NULL;
        }

        // Skip cs_blob header
        const void *plist = (const uint8_t *)buf + sizeof(CS_GenericBlob);
        size_t plist_size = hdr.length - sizeof(CS_GenericBlob);

        // Convert to XPC dictionary
        xpc_object_t obj = xpc_create_from_plist(plist, plist_size);

        free(buf);

        if (!obj || xpc_get_type(obj) != XPC_TYPE_DICTIONARY) {
                if (obj) xpc_release(obj);
                return NULL;
        }

        return obj;
}

bool process_requires_hookd(void)
{
        xpc_object_t entitlementsXdict = copy_entitlements_xpc();
        if (!entitlementsXdict) return true;

        bool requiresHookd = xpc_dictionary_get_bool(entitlementsXdict, "com.apple.private.cs.debugger") != true;
        xpc_release(entitlementsXdict);
        return requiresHookd;
}

const struct mach_header_64 *get_dyld_mach_header(void)
{
        static const struct mach_header_64 *dyldMachHeader = NULL;
        static dispatch_once_t onceToken;
        dispatch_once (&onceToken, ^{
                task_dyld_info_data_t dyldInfo;
                uint32_t count = TASK_DYLD_INFO_COUNT;
                kern_return_t kr = task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
                if (kr == KERN_SUCCESS) {
                        struct dyld_all_image_infos *infos = (struct dyld_all_image_infos *)dyldInfo.all_image_info_addr;
                        dyldMachHeader = (const struct mach_header_64 *)infos->dyldImageLoadAddress;
                }
        });
        return dyldMachHeader;
}

int parse_dyldhook_jbinfo(char **jbRootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut, bool *fullyDebuggedOut)
{
        // Get dyld header
        const struct mach_header_64 *dyldHeader = get_dyld_mach_header();
        if (!dyldHeader) return -1;

        // Check if dyld LC_UUID contains dopamine magic
        uuid_t dyldUUID;
        if (!_dyld_get_image_uuid((const struct mach_header *)dyldHeader, dyldUUID)) return -2;
        if (!string_has_prefix((char *)dyldUUID, "DOPA")) return -3;

        // If so, get __jbinfo section
        size_t jbInfoSize = 0;
        struct dyld_jbinfo *jbInfo = (struct dyld_jbinfo *)getsectiondata(dyldHeader, "__DATA", "__jbinfo", &jbInfoSize);
        if (!jbInfo) return -4;

        // Check if dyld already performed check-in
        if (jbInfo->state != DYLD_STATE_CHECKED_IN) return -5;

        // If so, parse jbinfo
        if (jbRootPathOut)        *jbRootPathOut        = jbInfo->jbRootPath;
        if (bootUUIDOut)          *bootUUIDOut          = jbInfo->bootUUID;
        if (sandboxExtensionsOut) *sandboxExtensionsOut = jbInfo->sandboxExtensions;
        if (fullyDebuggedOut)     *fullyDebuggedOut     = jbInfo->fullyDebugged;

        return 0;
}

__attribute__((constructor)) static void initializer(void)
{
        /***** roothide specific (Relaxin main.m:786) *****/
        // Must run FIRST: sets HOOK_DYLIB_PATH to the path this systemhook
        // instance was injected through (the randomized published path,
        // e.g. /usr/lib/systemhook-<jbrand>.dylib), clears DYLD_IN_CACHE
        // leftovers and arms the dyld-patch fallback detection. Every later
        // use of HOOK_DYLIB_PATH (env cleanup below, spawn hooks in common.c)
        // depends on this assignment.
        roothide_init();
        /**************************************************/

        // Under normal circumstances, dyldhook will have already handled the check-in, so get the check-in information from the __jbinfo section
        // For more information on the check-in process, check the comments in dyldhook
        if (parse_dyldhook_jbinfo(&JB_RootPath, &JB_BootUUID, &JB_SandboxExtensions, &gFullyDebugged) != 0) {
                // If under any circumstances dyldhook has *not* performed a check-in, do it now
                // This code path is taken inside xpcproxy on iOS 16, because launchd apparently no longer passes it a bootstrap port
                if (jbclient_process_checkin(&JB_RootPath, &JB_BootUUID, &JB_SandboxExtensions, &gFullyDebugged, NULL) == 0) {
                        consume_tokenized_sandbox_extensions(JB_SandboxExtensions);
                }
                else {
                        // If neither dyldhook nor systemhook managed to perform the check-in, something is very wrong and the best thing we can do is bail out
                        // Should realistically never happen though
                        return;
                }
        }

        // Unset DYLD_INSERT_LIBRARIES unconditionally after systemhook is loaded.
        //
        // WHY: dyld reads this env var during process startup (before ANY
        // constructor runs), so by the time this constructor executes:
        //   - systemhook.dylib is already loaded and initialized
        //   - dyld has already consumed the env var for injection
        //   - The env var serves NO PURPOSE in the parent process anymore
        //
        // Bankng apps call getenv("DYLD_INSERT_LIBRARIES") as one of their
        // top-3 jailbreak detection checks. The old code only unset when the
        // var contained ONLY systemhook (no TweakLoader), so when tweaks were
        // active the env var leaked through with the full injection chain.
        //
        // SAFETY:
        //   - Children spawned later via posix_spawn get their env from the
        //     caller's envp parameter (NOT from the parent's environ), so
        //     this unsetenv does NOT affect child process injection.
        //   - spawn_hook_shared() in common.c already manages DYLD_INSERT_LIBRARIES
        //     insertion/removal for each child independently.
        //   - dyld has already finished reading this var; nothing in the
        //     remaining constructor code reads it.
        //   - This runs AFTER roothide_init_with_checkin() (line 535) which
        //     is the last init function that could theoretically need it.
        //
        // This eliminates the #1 jailbreak detection vector without affecting
        // any functional behavior.
        unsetenv("DYLD_INSERT_LIBRARIES");

        // On iOS 26+, hooks have to be applied through hookd
        if (__builtin_available(iOS 19.0, *)) {

                // If available, use jbclient_mach_hookd_send_msg inside dyld instead...
                // The reason for this is that dyldhook in itself is fully self contained without calling any external code
                // We want to make sure no external code is invoked when some binary calls vm_protect
                // This is mainly due to the fact if the binary is trying to remove the executable flag of a page our logic depends on, the binary will crash
                // Frida is notorious for this, it hooks something in libsystem in every process it injects to
                // Alternatively we could also
                // - Implement inline mach_msg* syscalls into systemhook
                // - Refactor all logic involving hookd into it's own library and implement the inline syscalls there
                // But for now this works, the only problem could be something trying to hook a page in dyld itself....
                void *dyld_jbclient_mach_hookd_send_msg = litehook_find_symbol(get_dyld_mach_header(), "_jbclient_mach_hookd_send_msg");
                if (dyld_jbclient_mach_hookd_send_msg) {
                        hookd_send_msg = dyld_jbclient_mach_hookd_send_msg;
                }

                if (process_requires_hookd()) {
                        litehook_hook_memory = litehook_hook_memory_hookd;
                        litehook_hook_function(mach_vm_protect, mach_vm_protect_fixed);
                        init_hookd_external_support();
                }
        }

        // Apply posix_spawn / execve hooks
        if (__builtin_available(iOS 16.0, *)) {
                litehook_hook_function(__posix_spawn, __posix_spawn_hook);
                litehook_hook_function(__execve,      __execve_hook);
        }
        else {
                // On iOS 15 there is a way to hook posix_spawn and execve without doing instruction replacements
                // Unfortunately Apple decided to remove these in iOS 16 :(

                void **posix_spawn_with_filter = litehook_find_dsc_symbol("/usr/lib/system/libsystem_kernel.dylib", "_posix_spawn_with_filter");
                void **execve_with_filter      = litehook_find_dsc_symbol("/usr/lib/system/libsystem_kernel.dylib", "_execve_with_filter");

                *posix_spawn_with_filter = __posix_spawn_hook_with_filter;
                *execve_with_filter      = __execve_hook;
        }

        // Hook the dyld_shared_cache __fcntl to jump to the dyld __fcntl instead
        // This makes it so that library validation is also bypassed if someone calls fcntl in userspace to attach a signature manually
        void *dyld___fcntl = litehook_find_symbol(get_dyld_mach_header(), "___fcntl");
        extern int __fcntl(int fd, int op, ... /* arg */ );
        litehook_hook_function(__fcntl, dyld___fcntl);

        // Initialize stuff neccessary for sandbox_apply hook
        gLibSandboxHandle = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_FIRST | RTLD_LOCAL | RTLD_LAZY);
        sandbox_apply_orig = dlsym(gLibSandboxHandle, "sandbox_apply");

        // Apply dyld hooks
        void ***gDyldPtr = litehook_find_dsc_symbol("/usr/lib/system/libdyld.dylib", "__ZN5dyld45gDyldE");
        if (gDyldPtr) {
                // TODO: Maybe we can just rebind sandbox_apply instead?
                dyld_hook_routine(*gDyldPtr, 17, (void *)&dyld_dlsym_hook, (void **)&dyld_dlsym_orig, 0x839D);
        } else {
                void ***gAPIsPtr = litehook_find_dsc_symbol("/usr/lib/system/libdyld.dylib", "__ZN5dyld45gAPIsE");
                if (gAPIsPtr) {
                        dyld_hook_routine(*gAPIsPtr, 16, (void *)&dyld_dlsym_hook, (void **)&dyld_dlsym_orig, 0x839D);
                }
        }

/*************************** roothide *************************/
        // RootHide port (Dopamine2-roothide main.c:378 parity): after the
        // library-trust hook is in place, run the per-process roothide checkin
        // init. This was previously dead code in this fork (the function
        // existed but was never called), which meant:
        //   - redirect_paths() never ran: jailbroken binaries kept the stock
        //     CFFIXED_USER_HOME instead of the jbroot-relative home
        //   - /usr/lib/roothideinit.dylib (shipped by the RootHide bootstrap)
        //     was never loaded into jailbreak processes
        //   - in dyld-patch fallback mode, the dlopen*/dlsym dyld routine
        //     hooks (init_dyldhooks) were never installed
        // JB_RootPath is guaranteed non-NULL here: the constructor returns
        // early above when neither dyldhook nor fallback check-in succeeded.
        roothide_init_with_checkin(JB_RootPath); // will hook dlopen* if necessary
/*************************************************************/

#ifdef __arm64e__
        // Since pages have been modified in this process, we need to load forkfix to ensure forking will work
        // Optimization: If the process cannot fork at all due to sandbox, we don't need to do anything
        if (sandbox_check(getpid(), "process-fork", SANDBOX_CHECK_NO_REPORT, NULL) == 0) {
                dlopen(JBROOT_PATH("/basebin/forkfix.dylib"), RTLD_NOW);
        }
#endif

        if (load_executable_path() == 0) {
                // Load roothidehooks / watchdoghook when neccessary
                // FIX DYLIB NAME BUG: this used to dlopen "rootlesshooks.dylib",
                // but that subproject was removed from the BaseBin build (the
                // rootlesshooks target in BaseBin/Makefile is a no-op stub) and
                // only "roothidehooks.dylib" is actually built and shipped in
                // basebin.tar. The silent dlopen failure meant cfprefsd,
                // SpringBoard and lsd never got their RootHide hiding hooks.
                // The official Dopamine2-roothide loads roothidehooks.dylib
                // into these exact three daemons (roothidehooks' constructor
                // self-checks the process name, so loading it elsewhere is a
                // harmless no-op).
                // RootHide port (Relaxin parity): Relaxin additionally loads
                // roothidehooks into /usr/libexec/runningboardd (its
                // runningboardd.m hooks -[RBProcess _allowedLockedFilePaths]
                // so jailbreak processes may lock files in the jbroot).
                // Without this entry the hook file was dead code.
                if (!strcmp(gExecutablePath, "/usr/sbin/cfprefsd") ||
                        !strcmp(gExecutablePath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") ||
                        !strcmp(gExecutablePath, "/usr/libexec/lsd") ||
                        !strcmp(gExecutablePath, "/usr/libexec/runningboardd")) {
                        dlopen(JBROOT_PATH("/basebin/roothidehooks.dylib"), RTLD_NOW);
                }
                // RootHide Manager app compat (Kernel-JB): the shipped RootHide
                // Manager 1.3.9 binary crashes with SIGABRT when the user toggles
                // a blacklist switch — +[AppDelegate getDefaultsForKey:] returns
                // the IMMUTABLE NSDictionary read from RootHideConfig.plist and
                // -[BlacklistViewController switchChanged:] calls
                // setObject:forKey: on it (unrecognized selector → abort).
                // roothidehooks.dylib carries a swizzle that converts the return
                // value to a mutable dictionary (roothidehooks/rootmanager.m).
                // Load it ONLY into the manager app: the gExecutablePath for the
                // manager is <jbroot>/Applications/RootHide.app/RootHide (the app
                // is installed inside the jbroot by the RootHide bootstrap deb),
                // so a suffix match keeps the check jbroot-independent. The
                // hook's constructor gates on the exact process name "RootHide",
                // making this a no-op for every other process even if the dylib
                // were loaded elsewhere.
                else if (string_has_suffix(gExecutablePath, "/RootHide.app/RootHide")) {
                        dlopen(JBROOT_PATH("/basebin/roothidehooks.dylib"), RTLD_NOW);
                }
                else if (!strcmp(gExecutablePath, "/usr/libexec/watchdogd")) {
                        dlopen(JBROOT_PATH("/basebin/watchdoghook.dylib"), RTLD_NOW);
                }

                // ptrace hook to allow attaching a debugger to processes that systemhook did not inject into
                // e.g. allows attaching debugserver to an app where tweak injection has been disabled via choicy
                // since we want to keep hooks minimal and debugserver is the only thing I can think of that would
                // call ptrace and expect it to allow invalid pages, we only hook it in debugserver
                // this check is a bit shit since we rely on the name of the binary, but who cares ¯\_(ツ)_/¯
                if (string_has_suffix(gExecutablePath, "/debugserver")) {
                        litehook_hook_function(ptrace, ptrace_hook);
                }

#ifndef __arm64e__
                // On arm64, writing to executable pages removes CS_VALID from the csflags of the process
                // These hooks are neccessary to get the system to behave with this (since multiple system APIs check for CS_VALID and produce failures if it's not set)
                // They are ugly but needed
                litehook_hook_function(csops, csops_hook);
                litehook_hook_function(csops_audittoken, csops_audittoken_hook);
                if (__builtin_available(iOS 16.0, *)) {
                        litehook_hook_function(necp_match_policy, necp_match_policy_hook);
                        litehook_hook_function(necp_open, necp_open_hook);
                        litehook_hook_function(necp_client_action, necp_client_action_hook);
                        litehook_hook_function(necp_session_open, necp_session_open_hook);
                        litehook_hook_function(necp_session_action, necp_session_action_hook);
                }
#endif

/******************* roothide (Dopamine2-roothide main.c:427 parity) *******************/
                // RootHide port: per-executable roothide init. Previously dead
                // code in this fork. What this restores:
                //   - sysctl / sysctlbyname hooks for system daemons (NOT for
                //     removable bundle paths): after hideDeveloperMode() swaps
                //     the kernel sysctl OIDs, jailbreak daemons still need the
                //     TRUE security.mac.amfi.developer_mode_status value (the
                //     hook returns 1) — stock daemons keep seeing the swapped
                //     (hidden) value, exactly like upstream.
                //   - loadPathHook() for the jailbreak app itself (see the
                //     updated condition in roothider_main.c)
                //   - /usr/lib/roothidepatch.dylib (RootHide bootstrap) loaded
                //     into every injected process — the core per-process
                //     path-translation layer (jbroot()/rootfs()/jbrand()). Its
                //     absence meant jbroot-based paths only worked for binaries
                //     that linked libroothide at build time.
                // The dlopens are best-effort (missing dylib => no-op).
                roothide_init_with_executable(gExecutablePath);
/**************************************************************************************/

                // Load tweaks if desired
                // Resolve the loader through the active jbroot so relocated roots remain supported.
                
                // ========== ROOTHIDE HIDE INITIALIZATION ==========
                // Initialize RootHide hiding subsystem for blacklisted apps
                // This must happen BEFORE loading tweaks to ensure clean environment
                //
                // RootHide port: the old `roothide_hide_init(true)` call (from
                // the deleted patchwork file `libjailbreak/src/roothide_hide.c`)
                // has been removed. In the Relaxin upstream fork, per-process
                // hiding is implemented by `roothidehooks.dylib` (loaded into
                // cfprefsd/lsd/SpringBoard/runningboardd via DYLD_INSERT_LIBRARIES
                // from systemhook/src/roothider_main.c). The clean-mode env var
                // check below is preserved for backward compatibility with the
                // existing Kernel-JB Application-side bootstrap logic in
                // DOBootstrapper.m (which still sets ROOTHIDE_CLEAN_MODE_ENV on
                // children that should skip tweak injection).
                bool isCleanMode = false;
                if (getenv(ROOTHIDE_CLEAN_MODE_ENV)) {
                        const char *cleanMode = getenv(ROOTHIDE_CLEAN_MODE_ENV);
                        if (cleanMode && strcmp(cleanMode, "1") == 0) {
                                isCleanMode = true;
                        }
                }
                if (getenv(ROOTHIDE_MODE_ENV)) {
                        const char *roothideMode = getenv(ROOTHIDE_MODE_ENV);
                        if (roothideMode && strcmp(roothideMode, "hide") == 0) {
                                isCleanMode = true;
                        }
                }
                // Silence unused-variable warning; the env-var reads above are kept
                // for backward-compat inspection (a future commit will route the
                // clean-mode flag through the Relaxin roothidehooks per-process dylib).
                (void)isCleanMode;
                // ========== END ROOTHIDE INIT ==========
                
                if (should_enable_tweaks()) {
                        const char *tweakLoaderPath = JBROOT_PATH("/usr/lib/TweakLoader.dylib");
                        if (access(tweakLoaderPath, F_OK) == 0) {
                                void *tweakLoaderHandle = dlopen(tweakLoaderPath, RTLD_NOW);
                                if (tweakLoaderHandle != NULL) {
                                        dlclose(tweakLoaderHandle);
                                }
                        }
                }

#ifndef __arm64e__
                // Feeable attempt at adding back CS_VALID
                jbclient_cs_revalidate();
#endif
        }

        // ========== ROOTHIDE PATCHER IMPORT DIAGNOSTICS ==========
        // Temporary diagnostics for the silent DocumentPicker import failure.
        // The Patcher app imports a picked deb via copyItem() into
        // jbroot/var/mobile/RootHidePatcher/.Inbox and swallows all errors
        // (catch -> print), so the user sees "no alert, nothing happens".
        // These probes re-create every step of that copy inside the Patcher
        // process itself and log each result to
        // <jbroot>/var/mobile/.patcher_diag.log which the jailbreak app
        // surfaces to the user.
        if (string_has_suffix(gExecutablePath, "/Patcher.app/Patcher")) {
                // The log lives INSIDE the Patcher work tree, which check-in now
                // grants a dedicated read-write extension for — so even if the
                // umbrella /var/mobile extension is broken on this build, the
                // probes can still record results for the jailbreak app to show.
                char diagPath[PATH_MAX];
                snprintf(diagPath, sizeof(diagPath), "%s/var/mobile/RootHidePatcher/.patcher_diag.log",
                         JB_RootPath ? JB_RootPath : "");

                // (0) marker: the Patcher process reached systemhook init with a
                // valid checkin — if this line is MISSING from the log the
                // Patcher was spawned clean (not injected / not checked in) and
                // everything else follows.
                FILE *df = fopen(diagPath, "a");
                if (df) {
                        fprintf(df, "[%ld] === Patcher launched: pid=%d uid=%d checkin=%d jbroot=%s\n",
                                (long)time(NULL), getpid(), getuid(),
                                JB_RootPath ? 1 : 0,
                                JB_RootPath ? JB_RootPath : "(none)");
                        fclose(df);
                }

                if (JB_RootPath) {
                        // (1) stat + open of the Patcher work dirs — what
                        // folderCheck()/DocumentPicker touch first.
                        const char *probeDirs[] = {
                                "/var/mobile/RootHidePatcher",
                                "/var/mobile/RootHidePatcher/.Inbox",
                        };
                        for (size_t i = 0; i < sizeof(probeDirs)/sizeof(probeDirs[0]); i++) {
                                char p[PATH_MAX];
                                snprintf(p, sizeof(p), "%s%s", JB_RootPath, probeDirs[i]);
                                struct stat st;
                                int stR = stat(p, &st);
                                int opR = open(p, O_RDONLY);
                                int opErr = errno;
                                if (opR >= 0) close(opR);
                                df = fopen(diagPath, "a");
                                if (df) {
                                        fprintf(df, "[%ld] stat(%s)=rc%d mode=%o uid=%d open=%d errno=%d(%s)\n",
                                                (long)time(NULL), p, stR,
                                                stR == 0 ? (int)(st.st_mode & 07777) : 0,
                                                stR == 0 ? (int)st.st_uid : -1,
                                                opR, stR == 0 && opR >= 0 ? 0 : opErr,
                                                stR == 0 && opR >= 0 ? "" : strerror(opErr));
                                        fclose(df);
                                }
                        }

                        // (2) the critical probe: create+write+unlink inside
                        // .Inbox — exactly what DocumentPicker's copyItem does.
                        // If this fails the app sandbox is blocking the write
                        // (extension not consumed / not honoured) and the import
                        // can never work.
                        char probe[PATH_MAX];
                        snprintf(probe, sizeof(probe), "%s/var/mobile/RootHidePatcher/.Inbox/.diag-%d", JB_RootPath, getpid());
                        errno = 0;
                        int fd = open(probe, O_CREAT | O_WRONLY, 0644);
                        int openErr = errno;
                        if (fd >= 0) {
                                errno = 0;
                                ssize_t w = write(fd, "diag", 4);
                                int wErr = errno;
                                fsync(fd);
                                close(fd);
                                unlink(probe);
                                df = fopen(diagPath, "a");
                                if (df) {
                                        fprintf(df, "[%ld] WRITE-PROBE .Inbox OK: wrote=%zd errno=%d\n",
                                                (long)time(NULL), w, wErr);
                                        fclose(df);
                                }
                        } else {
                                df = fopen(diagPath, "a");
                                if (df) {
                                        fprintf(df, "[%ld] WRITE-PROBE .Inbox FAILED: errno=%d (%s)\n",
                                                (long)time(NULL), openErr, strerror(openErr));
                                        fclose(df);
                                }
                        }
                }
        }
        // ========== END PATCHER DIAGNOSTICS ==========
}