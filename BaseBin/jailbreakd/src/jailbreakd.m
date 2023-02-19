#import <Foundation/Foundation.h>
#import "jailbreakd.h"
#import "ppl.h"
#import "pac.h"
#import "util.h"
#import "trustcache.h"
#import <kern_memorystatus.h>
#import <libproc.h>
#import "JBDTCPage.h"
#import "trustcache.h"

uint64_t gSelfProc;
uint64_t gSelfTask;

void populateGlobalVars(void)
{
	gSelfProc = proc_for_pid(getpid());
	NSLog(@"Found self proc: 0x%llX", gSelfProc);
	gSelfTask = proc_get_task(gSelfProc);
	NSLog(@"Found self task: 0x%llX", gSelfTask);
}

void PPLInitializedCallback(void)
{
	populateGlobalVars();
	//recoverPACPrimitivesIfPossible();
}

void PACInitializedCallback(void)
{
	startTrustCacheFileListener();
}

int main(int argc, char* argv[])
{
	@autoreleasepool {
		NSLog(@"Hello from the other side!");

		gTCPages = [NSMutableArray new];

		xpc_connection_t connection = xpc_connection_create_mach_service("com.opa334.jailbreakd", NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);
		if (!connection) {
			NSLog(@"Failed to create XPC server. Exiting.");
			return 0;
		}

		// Configure event handler
		xpc_connection_set_event_handler(connection, ^(xpc_object_t object)
		{
			xpc_type_t type = xpc_get_type(object);
			if (type == XPC_TYPE_CONNECTION)
			{
				xpc_object_t incomingConnection = object;
				NSLog(@"XPC server received incoming connection: %s", xpc_copy_description(incomingConnection));

				xpc_connection_set_event_handler(incomingConnection, ^(xpc_object_t message)
				{
					NSLog(@"XPC connection received message: %s", xpc_copy_description(message));

					xpc_object_t reply = xpc_dictionary_create_reply(message);
					if(reply)
					{
						if(xpc_get_type(message) == XPC_TYPE_DICTIONARY)
						{
							const char *cAction = xpc_dictionary_get_string(message, "action");
							if (cAction)
							{
								NSString *action = [NSString stringWithUTF8String:xpc_dictionary_get_string(message, "action")];
								if ([action isEqualToString:@"status"]) {
									xpc_dictionary_set_uint64(reply, "ppl-status", gPPLStatus);
									xpc_dictionary_set_uint64(reply, "pac-status", gPACStatus);
								}
								else if ([action isEqualToString:@"ppl-init"]) {
									if (gPPLStatus == kPPLStatusNotInitialized) {
										uint64_t magicPage = xpc_dictionary_get_uint64(message, "magicPage");
										initPPLPrimitives(magicPage);
									}
								}
								else if ([action isEqualToString:@"pac-init"]) {
									if (gPACStatus == kPACStatusNotInitialized && gPPLStatus == kPPLStatusInitialized) {
										uint64_t kernelAllocation = xpc_dictionary_get_uint64(message, "kernelAllocation");
										uint64_t arcContext = initPACPrimitives(kernelAllocation);
										xpc_dictionary_set_uint64(reply, "arcContext", arcContext);
									}
								}
								else if ([action isEqualToString:@"pac-finalize"]) {
									if (gPACStatus == kPACStatusPrepared && gPPLStatus == kPPLStatusInitialized) {
										finalizePACPrimitives();
									}
								}
								else if ([action isEqualToString:@"rebuild-trustcache"]) {
									rebuildTrustCache();
								}
								else if ([action isEqualToString:@"kcall"]) {
									uint64_t func = xpc_dictionary_get_uint64(message, "func");
									uint64_t a1 = xpc_dictionary_get_uint64(message, "a1");
									uint64_t a2 = xpc_dictionary_get_uint64(message, "a2");
									uint64_t a3 = xpc_dictionary_get_uint64(message, "a3");
									uint64_t a4 = xpc_dictionary_get_uint64(message, "a4");
									uint64_t a5 = xpc_dictionary_get_uint64(message, "a5");
									uint64_t a6 = xpc_dictionary_get_uint64(message, "a6");
									uint64_t a7 = xpc_dictionary_get_uint64(message, "a7");
									uint64_t a8 = xpc_dictionary_get_uint64(message, "a8");
									uint64_t ret = kcall(func, a1, a2, a3, a4, a5, a6, a7, a8);
									xpc_dictionary_set_uint64(message, "ret", ret);
								}
								else if ([action isEqualToString:@"handoff-ppl"]) {
									pid_t pid = xpc_connection_get_pid(incomingConnection);
									uint64_t magicPage;
									int r = handoffPPLPrimitives(pid, &magicPage);
									if (r == 0) {
										xpc_dictionary_set_uint64(reply, "magic-page", magicPage);
									}
									else {
										xpc_dictionary_set_int64(reply, "error-code", r);
									}
								}
							}
						}

						NSLog(@"XPC connection sending reply: %s", xpc_copy_description(reply));
						xpc_connection_send_message(xpc_dictionary_get_remote_connection(message), reply);
					}
				});
				xpc_connection_resume(incomingConnection);
			}
			else if (type == XPC_TYPE_ERROR)
			{
				NSLog(@"XPC server error: %s", xpc_dictionary_get_string(object, XPC_ERROR_KEY_DESCRIPTION));
			}
			else
			{
				NSLog(@"XPC server received unknown object: %s", xpc_copy_description(object));
			}
		});

		xpc_connection_resume(connection);

		[[NSRunLoop currentRunLoop] run];
		return 0;
	}
}

// KILL JETSAM
// Credits: https://gist.github.com/Lessica/ecfc5816467dcbaac41c50fd9074b8e9
// There is literally no other way to do it, fucking hell
static __attribute__ ((constructor(101), visibility("hidden")))
void BypassJetsam(void) {
    pid_t me = getpid();
    int rc; memorystatus_priority_properties_t props = {JETSAM_PRIORITY_CRITICAL, 0};
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES, me, 0, &props, sizeof(props));
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, me, -1, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_MANAGED, me, 0, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
    rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_FREEZABLE, me, 0, NULL, 0);
    if (rc < 0) { perror ("memorystatus_control"); exit(rc); }
    rc = proc_track_dirty(me, 0);
    if (rc != 0) { perror("proc_track_dirty"); exit(rc); }
}