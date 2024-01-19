#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <mach-o/dyld.h>
#import <spawn.h>

#import <sandbox.h>
#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import "ipc_hook.h"
#import "dsc_hook.h"
#import "crashreporter.h"
#import "boomerang.h"

int gLaunchdImageIndex = -1;

NSString *generateSystemWideSandboxExtensions(void)
{
	NSMutableString *extensionString = [NSMutableString new];

	// Make /var/jb readable
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_file("com.apple.app-sandbox.read", jbinfo(rootPath), 0)]];
	[extensionString appendString:@"|"];

	// Make binaries in /var/jb executable
	[extensionString appendString:[NSString stringWithUTF8String:sandbox_extension_issue_file("com.apple.sandbox.executable", jbinfo(rootPath), 0)]];
	[extensionString appendString:@"|"];

	return extensionString;
}

__attribute__((constructor)) static void initializer(void)
{
	FILE *f = fopen("/var/mobile/launchd_new.log", "a");
	fprintf(f, "WE OUT HERE! launchd gang!\n");
	fflush(f);

	crashreporter_start();

	fprintf(f, "crashreporter started\n");
	fflush(f);

	int r = boomerang_recoverPrimitives();
	if (r == 0) {
		fprintf(f, "Primitives recovered!\n");
		fprintf(f, "Test read: 0x%x\n", kread32(kconstant(base)));
		fflush(f);
	}
	else {
		fprintf(f, "Failed to recover primitives: %d\n", r);
		fclose(f);
		return;
	}

	for (int i = 0; i < _dyld_image_count(); i++) {
		if(!strcmp(_dyld_get_image_name(i), "/sbin/launchd")) {
			gLaunchdImageIndex = i;
			break;
		}
	}
	// System wide sandbox extensions and root path
	//setenv("JB_SANDBOX_EXTENSIONS", generateSystemWideSandboxExtensions().UTF8String, 1);
	//JB_SandboxExtensions = strdup(getenv("JB_SANDBOX_EXTENSIONS"));

	//proc_set_debugged_pid(getpid(), false);

	/*initXPCHooks();
	initDaemonHooks();
	initSpawnHooks();
	initIPCHooks();
	initDSCHooks();*/

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", JBRootPath("basebin/launchdhook.dylib"), 1);
	fclose(f);
}