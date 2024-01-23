#ifndef JBCLIENT_XPC_H
#define JBCLIENT_XPC_H

#include <xpc/xpc.h>
#include <stdint.h>

void jbclient_xpc_set_custom_port(mach_port_t serverPort);

xpc_object_t jbserver_xpc_send_dict(xpc_object_t xdict);
xpc_object_t jbserver_xpc_send(uint64_t domain, uint64_t action, xpc_object_t xargs);

char *jbclient_get_root_path(void);
char *jbclient_get_boot_uuid(void);
int jbclient_trust_binary(const char *binaryPath);
int jbclient_trust_library(const char *libraryPath);
int jbclient_process_checkin(char **rootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut);
int jbclient_fork_fix(uint64_t childPid);
int jbclient_platform_set_process_debugged(uint64_t pid);
int jbclient_platform_jailbreak_update(const char *updateTar);
int jbclient_platform_set_jailbreak_visible(bool visible);
int jbclient_watchdog_intercept_userspace_panic(const char *panicMessage);
int jbclient_root_get_physrw(void);
int jbclient_root_get_kcall(uint64_t stackAllocation, uint64_t *arcContextOut);
int jbclient_root_get_sysinfo(xpc_object_t *sysInfoOut);
int jbclient_root_add_cdhash(uint8_t *cdhashData, size_t cdhashLen);
int jbclient_root_steal_ucred(uint64_t ucredToSteal, uint64_t *orgUcred);
int jbclient_boomerang_done(void);

#endif
