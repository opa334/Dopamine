#import <Foundation/Foundation.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/util.h>
#import <libjailbreak/jailbreakd.h>
#import <libjailbreak/handoff.h>
#import "trustcache.h"
#import <kern_memorystatus.h>
#import <libproc.h>
#import "JBDTCPage.h"
#import <stdint.h>

kern_return_t bootstrap_check_in(mach_port_t bootstrap_port, const char *service, mach_port_t *server_port);


void PPLInitializedCallback(void)
{
	//recoverPACPrimitivesIfPossible();
}

void PACInitializedCallback(void)
{
	startTrustCacheFileListener();
}

uint64_t jbdParseNumUInt64(NSNumber *num)
{
	if ([num isKindOfClass:NSNumber.class]) {
		return num.unsignedLongLongValue;
	}
	return 0;
}

pid_t get_port_owner_pid(mach_port_t port) {
    mach_port_t owner;
    mach_port_status_t status;
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    kern_return_t kr = mach_port_get_attributes(mach_task_self(), port, MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &count);
    if (kr != KERN_SUCCESS) {
        printf("Error: mach_port_get_attributes() failed with error %d\n", kr);
        return -1;
    }
    return status.mps_pset;
}

void mach_port_callback(CFMachPortRef port, void *msgV, CFIndex size, void *info)
{
	mach_msg_header_t *msg = (mach_msg_header_t *)msgV;
	mach_port_t client_port = msg->msgh_remote_port;
	pid_t clientPid = get_port_owner_pid(client_port);

	NSMutableDictionary *responseDict = [NSMutableDictionary new];

	NSDictionary *msgDict = jbdDecodeMessage(msg);
	if (msgDict) {
		NSLog(@"received message %d with dictionary: %@", msg->msgh_id, msgDict);

		switch (msg->msgh_id) {
			case JBD_MSG_GET_STATUS: {
				responseDict[@"PPLRWStatus"] = @(gPPLRWStatus);
				responseDict[@"kcallStatus"] = @(gKCallStatus);
				responseDict[@"pid"] = @(getpid());
				break;
			}
			
			case JBD_MSG_PPL_INIT: {
				if (gPPLRWStatus == kPPLRWStatusNotInitialized) {
					uint64_t magicPage = jbdParseNumUInt64(msgDict[@"magicPage"]);
					if (magicPage) {
						initPPLPrimitives(magicPage);
						PPLInitializedCallback();
					}
				}
				break;
			}
			
			case JBD_MSG_PAC_INIT: {
				if (gKCallStatus == kKcallStatusNotInitialized && gPPLRWStatus == kPPLRWStatusInitialized) {
					uint64_t kernelAllocation = jbdParseNumUInt64(msgDict[@"kernelAllocation"]);
					if (kernelAllocation) {
						uint64_t arcContext = initPACPrimitives(kernelAllocation);
						responseDict[@"arcContext"] = @(arcContext);
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
				uint64_t magicPage = 0;
				int r = handoffPPLPrimitives(clientPid, &magicPage);
				if (r == 0) {
					responseDict[@"magicPage"] = @(magicPage);
				}
				else {
					responseDict[@"errorCode"] = @(r);
				}
				break;
			}
			
			
			case JBD_MSG_KCALL: {
				uint64_t func = jbdParseNumUInt64(msgDict[@"func"]);
				uint64_t a1 = jbdParseNumUInt64(msgDict[@"a1"]);
				uint64_t a2 = jbdParseNumUInt64(msgDict[@"a2"]);
				uint64_t a3 = jbdParseNumUInt64(msgDict[@"a3"]);
				uint64_t a4 = jbdParseNumUInt64(msgDict[@"a4"]);
				uint64_t a5 = jbdParseNumUInt64(msgDict[@"a5"]);
				uint64_t a6 = jbdParseNumUInt64(msgDict[@"a6"]);
				uint64_t a7 = jbdParseNumUInt64(msgDict[@"a7"]);
				uint64_t a8 = jbdParseNumUInt64(msgDict[@"a8"]);
				uint64_t ret = kcall(func, a1, a2, a3, a4, a5, a6, a7, a8);
				responseDict[@"ret"] = @(ret);
				break;
			}
			

			case JBD_MSG_REBUILD_TRUSTCACHE: {
				rebuildTrustCache();
				break;
			}
			
			case JBD_MSG_UNRESTRICT_VNODE: {
				//TODO
				break;
			}

			case JBD_MSG_UNRESTRICT_PROC: {
				pid_t pid = jbdParseNumUInt64(msgDict[@"pid"]);
				uint64_t proc = proc_for_pid(pid);
				if (proc != 0) {
					NSMutableDictionary *entitlements = proc_dump_entitlements(proc);
					entitlements[@"get-task-allow"] = (__bridge id)kCFBooleanTrue;
					//entitlements[@"run-invalid-allow"] = (__bridge id)kCFBooleanTrue;
					//entitlements[@"run-unsigned-code"] = (__bridge id)kCFBooleanTrue;
					proc_replace_entitlements(proc, entitlements);
					bool success = cs_allow_invalid(proc);
					responseDict[@"success"] = @(success);
				}
				break;
			}
		}
	}

	if (responseDict) {
		NSLog(@"responding to message %d with %@", msg->msgh_id, responseDict);

		mach_msg_header_t *responseMsg = malloc(0x1000);
		memset(responseMsg, 0, 0x1000);
		jbdEncodeMessage(responseMsg, responseDict, 0x1000);
		responseMsg->msgh_bits = msg->msgh_bits & MACH_MSGH_BITS_REMOTE_MASK;
		responseMsg->msgh_remote_port = client_port;
		responseMsg->msgh_local_port = MACH_PORT_NULL;
		responseMsg->msgh_id = msg->msgh_id;

		kern_return_t kr = mach_msg(responseMsg, MACH_SEND_MSG, responseMsg->msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
		if (kr != KERN_SUCCESS) {
			NSLog(@"error sending response message: %d (%s)", kr, mach_error_string(kr));
		}

		free(responseMsg);
	}
}

int main(int argc, char* argv[])
{
	@autoreleasepool {
		NSLog(@"Hello from the other side!");

		gTCPages = [NSMutableArray new];

		mach_port_t machPort = 0;
		kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd", &machPort);
		if (kr != KERN_SUCCESS) {
			NSLog(@"Failed bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		CFMachPortRef cfMachPort = CFMachPortCreateWithPort(NULL, machPort, mach_port_callback, NULL, NULL);

		CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, cfMachPort, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);

		mach_port_t port = 15;
		mach_port_t bootstrapPort;
		task_get_bootstrap_port(mach_task_self(), &bootstrapPort);

		mach_port_insert_right(mach_task_self(), port, machPort, MACH_MSG_TYPE_MAKE_SEND);

		CFRunLoopRun();
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