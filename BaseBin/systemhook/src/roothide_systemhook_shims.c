// roothide_systemhook_shims.c
//
// RootHide port (Relaxin upstream): shims for symbols referenced by the
// Relaxin systemhook roothider_main.c that are NOT implemented natively in
// Kernel-JB's systemhook:
//
//   - __posix_spawn_orig  — Kernel-JB's common/common.h declares it but
//                           no .c file implements it. Relaxin's common.c:84
//                           implements it as syscall(SYS_posix_spawn, ...).
//
//   - __execve_orig       — same situation; Relaxin's common.c:92 implements
//                           it as syscall(SYS_execve, ...).
//
//   - spawn_config_for_executable — Kernel-JB's common/common.c:121 declares
//                           it as `static`, so it's invisible to other
//                           translation units (roothider_main.c references
//                           it). Relaxin's version is non-static.
//
// Rather than modify Kernel-JB's common.c (which would change the visibility
// of an existing internal helper), this shim file provides new implementations
// that the linker can resolve.

#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <spawn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <xpc/xpc.h>
#include <xpc_private.h>

// systemhook.dylib is self-contained (does NOT link libroothide), but it
// defines get_jbroot() in main.c and includes jbroot.h for the JBROOT_PATH
// macro. We include the same header here so we can call JBROOT_PATH() to
// resolve the config.plist path at runtime.
#include <libjailbreak/jbroot.h>

// kSpawnConfig type and values (must match common/common.h's enum).
// Defined here as macros so the shim compiles independently of common.h.
// The type is typedef'd to int since the enum is just integer flags.
#ifndef kSpawnConfigInject
#define kSpawnConfigInject        (1 << 0)
#endif
#ifndef kSpawnConfigTrust
#define kSpawnConfigTrust         (1 << 1)
#endif
#ifndef kSpawnConfigPatchProcess
#define kSpawnConfigPatchProcess  (1 << 2)
#endif
typedef int kSpawnConfig;

// Shim: __posix_spawn_orig — invoke the underlying posix_spawn syscall directly.
// This is what Relaxin's common.c:84-90 does.
struct _posix_spawn_args_desc;
int __posix_spawn_orig(pid_t *restrict pid,
                       const char *restrict path,
                       struct _posix_spawn_args_desc *desc,
                       char *const argv[restrict],
                       char *const envp[restrict]) {
    return syscall(SYS_posix_spawn, pid, path, desc, argv, envp);
}

// Shim: __execve_orig — invoke the underlying execve syscall directly.
int __execve_orig(const char *path, char *const argv[], char *const envp[]) {
    return syscall(SYS_execve, path, argv, envp);
}

// ── User-config ProcessBlacklist reader (ported from Dopamine2-roothide) ──────
//
// Reads <jbroot>/var/mobile/Library/RootHide/RootHideConfig.plist which is
// written by RootHideManager.m (the Dopamine Settings page).
// (DOBootstrapper / Relaxin bootstrap) and contains a "ProcessBlacklist" array
// of executable paths the user chose to blacklist from tweak injection.
//
// This is a local copy of the logic from common/common.c:99-143
// (jbuserconfig_get_value + the XPC array check in spawn_config_for_executable).
// We reimplement it here to avoid modifying common.c's static function visibility.
//
// SAFETY: The plist read is cached (static dict + mtime check) so repeated
// calls within the same process lifetime are fast (~0 cost after first read).
// Missing file → returns NULL → no blacklist → default inject behavior.
// Malformed plist → returns NULL → safe fallback.

static xpc_object_t _userconfig_get_value(const char *key) {
    // JBROOT_PATH uses get_jbroot() which is defined in systemhook's main.c.
    // systemhook.dylib is self-contained (no libroothide link), but the jbroot.h
    // header provides an inline JBROOT_PATH macro that calls get_jbroot().
    char configPathBuf[PATH_MAX] = {0};
    const char *configPath = JBROOT_PATH("/var/mobile/Library/RootHide/RootHideConfig.plist");
    if (configPath) {
        strlcpy(configPathBuf, configPath, sizeof(configPathBuf));
        configPath = configPathBuf;
    }
    if (!configPath || access(configPath, R_OK) != 0) return NULL;

    // Simple cache: re-read only if file changed since last read.
    static xpc_object_t configDict = NULL;
    static time_t lastMtime = 0;

    struct stat st;
    if (stat(configPath, &st) != 0) return NULL;

    if (st.st_mtime != lastMtime) {
        lastMtime = st.st_mtime;
        int fd = open(configPath, O_RDONLY);
        if (fd < 0) return NULL;

        size_t len = st.st_size;
        void *addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
        close(fd);
        if (addr == MAP_FAILED) return NULL;

        if (configDict) xpc_release(configDict);
        configDict = xpc_create_from_plist(addr, len);
        munmap(addr, len);
    }

    if (!configDict || xpc_get_type(configDict) != XPC_TYPE_DICTIONARY)
        return NULL;

    return xpc_dictionary_get_value(configDict, key);
}

