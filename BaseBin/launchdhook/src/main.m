#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/kcall.h>
#import <libfilecom/FCHandler.h>
#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import <mach-o/dyld.h>
#import <spawn.h>

int gLaunchdImageIndex = -1;

__attribute__((constructor)) static void initializer(void)
{
	bool comingFromUserspaceReboot = bootInfo_getUInt64(@"environmentInitialized");
	if (comingFromUserspaceReboot) {
		// Launchd was already initialized before, we are coming from a userspace reboot... recover primitives
		// First get PPLRW primitives
		dispatch_semaphore_t sema = dispatch_semaphore_create(0);
		FCHandler *handler = [[FCHandler alloc] initWithReceiveFilePath:@"/var/jb/basebin/.communication/boomerang_to_launchd" sendFilePath:@"/var/jb/basebin/.communication/launchd_to_boomerang"];
		handler.receiveHandler = ^(NSDictionary *message) {
			NSString *identifier = message[@"id"];
			if (identifier) {
				if ([identifier isEqualToString:@"receivePPLRW"])
				{
					uint64_t magicPage = [(NSNumber*)message[@"magicPage"] unsignedLongLongValue];
					initPPLPrimitives(magicPage);
					dispatch_semaphore_signal(sema);
				}
			}
		};
		[handler sendMessage:@{ @"id" : @"getPPLRW" }];
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
		recoverPACPrimitives();
		[handler sendMessage:@{ @"id" : @"primitivesInitialized" }];
		[[NSFileManager defaultManager] removeItemAtPath:@"/var/jb/basebin/.communication" error:nil];
		bootInfo_setObject(@"jbdIconCacheNeedsRefresh", @1);
	}
	else {
		// Launchd hook loaded for first time, get primitives from jailbreakd
		jbdInitPPLRW();
		recoverPACPrimitives();
	}

	for (int i = 0; i < _dyld_image_count(); i++) {
		if(!strcmp(_dyld_get_image_name(i), "/sbin/launchd")) {
			gLaunchdImageIndex = i;
			break;
		}
	}

	proc_set_debugged(getpid());
	initXPCHooks();
	initDaemonHooks();
	initSpawnHooks();
	/*if (!comingFromUserspaceReboot) {
		
	}*/

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", "/var/jb/basebin/launchdhook.dylib", 1);

	bootInfo_setObject(@"environmentInitialized", @1);
}

/*

TODO: Register for host get special port 10 in launchd
then recover primitives from jailbreakd over that
should be more stable and less prone to lockups
do this on background thread

*/