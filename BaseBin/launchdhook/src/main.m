#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import "spawn_hook.h"
#import "xpc.h"

__attribute__((constructor)) static void initializer(void)
{
	if (bootInfo_getUInt64(@"environmentInitialized")) {
		// Launchd was already initialized before, we are coming from a userspace reboot... recover primitives
		// TODO
	}
	else {
		// Launchd hook loaded for first time, get primitives from jailbreakd
		//jbdRemoteLog(3, @"getting pplrw from jbd...");
		jbdInitPPLRW();
		//jbdRemoteLog(3, @"getting PAC primitives from jbd...");
		recoverPACPrimitives();
	}
	
	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass envp to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", "/var/jb/basebin/launchdhook.dylib", 1);

	proc_set_debugged(getpid());

	initSpawnHooks();
	initXPCHooks();

	bootInfo_setObject(@"environmentInitialized", @1);
}