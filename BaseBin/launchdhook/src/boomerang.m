#import <Foundation/Foundation.h>
#import <spawn.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/jbserver.h>
#import <libjailbreak/jbserver_boomerang.h>
#import <libjailbreak/physrw.h>
#import <unistd.h>

int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *__restrict attr, mach_port_t portarray[], uint32_t count);

extern int (*posix_spawn_orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]);

#define JB_DOMAIN_PRIMITIVE_STORAGE 10

#define JB_PRIMITIVE_STORAGE_RETRIEVE_PHYSRW 1
#define JB_PRIMITIVE_STORAGE_RETRIEVE_KCALL 2

xpc_object_t pipe_send_message(xpc_object_t pipe, xpc_object_t xdict)
{
	/*FILE *f;
	char *xdictDesc = xpc_copy_description(xdict);
	f = fopen("/var/mobile/boomerang.log", "a");
	fprintf(f, "[launchd client] Sending %s\n", xdictDesc);
	fclose(f);
	free(xdictDesc);*/

	xpc_object_t xreply = nil;
	int r = xpc_pipe_routine_with_flags(pipe, xdict, &xreply, 0);
	if (r != 0) {
		return nil;
	}
	if (!xreply) {
		return nil;
	}
	int64_t result = xpc_dictionary_get_int64(xreply, "result");
	if (result != 0) {
		return nil;
	}

	/*f = fopen("/var/mobile/boomerang.log", "a");
	char *xreplyDesc = xpc_copy_description(xreply);
	fprintf(f, "[launchd client] Received reply %s\n", xreplyDesc);
	fclose(f);
	free(xreplyDesc);*/

	return xreply;
}

void boomerang_stashPrimitives()
{
	__block bool boomerangHasPhysrw = false;
	__block bool boomerangHasKcall = false;
	dispatch_semaphore_t boomerangDone = dispatch_semaphore_create(0);

	mach_port_t serverPort = MACH_PORT_NULL;
	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &serverPort);
	mach_port_insert_right(mach_task_self(), serverPort, serverPort, MACH_MSG_TYPE_MAKE_SEND);

	// Small server provided to boomerang to obtain exploit primitives
	dispatch_source_t serverSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)serverPort, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(serverSource, ^{
		xpc_object_t xdict = nil;
		if (!xpc_pipe_receive(serverPort, &xdict)) {
			if (!jbserver_received_xpc_message(&gBoomerangServer, xdict)) {
				if (xpc_get_type(xdict) == XPC_TYPE_DICTIONARY) {
					if (xpc_dictionary_get_bool(xdict, "boomerang-done")) {
						dispatch_semaphore_signal(boomerangDone);
						return;
					}
				}
			}
		}
	});
	dispatch_resume(serverSource);

	// Spawn boomerang process
	pid_t boomerangPid = 0;
	posix_spawnattr_t attr = NULL;
	posix_spawnattr_init(&attr);
	posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){ serverPort }, 1);
	int ret = posix_spawn_orig(&boomerangPid, JBRootPath("basebin/boomerang"), NULL, &attr, NULL, NULL);
	if (ret != 0) return;
	posix_spawnattr_destroy(&attr);

	// Wait for boomerang to retrieve the primitives from launchd (handled in server above)
	dispatch_semaphore_wait(boomerangDone, DISPATCH_TIME_FOREVER);
	dispatch_source_cancel(serverSource);

	// Stash boomerang pid in environment to later be able to call waitpid on it
	char pidBuf[10];
	snprintf(pidBuf, 10, "%d", boomerangPid);
	setenv("BOOMERANG_PID", pidBuf, 1);
}

void boomerang_recoverPrimitives(void)
{
	// Mach port to boomerang should be stored in our registeredPorts[0]
	// Use it to recover primitives, then replace it with MACH_PORT_NULL
	// Afterwards reset registered ports to make launchd happy
	mach_port_t *registeredPorts;
	mach_msg_type_number_t registeredPortsCount = 0;
	if (mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount) != 0 || registeredPortsCount < 1) return;
	mach_port_t boomerangPort = registeredPorts[0];
	jbclient_xpc_init_from_port(boomerangPort);

	// Recover boomerang pid from environment
	pid_t boomerangPid = 0;
	const char *pidBuf = getenv("BOOMERANG_PID");
	if (pidBuf) {
		boomerangPid = atoi(pidBuf);
		unsetenv("BOOMERANG_PID");
	}

	// Retrieve system info
	xpc_object_t xSystemInfoDict;
	if (jbclient_root_get_sysinfo(&xSystemInfoDict) != 0) return;
	SYSTEM_INFO_DESERIALIZE(xSystemInfoDict);

	// Retrieve physrw
	jbclient_root_get_physrw();
	physrw_init();

	// Retrieve kcall if available
	if (jbinfo(usesPACBypass)) {
		// TODO
	}

	// Kill boomerang and remove zombie proc if needed
	if (boomerangPid != 0) {
		kill(boomerangPid, SIGKILL);
		int boomerangStatus;
		waitpid(boomerangPid, &boomerangStatus, WEXITED);
		waitpid(boomerangPid, &boomerangStatus, 0);
	}
}
