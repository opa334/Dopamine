#ifndef JBSERVER_XPC_H
#define JBSERVER_XPC_H

#include <libjailbreak/jbserver.h>
#include <xpc/xpc.h>

int jbserver_received_xpc_message(struct jbserver_impl *server, xpc_object_t xmsg);
#endif
