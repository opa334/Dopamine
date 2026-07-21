#ifndef __JBCLIENT_MACH
#define __JBCLIENT_MACH

#include <mach/mach.h>
#include <stdint.h>
#include "jbserver.h"

mach_port_t jbclient_mach_get_launchd_port(void);
int jbclient_mach_send_msg(mach_msg_header_t *hdr, struct jbserver_mach_msg_reply *reply);
int jbclient_mach_process_checkin(char *jbRootPathOut, char *bootUUIDOut, char *sandboxExtensionsOut, bool *fullyDebuggedOut);
int jbclient_mach_fork_fix(pid_t childPid);
int jbclient_mach_trust_file(int fd, struct siginfo *siginfo);

#endif