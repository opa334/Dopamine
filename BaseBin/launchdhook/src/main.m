#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/launchd.h>
#import <libfilecom/FCHandler.h>
#import <mach-o/dyld.h>
#import <spawn.h>

#import <sandbox.h>
#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import "ipc_hook.h"
#import "crashreporter.h"
#import "../systemhook/src/common.h"

int gLaunchdImageIndex = -1;

NSString *generateSystemWideSandboxExtensions(void)
{
	NSMutableString *extensionString = [NSMutableString new];

	// Make /var/jb readable
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_file("com.apple.app-sandbox.read", prebootPath(nil).fileSystemRepresentation, 0)]];
	[extensionString appendString:@"|"];

	// Make binaries in /var/jb executable
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_file("com.apple.sandbox.executable", prebootPath(nil).fileSystemRepresentation, 0)]];
	[extensionString appendString:@"|"];

	// Ensure the whole system has access to com.opa334.jailbreakd.systemwide
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_mach("com.apple.app-sandbox.mach", "com.opa334.jailbreakd.systemwide", 0)]];
	[extensionString appendString:@"|"];
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_mach("com.apple.security.exception.mach-lookup.global-name", "com.opa334.jailbreakd.systemwide", 0)]];

	return extensionString;
}

__attribute__((constructor)) static void initializer(void)
{
	crashreporter_start();
	bool comingFromUserspaceReboot = bootInfo_getUInt64(@"environmentInitialized");
	if (comingFromUserspaceReboot) {

		// super hacky fix to support OTA updates from 1.0.x to 1.1
		// I hate it, but there is no better way :/
		NSURL *disabledLaunchDaemonURL = [NSURL fileURLWithPath:prebootPath(@"basebin/LaunchDaemons/Disabled") isDirectory:YES];
		NSArray<NSURL *> *disabledLaunchDaemonPlistURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:disabledLaunchDaemonURL includingPropertiesForKeys:nil options:0 error:nil];
		for (NSURL *disabledLaunchDaemonPlistURL in disabledLaunchDaemonPlistURLs) {
			patchBaseBinLaunchDaemonPlist(disabledLaunchDaemonPlistURL.path);
		}

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
					boomerangPid = [(NSNumber*)message[@"boomerangPid"] intValue];
					initPPLPrimitives();
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
	// System wide sandbox extensions and root path
	setenv("JB_SANDBOX_EXTENSIONS", generateSystemWideSandboxExtensions().UTF8String, 1);
	setenv("JB_ROOT_PATH", prebootPath(nil).fileSystemRepresentation, 1);
	JB_SandboxExtensions = strdup(getenv("JB_SANDBOX_EXTENSIONS"));
	JB_RootPath = strdup(getenv("JB_ROOT_PATH"));

	proc_set_debugged_pid(getpid(), false);
	
	
	initXPCHooks();
	initDaemonHooks();
	initSpawnHooks();
	initIPCHooks();

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", prebootPath(@"basebin/launchdhook.dylib").fileSystemRepresentation, 1);

	bootInfo_setObject(@"environmentInitialized", @1);
}