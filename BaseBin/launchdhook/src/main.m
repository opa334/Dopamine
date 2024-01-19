#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/util.h>
#import <libjailbreak/kernel.h>
#import <mach-o/dyld.h>
#import <spawn.h>

#import "spawn_hook.h"
#import "xpc_hook.h"
#import "daemon_hook.h"
#import "ipc_hook.h"
#import "dsc_hook.h"
#import "crashreporter.h"
#import "boomerang.h"

__attribute__((constructor)) static void initializer(void)
{
	crashreporter_start();

	if (boomerang_recoverPrimitives() != 0) return; // TODO: userspace panic?

	cs_allow_invalid(proc_self(), false);

	initXPCHooks();
	initDaemonHooks();
	initSpawnHooks();
	initIPCHooks();
	initDSCHooks();

	// This will ensure launchdhook is always reinjected after userspace reboots
	// As this launchd will pass environ to the next launchd...
	setenv("DYLD_INSERT_LIBRARIES", JBRootPath("/basebin/launchdhook.dylib"), 1);
}