#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <mach-o/dyld.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import <sandbox.h>
#import "substrate.h"
#import <libjailbreak/jbserver.h>

/*#undef JBLogDebug
void JBLogDebug(const char *format, ...)
{
	va_list va;
	va_start(va, format);

	FILE *launchdLog = fopen("/var/mobile/launchd-xpc.log", "a");
	vfprintf(launchdLog, format, va);
	fprintf(launchdLog, "\n");
	fclose(launchdLog);

	va_end(va);	
}*/

int xpc_receive_mach_msg(void *a1, void *a2, void *a3, void *a4, xpc_object_t *xOut);
int (*xpc_receive_mach_msg_orig)(void *a1, void *a2, void *a3, void *a4, xpc_object_t *xOut);
int xpc_receive_mach_msg_hook(void *a1, void *a2, void *a3, void *a4, xpc_object_t *xOut)
{
	int r = xpc_receive_mach_msg_orig(a1, a2, a3, a4, xOut);
	if (r == 0) {
		if (jbserver_received_xpc_message(&gGlobalServer, *xOut) == 0) {
			// Returning non null here makes launchd disregard this message
			// For jailbreak messages we have the logic to handle them
			return 22;
		}
	}
	return r;
}

void initXPCHooks(void)
{
	MSHookFunction(xpc_receive_mach_msg, (void *)xpc_receive_mach_msg_hook, (void **)&xpc_receive_mach_msg_orig);
}
