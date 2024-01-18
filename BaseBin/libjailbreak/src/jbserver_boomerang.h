#ifndef JBSERVER_BOOMERANG_H
#define JBSERVER_BOOMERANG_H

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <xpc/xpc.h>
#include <bsm/audit.h>

#include "jbserver.h"

int boomerang_get_physrw(audit_token_t *clientToken);
int boomerang_get_kcall(audit_token_t *clientToken, uint64_t stackAllocation, uint64_t *arcContextOut);
int boomerang_get_sysinfo(xpc_object_t *sysInfoOut);

extern struct jbserver_impl gBoomerangServer;

#endif