#include <stdbool.h>
#include <stdint.h>

typedef enum {
	JBS_TYPE_UINT64,
	JBS_TYPE_STRING,
	JBS_TYPE_CALLER_TOKEN,
} jbserver_type;

typedef struct s_jbserver_arg
{
    const char *name;
    jbserver_type type;
	bool out;
} jbserver_arg;

struct jbserver_action {
    void *handler;
	uint64_t argCount;
    jbserver_arg *args;
};

struct jbserver_domain {
    void *permissionHandler;
    uint64_t actionCount;
    struct jbserver_action actions[];  // Flexible array member moved to the end
};

struct jbserver_impl {
    uint64_t maxDomain;
    struct jbserver_domain **domains;
};

extern struct jbserver_impl gGlobalServer;



// Domain: System-Wide
// Reachable from all processes
#define JBS_DOMAIN_SYSTEMWIDE 1
#define JBS_SYSTEMWIDE_GET_JB_ROOT 1
#define JBS_SYSTEMWIDE_GET_BOOT_UUID 2
#define JBS_SYSTEMWIDE_TRUST_BINARY 3
#define JBS_SYSTEMWIDE_PROCESS_CHECKIN 4
#define JBS_SYSTEMWIDE_FORK_FIX 5
//#define JBS_SYSTEMWIDE_LOCK_PAGE 6

// Domain: Platform
// Reachable from all processes that have CS_PLATFORMIZED or are entitled with platform-application or are the Dopamine app itself
#define JBS_DOMAIN_PLATFORM 2
#define JBS_PLATFORM_SET_PROCESS_DEBUGGED 1
#define JBS_ROOT_JAILBREAK_UPDATE 2
#define JBS_ROOT_SET_JAILBREAK_VISIBLE 3

// Domain: Watchdog
// Only reachable from watchdogd
#define JBS_DOMAIN_WATCHDOG 3
#define JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC 1

// Domain: Root
// Only reachable from root processes
#define JBS_DOMAIN_ROOT 4
#define JBS_ROOT_GET_PHYSRW 1
#define JBS_ROOT_GET_KCALL 2
#define JBS_ROOT_GET_SYSINFO 3
#define JBS_ROOT_ADD_CDHASH 4