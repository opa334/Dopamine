#ifndef ROOTHIDER_H
#define ROOTHIDER_H

#include "roothider/log.h"
#include "roothider/common.h"
#include "roothider/ptrace.h"
#include "roothider/mach_exc.h"
#include "roothider/exec_patch.h"
#include "roothider/jailbreakd.h"
#include "roothider/xpc_private.h"
#include "roothider/crashreporter.h"

extern int roothide_unsupport_request();
extern bool roothide_domain_allowed(audit_token_t clientToken);

#endif // ROOTHIDER_H