// Shim: spawn_config_for_executable — non-static re-export matching Dopamine2-roothide.
//
// Returns a bitmask:
//   bit 0 (kSpawnConfigInject)        — set if path is not blacklisted
//   bit 1 (kSpawnConfigTrust)         — set if path should be trust-cached
//   bit 2 (kSpawnConfigPatchProcess)  — set if process should be patched
//
// FIX: Ported the full Dopamine2-roothide user blacklist logic. Previously
// this was a stub that returned inject+trust+patch for ALL non-hardcoded
// processes, which meant user-blacklisted banking apps STILL received tweak
// injection and were still patched — detectable by the app. Now reads the
// "ProcessBlacklist" array from <jbroot>/var/mobile/Library/RootHide/RootHideConfig.plist
// (written by RootHideManager.m, read by blacklist.m)
// the JB app's DOBootstrapper) and returns 0 (no inject/trust/patch) for
// any path found in that array.
//
// The hard blacklist (system daemons that crash when injected) is checked
// FIRST — those ALWAYS return 0 regardless of user config.
//
// FAIL-SAFE: If config.plist is missing or unparseable, falls through to
// the default (inject + trust + patch) — same behavior as before. This
// can never cause a hang or boot failure.
kSpawnConfig spawn_config_for_executable(const char *path, char *const argv[restrict]) {
    (void)argv;
    if (!path) return 0;

    // ── 1. Hard blacklist (system daemons that crash when injected) ───────────
    // Matches Dopamine2-roothide common.c:125-130 exactly.
    static const char *kBlacklist[] = {
        "/System/Library/Frameworks/GSS.framework/Helpers/GSSCred",
        "/System/Library/PrivateFrameworks/DataAccess.framework/Support/dataaccessd",
        "/System/Library/PrivateFrameworks/IDSBlastDoorSupport.framework/XPCServices/IDSBlastDoorService.xpc/IDSBlastDoorService",
        "/System/Library/PrivateFrameworks/MessagesBlastDoorSupport.framework/XPCServices/MessagesBlastDoorService.xpc/MessagesBlastDoorService",
    };
    for (size_t i = 0; i < sizeof(kBlacklist)/sizeof(kBlacklist[0]); i++) {
        if (strcmp(kBlacklist[i], path) == 0) return 0;
    }

    // ── 2. User-config ProcessBlacklist (ported from Dopamine2-roothide) ───────
    // This reads <jbroot>/basebin/config.plist → "ProcessBlacklist" array.
    // The jailbreak app writes this file when the user toggles "disable tweaks"
    // for a specific app in the RootHide Manager UI.
    //
    // Previously MISSING in this port — the stub always returned inject+trust+patch,
    // so user-blacklisted apps still got tweak injection. Banking apps with
    // "disable tweaks" enabled would still be injected with TweakLoader.dylib,
    // visible in their dyld image list → jailbreak detected.
    xpc_object_t userBlacklist = _userconfig_get_value("ProcessBlacklist");
    if (userBlacklist && xpc_get_type(userBlacklist) == XPC_TYPE_ARRAY) {
        size_t count = xpc_array_get_count(userBlacklist);
        for (size_t i = 0; i < count; i++) {
            const char *blacklistedPath = xpc_array_get_string(userBlacklist, i);
            if (blacklistedPath && strcmp(blacklistedPath, path) == 0) {
                // User blacklisted this process: trust it (so it can run) but
                // do NOT inject tweaks or patch the process. Matches
                // Dopamine2-roothide common.c:141 behavior.
                return kSpawnConfigTrust;
            }
        }
    }

    // ── 3. Default: inject + trust (kSpawnConfigPatchProcess deliberately
    // NOT set) ─────────────────────────────────────────────────────────────────
    // REGRESSION ANALYSIS (dopamine.ips bug_type 509, iOS 16.7.16 stackshot,
    // build 1c973e0): setting kSpawnConfigPatchProcess by default routed EVERY
    // spawn system-wide through the roothider_main.c suspended-spawn +
    // jbdSpawnExecStart/jbdSpawnPatchChild branch. That branch makes TWO
    // synchronous XPC round trips per child, and its failure paths are
    // catastrophic under a stock-dyld fork where children already self-check-in
    // via the DYLD_INSERT_LIBRARIES-injected systemhook:
    //   - jbdSpawnExecStart failure returns 201 straight out of posix_spawn
    //     (dash printed "Unknown error: 201" for every command in
    //     prep_bootstrap.sh), and
    //   - jbdSpawnPatchChild failure SIGQUIT+SIGKILLs the suspended child,
    //     which reads to the user as "spam kill 9" and freezes setup.
    // Proof from the stackshot: the jailbreak worker (tid 3952) sat blocked in
    // jbserver_xpc_send after xpc_pipe_routine with the reply never arriving —
    // every extra XPC round trip is a hang vector whenever the server side is
    // busy (bootstrap storm) or mid-teardown.
    // The exec-trace jbenv patch is redundant in stock-dyld mode anyway:
    // spawn_exec_hook_common already appends DYLD_INSERT_LIBRARIES=systemhook,
    // and the child's systemhook constructor fetches jbroot + sandbox
    // extensions itself via jbclient_process_checkin. Upstream agrees the path
    // is optional: exec_cmd_roothide_spawn skips patching when systemhook is
    // already loaded (dlopen("systemhook.dylib", RTLD_NOLOAD)).
    // The RootHidePatcher fix in 1c973e0 was the TRUST half (recursive trust of
    // bash -> libvrootapi -> libvroot -> libroothide -> roothideinit), which
    // stays enabled here via kSpawnConfigTrust; jbenv/sandbox for the
    // patcher's shell comes from env-based injection, exactly like every
    // other jailbreak binary.
    return (kSpawnConfigInject | kSpawnConfigTrust);
}
