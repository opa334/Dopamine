#ifndef JBSERVER_DOMAINS
#define JBSERVER_DOMAINS

// Domain: System-Wide
// Reachable from all processes
#define JBS_DOMAIN_SYSTEMWIDE 1
enum {
    JBS_SYSTEMWIDE_GET_JBROOT = 1,
    JBS_SYSTEMWIDE_GET_BOOT_UUID,
    JBS_SYSTEMWIDE_TRUST_FILE,
    JBS_SYSTEMWIDE_PROCESS_CHECKIN,
    JBS_SYSTEMWIDE_FORK_FIX,
    JBS_SYSTEMWIDE_CS_REVALIDATE,
    JBS_SYSTEMWIDE_JBSETTINGS_GET,
    JBS_SYSTEMWIDE_PERSONA_FIX,
};

// Domain: Platform
// Reachable from all processes that have CS_PLATFORMIZED or are entitled with platform-application or are the Dopamine app itself
#define JBS_DOMAIN_PLATFORM 2
enum {
    JBS_PLATFORM_SET_PROCESS_DEBUGGED = 1,
    JBS_PLATFORM_STAGE_JAILBREAK_UPDATE,
    JBS_PLATFORM_JBSETTINGS_SET,
    JBS_PLATFORM_SET_SYSTEMWIDE_DOMAIN_ENABLED,
};


// Domain: Watchdog
// Only reachable from watchdogd
#define JBS_DOMAIN_WATCHDOG 3
enum {
    JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC = 1,
    JBS_WATCHDOG_GET_LAST_USERSPACE_PANIC
};

// Domain: Root
// Only reachable from root processes
#define JBS_DOMAIN_ROOT 4
enum {
    JBS_ROOT_GET_PHYSRW = 1,
    JBS_ROOT_SIGN_THREAD,
    JBS_ROOT_GET_SYSINFO,
    JBS_ROOT_STEAL_UCRED,
    JBS_ROOT_SET_MAC_LABEL,
    JBS_ROOT_TRUSTCACHE_INFO,
    JBS_ROOT_TRUSTCACHE_ADD_CDHASH,
    JBS_ROOT_TRUSTCACHE_CLEAR,
};

// Domain: Dopamine
// Reachable exclusively from Dopamine app
#define JBS_DOMAIN_DOPAMINE 5
enum {
    JBS_DOPAMINE_IS_JAILBROKEN = 1,
    JBS_DOPAMINE_GET_ROOT,
    JBS_DOPAMINE_DROP_ROOT,
    // FIX REMOVE-JAILBREAK EPERM (Issue 2): see jbdomain_dopamine.c
    // dopamine_set_mac_label for the full write-up. Appending at the END of
    // the enum is ABI-safe for existing clients (action codes unchanged),
    // and the dispatcher only requires dense packing of DOMAINS, not actions.
    JBS_DOPAMINE_SET_MAC_LABEL,
};

// Domain: RootHide
// Reachable from the Dopamine app (for jailbreakd lookup/checkin) and from
// any process that needs to query the RootHide blacklist (e.g. systemhook
// deciding whether to inject tweaks into a blacklisted app).
//
// Ported from Relaxin upstream RootHide fork. Action codes match Relaxin's
// `jbclient_roothide.c` and `jbdomain_roothide.c` exactly.
//
// NOTE: the dispatcher in jbserver.c walks `server->domains[]` by index and
// aborts on NULL entries, so the array MUST be densely packed. Therefore
// JBS_DOMAIN_ROOTHIDE is set to 6 (immediately after JBS_DOMAIN_DOPAMINE=5)
// rather than 5 (Relaxin's value) to preserve Kernel-JB's existing DOPAMINE
// domain. If upstream Dopamine later adds domain 6, this value will need to
// move (and the array in jbserver_global.c updated accordingly).
#define JBS_DOMAIN_ROOTHIDE 6
enum {
    JBS_ROOTHIDE_JAILBROKEN_CHECK = 1,
    JBS_ROOTHIDE_PALEHIDE_PRESENT,
    JBS_ROOTHIDE_BLACKLIST_CHECK,
    JBS_ROOTHIDE_JAILBREAKD_LOOKUP,
    JBS_ROOTHIDE_JAILBREAKD_CHECKIN,
    JBS_ROOTHIDE_TRUST_LIBRARY_RECURSE,
    JBS_ROOTHIDE_TRUST_EXECUTABLE_RECURSE,
    JBS_ROOTHIDE_DYLD_PATCH_ENABLED_GET,
    JBS_ROOTHIDE_DYLD_PATCH_ENABLED_SET,
    JBS_ROOTHIDE_JAILBREAKD_CHECKIN_STATUS,
};

#define JBS_BOOMERANG_DONE 42

// RootHide port (Relaxin upstream): trustcache entry size constants.
// Used by jbclient_root_trustcache_append_entries and the trustcache_nokcall
// subsystem. Defined here (matching Relaxin's jbserver_domains.h) so they're
// visible to all consumers of <libjailbreak/jbserver_domains.h>.
#define JBS_TRUSTCACHE_ENTRY_SIZE 22U
#define JBS_TRUSTCACHE_HASH_SIZE 20U
#define JBS_TRUSTCACHE_MAX_APPEND_ENTRIES 65536U

#endif