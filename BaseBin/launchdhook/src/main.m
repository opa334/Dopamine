#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/kcall.h>
#import <libfilecom/FCHandler.h>
#import <mach-o/dyld.h>
#import <spawn.h>

#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import "ipc_hook.h"

int gLaunchdImageIndex = -1;

__attribute__((constructor)) static void initializer(void)
{
	bool comingFromUserspaceReboot = bootInfo_getUInt64(@"environmentInitialized");
	if (comingFromUserspaceReboot) {
		// Launchd was already initialized before, we are coming from a userspace reboot... recover primitives
		// First get PPLRW primitives
		__block pid_t boomerangPid = 0;
		dispatch_semaphore_t sema = dispatch_semaphore_create(0);
		FCHandler *handler = [[FCHandler alloc] initWithReceiveFilePath:prebootPath(@"basebin/.communication/boomerang_to_launchd") sendFilePath:prebootPath(@"basebin/.communication/launchd_to_boomerang")];
		handler.receiveHandler = ^(NSDictionary *message) {
			NSString *identifier = message[@"id"];
			if (identifier) {
				if ([identifier isEqualToString:@"receivePPLRW"])
				{
					uint64_t magicPage = [(NSNumber*)message[@"magicPage"] unsignedLongLongValue];
					boomerangPid = [(NSNumber*)message[@"boomerangPid"] intValue];
					initPPLPrimitives(magicPage);
					dispatch_semaphore_signal(sema);
				}
			}
		};
		[handler sendMessage:@{ @"id" : @"getPPLRW" }];
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
		recoverPACPrimitives();
		[handler sendMessage:@{ @"id" : @"primitivesInitialized" }];
		[[NSFileManager defaultManager] removeItemAtPath:prebootPath(@"basebin/.communication") error:nil];
		if (boomerangPid != 0) {
			int status;
			waitpid(boomerangPid, &status, WEXITED);
			waitpid(boomerangPid, &status, 0);
		}
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
	initIPCHooks();

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", prebootPath(@"basebin/launchdhook.dylib").fileSystemRepresentation, 1);

	bootInfo_setObject(@"environmentInitialized", @1);
}