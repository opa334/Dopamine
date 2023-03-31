#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/kcall.h>
#import <libfilecom/FCHandler.h>
#import "spawn_hook.h"
#import "xpc_hook.h"
#import "boot_task_hook.h"
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
	initSpawnHooks();
	initXPCHooks();
	if (comingFromUserspaceReboot) {
		initBootTaskHooks();
	}

	if (comingFromUserspaceReboot) {
		/*dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			while (1) {
				extern int (*posix_spawn_orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]);
				pid_t task_pid;
				int status = -200;
				char *argv[] = {"reinit", NULL};
				int spawnError = posix_spawn_orig(&task_pid, "/var/jb/basebin/jbinit", NULL, NULL, argv, NULL);
				do {
					if (waitpid(task_pid, &status, 0) == -1) {
						return;
					}
				} while (!WIFEXITED(status) && !WIFSIGNALED(status));
			}
		});*/
	}

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", "/var/jb/basebin/launchdhook.dylib", 1);

	bootInfo_setObject(@"environmentInitialized", @1);
}