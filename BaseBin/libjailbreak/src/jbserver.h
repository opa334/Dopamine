#ifndef JBSERVER_H
#define JBSERVER_H

#include <stdbool.h>
#include <stdint.h>
#include <xpc/xpc.h>
#include <xpc_private.h>
#include "signatures.h"
#include "jbserver_domains.h"

typedef enum {
    JBS_TYPE_BOOL,
	JBS_TYPE_UINT64,
	JBS_TYPE_STRING,
	JBS_TYPE_DATA,
    JBS_TYPE_ARRAY,
	JBS_TYPE_DICTIONARY,
    JBS_TYPE_FD,
	JBS_TYPE_CALLER_TOKEN,
    JBS_TYPE_XPC_GENERIC,
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
    bool (*permissionHandler)(audit_token_t);
    struct jbserver_action actions[];  // Flexible array member moved to the end
};

struct jbserver_impl {
    uint64_t maxDomain;
    struct jbserver_domain **domains;
};

extern struct jbserver_impl gGlobalServer;

int jbserver_received_xpc_message(struct jbserver_impl *server, xpc_object_t xmsg);

#define JBSERVER_MACH_MAGIC 0x444F50414D494E45
#define JBSERVER_MACH_CHECKIN 0
#define JBSERVER_MACH_FORK_FIX 1
#define JBSERVER_MACH_TRUST_FILE 2

struct jbserver_mach_msg {
    mach_msg_header_t hdr;
    uint64_t magic;
    uint64_t action;
};

struct jbserver_mach_msg_reply {
    struct jbserver_mach_msg msg;
    uint64_t status;
};

struct jbserver_mach_msg_checkin {
    struct jbserver_mach_msg base;
};

struct jbserver_mach_msg_checkin_reply {
    struct jbserver_mach_msg_reply base;
    bool fullyDebugged;
    char jbRootPath[PATH_MAX];
    char bootUUID[37];
    char sandboxExtensions[2000];
};

struct jbserver_mach_msg_forkfix {
    struct jbserver_mach_msg base;
    pid_t childPid;
};

struct jbserver_mach_msg_forkfix_reply {
    struct jbserver_mach_msg_reply base;
};

struct jbserver_mach_msg_trust_fd {
    struct jbserver_mach_msg base;
    int64_t fd;
    bool siginfoPopulated;
    struct siginfo siginfo;
};

struct jbserver_mach_msg_trust_fd_reply {
    struct jbserver_mach_msg_reply base;
};

struct jbserver_mach_complex_msg {
    mach_msg_header_t hdr;
    mach_msg_body_t body;
};

#endif
