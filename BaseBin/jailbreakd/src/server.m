#import <Foundation/Foundation.h>
#import <libjailbreak/pplrw.h>
#import <libjailbreak/kcall.h>
#import <libjailbreak/util.h>
#import <libjailbreak/jailbreakd.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/launchd.h>
#import <libjailbreak/signatures.h>
#import "trustcache.h"
#import <kern_memorystatus.h>
#import <libproc.h>
#import "JBDTCPage.h"
#import <stdint.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import "spawn_wrapper.h"


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

int processBinary(NSString *binaryPath)
{
	uint64_t selfproc = self_proc();

	FILE *machoFile = fopen(binaryPath.fileSystemRepresentation, "rb");
	if (!machoFile) return 1;
	int fd = fileno(machoFile);
	if (fd <= 0) return 1;

	bool isMacho = NO;
	bool isLibrary = NO;
	machoGetInfo(machoFile, &isMacho, &isLibrary);
	if (!isMacho) return 2;

	NSMutableArray *nonTrustCachedCDHashes = [NSMutableArray new];

	void (^tcCheckBlock)(NSString *) = ^(NSString *dependencyPath) {
		if (dependencyPath) {
			NSURL *dependencyURL = [NSURL fileURLWithPath:dependencyPath];
			NSData *cdHash = nil;
			BOOL isAdhocSigned = NO;
			evaluateSignature(dependencyURL, &cdHash, &isAdhocSigned);
			if (isAdhocSigned) {
				if (!isCdHashInTrustCache(cdHash)) {
					[nonTrustCachedCDHashes addObject:cdHash];
				}
			}
		}
	};

	tcCheckBlock(binaryPath);
	
	machoEnumerateDependencies(machoFile, binaryPath, tcCheckBlock);

	trustCacheUploadCDHashesFromArray(nonTrustCachedCDHashes);

	// Add entitlements for anything that's not a library
	if (!isLibrary) {
		int fcntlRet = loadEmbeddedSignature(machoFile);
		NSLog(@"fcntlRet: %d", fcntlRet); 
		//TODO: check if we can use the fcntlRet here somehow (performance improvements???)

		uint64_t vnode = proc_get_vnode_by_file_descriptor(selfproc, fd);
		NSMutableDictionary *vnodeEntitlements = vnode_dump_entitlements(vnode);
		if (vnodeEntitlements[@"get-task-allow"] != (__bridge id)kCFBooleanTrue) {
			vnodeEntitlements[@"get-task-allow"] = (__bridge id)kCFBooleanTrue;
			vnode_replace_entitlements(vnode, vnodeEntitlements);
		}
	}

	fclose(machoFile);
	return 0;
}

void primitivesInitializedCallback(void)
{
	tcPagesRecover();
	rebuildTrustCache();
	if (!bootInfo_getUInt64(@"launchdInitialized")) {
		// if launchd hook is not active, we want to load launch daemons now as the trustcache should be up now
		spawn(@"/var/jb/usr/bin/launchctl", @[@"bootstrap", @"system", @"/var/jb/Library/LaunchDaemons"]);
	}
}

void jailbreakd_received_message(mach_port_t machPort)
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
					primitivesInitializedCallback();
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
					xpc_object_t args = xpc_dictionary_get_value(message, "args");
					uint64_t argc = xpc_array_get_count(args);
					uint64_t argv[argc];
					for (uint64_t i = 0; i < argc; i++) {
						argv[i] = xpc_array_get_uint64(args, i);
					}
					uint64_t ret = kcall(func, argc, argv);
					xpc_dictionary_set_uint64(reply, "ret", ret);
				}
				else {
					xpc_dictionary_set_uint64(reply, "error", JBD_ERR_PRIMITIVE_NOT_INITIALIZED);
				}
				break;
			}

			case JBD_MSG_DO_KCALL_THREADSTATE: {
				if (gKCallStatus == kKcallStatusFinalized) {

					KcallThreadState threadState = { 0 };
					threadState.lr = xpc_dictionary_get_uint64(message, "lr");
					threadState.sp = xpc_dictionary_get_uint64(message, "sp");
					threadState.pc = xpc_dictionary_get_uint64(message, "pc");
					xpc_object_t xXpcArr = xpc_dictionary_get_value(message, "x");
					uint64_t xXpcCount = xpc_array_get_count(xXpcArr);
					if (xXpcCount > 29) xXpcCount = 29;
					for (uint64_t i = 0; i < xXpcCount; i++) {
						threadState.x[i] = xpc_array_get_uint64(xXpcArr, i);
					}

					bool raw = xpc_dictionary_get_bool(message, "raw");
					uint64_t ret = 0;
					if (raw) {
						ret = kcall_with_raw_thread_state(threadState);
					}
					else {
						ret = kcall_with_thread_state(threadState);
					}
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
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					rebuildTrustCache();
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
				break;
			}

			case JBD_MSG_PROCESS_BINARY: {
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					const char* filePath = xpc_dictionary_get_string(message, "filePath");
					if (filePath) {
						NSString *nsFilePath = [NSString stringWithUTF8String:filePath];
						result = processBinary(nsFilePath);
					}
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
				break;
			}

			case JBD_MSG_PROC_SET_DEBUGGED: {
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					pid_t pid = xpc_dictionary_get_int64(message, "pid");
					proc_set_debugged(pid);
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
				break;
			}

			case JBD_MSG_DEBUG_ME: {
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					proc_set_debugged(clientPid);
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
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

void jailbreakd_received_sw_message(mach_port_t machPort)
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
			NSLog(@"received system wide message %d with dictionary: %s", msgId, xpc_copy_description(message));
		}

		switch (msgId) {
			case JBD_MSG_PROCESS_BINARY: {
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					const char* filePath = xpc_dictionary_get_string(message, "filePath");
					if (filePath) {
						NSString *nsFilePath = [NSString stringWithUTF8String:filePath];
						result = processBinary(nsFilePath);
					}
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
				break;
			}
			case JBD_MSG_DEBUG_ME: {
				int64_t result = 0;
				if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
					proc_set_debugged(clientPid);
				}
				else {
					result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
				}
				xpc_dictionary_set_int64(reply, "result", result);
				break;
			}
			default:
				break;
		}
	}

	if (reply) {
		NSLog(@"responding to system wide message %d with %s", msgId, xpc_copy_description(reply));
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
		gTCAccessQueue = dispatch_queue_create("com.opa334.jailbreakd.tcAccessQueue", DISPATCH_QUEUE_SERIAL);

		mach_port_t machPort = 0;
		kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd", &machPort);
		if (kr != KERN_SUCCESS) {
			NSLog(@"Failed com.opa334.jailbreakd bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		mach_port_t machPortSystemWide = 0;
		kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd.systemwide", &machPortSystemWide);
		if (kr != KERN_SUCCESS) {
			NSLog(@"Failed com.opa334.jailbreakd.systemwide bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		if (bootInfo_getUInt64(@"launchdInitialized")) {
			NSLog(@"launchd already initialized, recovering primitives...");
			int err = launchdInitPPLRW();
			if (err == 0) {
				err = recoverPACPrimitives();
				if (err == 0) {
					primitivesInitializedCallback();
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
			mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(source);
			jailbreakd_received_message(lMachPort);
        });
        dispatch_resume(source);

		dispatch_source_t sourceSystemWide = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPortSystemWide, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(sourceSystemWide, ^{
			mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(sourceSystemWide);
			jailbreakd_received_sw_message(lMachPort);
        });
        dispatch_resume(sourceSystemWide);

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