#import <Foundation/Foundation.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/primitives.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/physrw.h>
#import <libjailbreak/jbserver_boomerang.h>

int main(int argc, char* argv[])
{
	setsid();

	__block bool launchdHasPhysrw = false;
	__block bool launchdHasKcall = false;

	mach_port_t serverPort = MACH_PORT_NULL;
	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &serverPort);
	mach_port_insert_right(mach_task_self(), serverPort, serverPort, MACH_MSG_TYPE_MAKE_SEND);

	// Boomerang server that launchd after the userspace reboot will use to recover the primitives
	dispatch_source_t serverSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)serverPort, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(serverSource, ^{
		xpc_object_t xdict = nil;
		if (!xpc_pipe_receive(serverPort, &xdict)) {
			if (jbserver_received_boomerang_xpc_message(&gBoomerangServer, xdict) == JBS_BOOMERANG_DONE) {
				exit(0);
			}
		}
	});
	dispatch_resume(serverSource);

	// When spawning, launchd should have stored a port to it's server in boomerang's registeredPorts[2]
	// Initialize jbclient with that
	mach_port_t *registeredPorts;
	mach_msg_type_number_t registeredPortsCount = 0;
	if (mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount) != 0 || registeredPortsCount < 3) return -1;
	jbclient_xpc_set_custom_port(registeredPorts[2]);

	// Stash our server port inside launchd's registeredPorts[2]
	task_t launchdTaskPort = MACH_PORT_NULL;
	kern_return_t kr = task_for_pid(mach_task_self(), 1, &launchdTaskPort);
	if (kr != KERN_SUCCESS || launchdTaskPort == MACH_PORT_NULL) return -1;
	kr = mach_ports_register(launchdTaskPort, (mach_port_t[]){ MACH_PORT_NULL, MACH_PORT_NULL, serverPort }, 3);
	if (kr != KERN_SUCCESS) return -1;
	mach_port_deallocate(mach_task_self(), launchdTaskPort);

	// Retrieve system info
	xpc_object_t xSystemInfoDict = NULL;
	if (jbclient_root_get_sysinfo(&xSystemInfoDict) != 0) return -1;
	SYSTEM_INFO_DESERIALIZE(xSystemInfoDict);

	// Retrieve physrw
	jbclient_root_get_physrw();
	libjailbreak_physrw_init();
	libjailbreak_translation_init();

	// Retrieve kcall if available
	if (jbinfo(usesPACBypass)) {
		// TODO
	}

	// Send done message to launchd
	jbclient_boomerang_done();

	// Now make our server run so that launchd can get everything back
	dispatch_main();
	return 0;
}