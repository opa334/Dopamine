#ifndef ROOTHIDE_XPC_PRIVATE_H
#define ROOTHIDE_XPC_PRIVATE_H
#include <xpc/xpc.h>
#include <mach/mach.h>
#include <xpc_private.h>

//real xpc_pipe_receive
//extern int xpc_pipe_receive(mach_port_t port, XPC_GIVES_REFERENCE xpc_object_t *message, bool timeout);

extern xpc_object_t xpc_mach_send_create(mach_port_t);
extern mach_port_t xpc_mach_send_get_right(xpc_object_t); //will deallocate the port when releasing xpc object
extern mach_port_t xpc_mach_send_copy_right(xpc_object_t);

extern xpc_object_t xpc_mach_recv_create(mach_port_t);
extern mach_port_t xpc_mach_recv_extract_right(xpc_object_t);

#endif // ROOTHIDE_XPC_PRIVATE_H