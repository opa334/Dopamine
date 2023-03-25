#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import "boomerang.h"
#import "spawn_hook.h"
#import "xpc.h"

__attribute__((constructor)) static void initializer(void)
{
	if (bootInfo_getUInt64(@"launchdInitialized")) {
		// Launchd was already initialized before, we are coming from a userspace reboot... recover primitives
		// TODO
	}
	else {
		// Launchd hook loaded for first time, get primitives from jailbreakd
		//jbdRemoteLog(3, @"getting pplrw from jbd...");
		jbdInitPPLRW();
		//jbdRemoteLog(3, @"getting PAC primitives from jbd...");
		recoverPACPrimitives();
		bootInfo_setObject(@"launchdInitialized", @1);
	}

	proc_set_debugged(getpid());
	
	initBoomerangHooks();
	initSpawnHooks();
	initXPCHooks();
}