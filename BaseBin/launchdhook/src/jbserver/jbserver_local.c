#include "jbserver_global.h"
#include <libjailbreak/jbserver.h>
#include <pthread.h>

volatile bool gLocalJBServerRunning = false;
pthread_t gLocalJBServerThread = NULL;
mach_port_t gLocalJBServerPort = MACH_PORT_NULL;

void *jbserver_local_loop(void *arg)
{
	while (gLocalJBServerRunning) {
		xpc_object_t xdict = NULL;
		if (!xpc_pipe_receive(gLocalJBServerPort, &xdict)) {
			jbserver_received_xpc_message(&gGlobalServer, xdict);
			xpc_release(xdict);
		}
	}
	return NULL;
}

mach_port_t jbserver_local_start(void)
{
	if (gLocalJBServerRunning) return gLocalJBServerPort;

	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &gLocalJBServerPort);
	mach_port_insert_right(mach_task_self(), gLocalJBServerPort, gLocalJBServerPort, MACH_MSG_TYPE_MAKE_SEND);

	gLocalJBServerRunning = true;
	pthread_create(&gLocalJBServerThread, NULL, (void *(*)(void *))jbserver_local_loop, NULL);

	return gLocalJBServerPort;
}

void jbserver_local_stop(void)
{
	if (!gLocalJBServerRunning) return;

	gLocalJBServerRunning = false;
	
	// Send a message to server to wake the thread up (which will make it exit since gLocalJBServerRunning is false)
	mach_msg_header_t h;
	h.msgh_bits = MACH_MSGH_BITS_REMOTE(MACH_MSG_TYPE_MAKE_SEND);
	h.msgh_size = sizeof(h);
	h.msgh_remote_port = gLocalJBServerPort;
	h.msgh_local_port = MACH_PORT_NULL;
	mach_msg_send(&h);

	// Now, wait for it to finish
	void *r;
	pthread_join(gLocalJBServerThread, &r);

	mach_port_deallocate(mach_task_self(), gLocalJBServerPort);
	gLocalJBServerPort = MACH_PORT_NULL;
	gLocalJBServerThread = NULL;
}