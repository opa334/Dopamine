#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import "boomerang.h"
#import "xpc.h"

__attribute__((constructor)) static void initializer(void)
{
	dispatch_async(dispatch_get_main_queue(), ^(void){
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
		initXPCHooks();
	});
}