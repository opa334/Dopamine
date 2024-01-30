#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/util.h>
#import <libjailbreak/kernel.h>
#import <mach-o/dyld.h>
#import <spawn.h>
#import <substrate.h>

#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import "ipc_hook.h"
#import "dsc_hook.h"
#import "crashreporter.h"
#import "boomerang.h"

bool gEarlyBootDone = false;

void abort_with_reason(uint32_t reason_namespace, uint64_t reason_code, const char *reason_string, uint64_t reason_flags);

void (*org_abort)(void);
void my_abort(void)
{
	FILE *f = fopen("/var/mobile/launchd.abort.txt", "a");
	fprintf(f, "%s\n\n", [NSThread callStackSymbols].description.UTF8String);
	fclose(f);
	sleep(1);
	org_abort();
}

__attribute__((constructor)) static void initializer(void)
{
	crashreporter_start();

	bool firstLoad = false;
	if (getenv("DOPAMINE_INITIALIZED") != 0) {
		// If Dopamine was initialized before, we assume we're coming from a userspace reboot
	}
	else {
		// Here we should have been injected into a live launchd on the fly
		// In this case, we are not in early boot...
		gEarlyBootDone = true;
		firstLoad = true;
	}

	if (boomerang_recoverPrimitives(firstLoad) != 0) {
		abort_with_reason(7, 1, "Dopamine: Failed to recover primitives, cannot continue.", 0);
		return;
	}

	cs_allow_invalid(proc_self(), false);

	initXPCHooks();
	initDaemonHooks();
	initSpawnHooks();
	initIPCHooks();
	initDSCHooks();
	MSHookFunction((void *)abort, (void *)&my_abort, (void **)&org_abort);

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", JBRootPath("/basebin/launchdhook.dylib"), 1);

	// Mark Dopamine as having been initialized before
	setenv("DOPAMINE_INITIALIZED", "1", 1);

	// Set an identifier that uniquely identifies this specific userspace boot
	// Part of rootless v2 spec
	setenv("LAUNCH_BOOT_UUID", [NSUUID UUID].UUIDString.UTF8String, 1);
}