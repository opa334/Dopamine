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
	FILE *launchdLog = fopen("/var/mobile/launchd.log", "a");
	fprintf(launchdLog, "Hello from launchd\n"); fflush(launchdLog);

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
					fprintf(launchdLog, "Boomerang responded\n"); fflush(launchdLog);
					boomerangPid = [(NSNumber*)message[@"boomerangPid"] intValue];
					initPPLPrimitives();
					fprintf(launchdLog, "Initialized PPLRW\n"); fflush(launchdLog);
					dispatch_semaphore_signal(sema);
				}
			}
		};
		fprintf(launchdLog, "Contacting boomerang to get back PPLRW\n"); fflush(launchdLog);
		[handler sendMessage:@{ @"id" : @"getPPLRW" }];
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
		fprintf(launchdLog, "Recovering PAC primitives...\n"); fflush(launchdLog);
		recoverPACPrimitives();
		fprintf(launchdLog, "Recovered PAC primitives!\n"); fflush(launchdLog);
		[handler sendMessage:@{ @"id" : @"primitivesInitialized" }];
		fprintf(launchdLog, "Cleaning up boomerang...\n"); fflush(launchdLog);
		[[NSFileManager defaultManager] removeItemAtPath:prebootPath(@"basebin/.communication") error:nil];
		if (boomerangPid != 0) {
			int status;
			waitpid(boomerangPid, &status, WEXITED);
			waitpid(boomerangPid, &status, 0);
		}
		fprintf(launchdLog, "Cleaned up boomerang!\n"); fflush(launchdLog);
		bootInfo_setObject(@"jbdIconCacheNeedsRefresh", @1);
	}
	else {
		// Launchd hook loaded for first time, get primitives from jailbreakd
		fprintf(launchdLog, "Getting PPLRW from jailbreakd...\n"); fflush(launchdLog);
		jbdInitPPLRW();
		fprintf(launchdLog, "Got PPLRW from jailbreakd!\n"); fflush(launchdLog);
		fprintf(launchdLog, "Recovering kcall...\n"); fflush(launchdLog);
		recoverPACPrimitives();
		fprintf(launchdLog, "Recovered kcall!\n"); fflush(launchdLog);
	}

	fprintf(launchdLog, "Finding launchd image index...\n"); fflush(launchdLog);
	for (int i = 0; i < _dyld_image_count(); i++) {
		if(!strcmp(_dyld_get_image_name(i), "/sbin/launchd")) {
			gLaunchdImageIndex = i;
			break;
		}
	}
	fprintf(launchdLog, "Found launchd image index: %d...!\n", gLaunchdImageIndex); fflush(launchdLog);

	fprintf(launchdLog, "Setting Sandbox / RootPath environment variables...\n"); fflush(launchdLog);
	// System wide sandbox extensions and root path
	setenv("JB_SANDBOX_EXTENSIONS", generateSystemWideSandboxExtensions().UTF8String, 1);
	setenv("JB_ROOT_PATH", prebootPath(nil).fileSystemRepresentation, 1);
	JB_SandboxExtensions = strdup(getenv("JB_SANDBOX_EXTENSIONS"));
	JB_RootPath = strdup(getenv("JB_ROOT_PATH"));
	fprintf(launchdLog, "Set Sandbox / RootPath environment variables!\n"); fflush(launchdLog);

	fprintf(launchdLog, "Setting launchd as debugged...\n"); fflush(launchdLog);
	proc_set_debugged_pid(getpid(), false);
	fprintf(launchdLog, "Set launchd as debugged!\n"); fflush(launchdLog);
	
	
	fprintf(launchdLog, "Initializing XPC hooks...\n"); fflush(launchdLog);
	initXPCHooks();
	fprintf(launchdLog, "Initializing daemon hooks...\n"); fflush(launchdLog);
	initDaemonHooks();
	fprintf(launchdLog, "Initializing spawn hooks...\n"); fflush(launchdLog);
	initSpawnHooks();
	fprintf(launchdLog, "Initializing IPC hooks...\n"); fflush(launchdLog);
	initIPCHooks();

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", prebootPath(@"basebin/launchdhook.dylib").fileSystemRepresentation, 1);

	bootInfo_setObject(@"environmentInitialized", @1);
	fprintf(launchdLog, "Done for now\n"); fflush(launchdLog);
	fclose(launchdLog);
}