#import <Foundation/Foundation.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/util.h>
#import <libjailbreak/jailbreakd.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/launchd.h>
#import "trustcache.h"
#import <kern_memorystatus.h>
#import <libproc.h>
#import "JBDTCPage.h"
#import <stdint.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import <libproc.h>


kern_return_t bootstrap_check_in(mach_port_t bootstrap_port, const char *service, mach_port_t *server_port);

const char *verbosityString(int verbosity)
{
	switch (verbosity) {
		case 1:
		return "ERROR";
		case 2:
		return "WARNING";
		default:
		return "INFO";
	}
}

NSString *procPath(pid_t pid)
{
	char pathbuf[4*MAXPATHLEN];
	int ret = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
	if (ret <= 0) return nil;
	return [NSString stringWithUTF8String:pathbuf];
}

void PPLInitializedCallback(void)
{
	//recoverPACPrimitivesIfPossible();
}

void PACInitializedCallback(void)
{
	startTrustCacheFileListener();
}

void mach_port_callback(mach_port_t machPort)
{
	xpc_object_t message = nil;
    int err = xpc_pipe_receive(machPort, &message);
    if (err != 0) {
		NSLog(@"xpc_pipe_receive error %d", err);
        return;
    }

	xpc_object_t reply = xpc_dictionary_create_reply(message);
	xpc_type_t messageType = xpc_get_type(message);
	JBD_MESSAGE_ID msgId = -1;
	if (messageType == XPC_TYPE_DICTIONARY) {
		audit_token_t auditToken = {};
		xpc_dictionary_get_audit_token(message, &auditToken);
		uid_t clientUid = audit_token_to_euid(auditToken);
		pid_t clientPid = audit_token_to_pid(auditToken);

		msgId = xpc_dictionary_get_uint64(message, "id");

		if (msgId != JBD_MSG_REMOTELOG) {
			NSLog(@"received message %d with dictionary: %s", msgId, xpc_copy_description(message));
		}

		switch (msgId) {
			case JBD_MSG_GET_STATUS: {
				xpc_dictionary_set_uint64(reply, "pplrwStatus", gPPLRWStatus);
				xpc_dictionary_set_uint64(reply, "kcallStatus", gKCallStatus);
				break;
			}
			
			case JBD_MSG_PPL_INIT: {
				if (gPPLRWStatus == kPPLRWStatusNotInitialized) {
					uint64_t magicPage = xpc_dictionary_get_uint64(message, "magicPage");
					if (magicPage) {
						initPPLPrimitives(magicPage);
						PPLInitializedCallback();
					}
				}
				break;
			}
			
			case JBD_MSG_PAC_INIT: {
				if (gKCallStatus == kKcallStatusNotInitialized && gPPLRWStatus == kPPLRWStatusInitialized) {
					uint64_t kernelAllocation = bootInfo_getUInt64(@"jailbreakd_pac_allocation");
					if (kernelAllocation) {
						uint64_t arcContext = initPACPrimitives(kernelAllocation);
						xpc_dictionary_set_uint64(reply, "arcContext", arcContext);
					}
					break;
				}
			}
			
			case JBD_MSG_PAC_FINALIZE: {
				if (gKCallStatus == kKcallStatusPrepared && gPPLRWStatus == kPPLRWStatusInitialized) {
					finalizePACPrimitives();
					PACInitializedCallback();
				}
				break;
			}
			
			case JBD_MSG_HANDOFF_PPL: {
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					uint64_t magicPage = 0;
					int r = handoffPPLPrimitives(clientPid, &magicPage);
					if (r == 0) {
						xpc_dictionary_set_uint64(reply, "magicPage", magicPage);
					}
					else {
						xpc_dictionary_set_uint64(reply, "errorCode", r);
					}
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}
			
			case JBD_MSG_DO_KCALL: {
				if (gKCallStatus == kKcallStatusFinalized) {
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
					xpc_dictionary_set_uint64(reply, "ret", ret);
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}


			case JBD_MSG_REMOTELOG: {
				uint64_t verbosity = xpc_dictionary_get_uint64(message, "verbosity");
				const char *log = xpc_dictionary_get_string(message, "log");
				NSLog(@"[%@(%d)/%s] %s", procPath(clientPid).lastPathComponent, clientPid, verbosityString(verbosity), log);
				break;
			}


			case JBD_MSG_REBUILD_TRUSTCACHE: {
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					rebuildTrustCache();
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}
			
			case JBD_MSG_ENTITLE_VNODE: {
				//TODO
				break;
			}

			case JBD_MSG_ENTITLE_PROC: {
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					pid_t pid = xpc_dictionary_get_int64(message, "pid");
					xpc_dictionary_set_bool(reply, "success", entitle_proc(pid));
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}

			case JBD_MSG_PROC_SET_DEBUGGED: {
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					pid_t pid = xpc_dictionary_get_int64(message, "pid");
					xpc_dictionary_set_bool(reply, "success", proc_set_debugged(pid));
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}
		}
	}

	if (reply) {
		if (msgId != JBD_MSG_REMOTELOG) {
			NSLog(@"responding to message %d with %s", msgId, xpc_copy_description(reply));
		}
		err = xpc_pipe_routine_reply(reply);
		if (err != 0) {
			NSLog(@"Error %d sending response", err);
		}
	}
}

int launchdInitPPLRW(void)
{
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "jailbreak-action", LAUNCHD_JB_MSG_ID_GET_PPLRW);
	xpc_object_t reply = launchd_xpc_send_message(msg);

	int error = xpc_dictionary_get_int64(reply, "error");
	if (error == 0) {
		uint64_t magicPage = xpc_dictionary_get_uint64(reply, "magicPage");
		initPPLPrimitives(magicPage);
		return 0;
	}
	else {
		return error;
	}
}

int main(int argc, char* argv[])
{
	@autoreleasepool {
		NSLog(@"Hello from the other side!");
		gIsJailbreakd = YES;

		gTCPages = [NSMutableArray new];

		mach_port_t machPort = 0;
		kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd", &machPort);
		if (kr != KERN_SUCCESS) {
			NSLog(@"Failed bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		if (bootInfo_getUInt64(@"launchdInitialized")) {
			NSLog(@"launchd already initialized, recovering primitives...");
			int err = launchdInitPPLRW();
			if (err == 0) {
				PPLInitializedCallback();
				err = recoverPACPrimitives();
				if (err == 0) {
					PACInitializedCallback();
				}
				else {
					NSLog(@"error recovering PAC primitives: %d", err);
				}
			}
			else {
				NSLog(@"error recovering PPL primitives: %d", err);
			}
		}

		dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPort, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
			mach_port_t machPort = (mach_port_t)dispatch_source_get_handle(source);
			mach_port_callback(machPort);
        });
        dispatch_resume(source);

		dispatch_main();
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