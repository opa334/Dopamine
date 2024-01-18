#ifndef JBSERVER_H
#define JBSERVER_H

#include <stdbool.h>
#include <stdint.h>
#include <xpc/xpc.h>

typedef enum {
    JBS_TYPE_BOOL,
	JBS_TYPE_UINT64,
	JBS_TYPE_STRING,
	JBS_TYPE_DATA,
    JBS_TYPE_ARRAY,
	JBS_TYPE_DICTIONARY,
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
    jbserver_arg *args;
};

struct jbserver_domain {
    void *permissionHandler;
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
enum {
    JBS_SYSTEMWIDE_GET_JB_ROOT = 1,
    JBS_SYSTEMWIDE_GET_BOOT_UUID = 2,
    JBS_SYSTEMWIDE_TRUST_BINARY = 3,
    JBS_SYSTEMWIDE_PROCESS_CHECKIN = 4,
    JBS_SYSTEMWIDE_FORK_FIX = 5,
};
//#define JBS_SYSTEMWIDE_LOCK_PAGE 6

// Domain: Platform
// Reachable from all processes that have CS_PLATFORMIZED or are entitled with platform-application or are the Dopamine app itself
#define JBS_DOMAIN_PLATFORM 2
enum {
    JBS_PLATFORM_SET_PROCESS_DEBUGGED = 1,
    JBS_PLATFORM_JAILBREAK_UPDATE = 2,
    JBS_PLATFORM_SET_JAILBREAK_VISIBLE = 3,
};


// Domain: Watchdog
// Only reachable from watchdogd
#define JBS_DOMAIN_WATCHDOG 3
enum {
    JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC = 1,
};

// Domain: Root
// Only reachable from root processes
#define JBS_DOMAIN_ROOT 4
enum {
    JBS_ROOT_GET_PHYSRW = 1,
    JBS_ROOT_GET_KCALL = 2,
    JBS_ROOT_GET_SYSINFO = 3,
    JBS_ROOT_ADD_CDHASH = 4,
};

int jbserver_received_xpc_message(struct jbserver_impl *server, xpc_object_t xmsg);

#endif
