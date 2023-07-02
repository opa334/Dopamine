#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/boot_info.h>
#import <libjailbreak/launchd.h>
#import <libjailbreak/signatures.h>
#import <libjailbreak/macho.h>
#import "trustcache.h"
#import <kern_memorystatus.h>
#import <libproc.h>
#import "JBDTCPage.h"
#import <stdint.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import "spawn_wrapper.h"
#import "server.h"
#import "fakelib.h"
#import "update.h"
#import "forkfix.h"

kern_return_t bootstrap_check_in(mach_port_t bootstrap_port, const char *service, mach_port_t *server_port);
SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

void setJetsamEnabled(bool enabled)
{
	pid_t me = getpid();
	int priorityToSet = -1;
	if (enabled) {
		priorityToSet = 10;
	}
	int rc = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, me, priorityToSet, NULL, 0);
	if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
}

void setTweaksEnabled(bool enabled)
{
	NSString *safeModePath = prebootPath(@"basebin/.safe_mode");
	if (enabled) {
		[[NSFileManager defaultManager] removeItemAtPath:safeModePath error:nil];
	}
	else {
		[[NSFileManager defaultManager] createFileAtPath:safeModePath contents:[NSData data] attributes:nil];
	}
}

int processBinary(NSString *binaryPath)
{
	if (!binaryPath) return 0;
	if (![[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) return 0;

	int ret = 0;

	uint64_t selfproc = self_proc();

	FILE *machoFile = fopen(binaryPath.fileSystemRepresentation, "rb");
	if (!machoFile) return 1;

	if (machoFile) {
		int fd = fileno(machoFile);

		bool isMacho = NO;
		bool isLibrary = NO;
		machoGetInfo(machoFile, &isMacho, &isLibrary);

		if (isMacho) {
			int64_t bestArchCandidate = machoFindBestArch(machoFile);
			if (bestArchCandidate >= 0) {
				uint32_t bestArch = bestArchCandidate;
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
				
				machoEnumerateDependencies(machoFile, bestArch, binaryPath, tcCheckBlock);

				dynamicTrustCacheUploadCDHashesFromArray(nonTrustCachedCDHashes);
			}
			else {
				ret = 3;
			}
		}
		else {
			ret = 2;
		}
		fclose(machoFile);
	}
	else {
		ret = 1;
	}

	return ret;
}

int launchdInitPPLRW(void)
{
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "id", LAUNCHD_JB_MSG_ID_GET_PPLRW);
	xpc_object_t reply = launchd_xpc_send_message(msg);
	if (!reply) return -1;

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

bool boolValueForEntitlement(audit_token_t *token, const char *entitlement)
{
	xpc_object_t entitlementValue = xpc_copy_entitlement_for_token(entitlement, token);
	if (entitlementValue) {
		if (xpc_get_type(entitlementValue) == XPC_TYPE_BOOL) {
			return xpc_bool_get_value(entitlementValue);
		}
	}
	return false;
}

void dumpUserspacePanicLog(const char *message)
{
	time_t t = time(NULL);
	struct tm *tm = localtime(&t);
	char timestamp[20];
	strftime(timestamp, sizeof(timestamp), "%Y-%m-%d_%H-%M-%S", tm);

	char panicPath[PATH_MAX];
	strcpy(panicPath, "/var/mobile/Library/Logs/CrashReporter/userspace-panic-");
	strcat(panicPath, timestamp);
	strcat(panicPath, ".ips");

	FILE * f = fopen(panicPath, "w");
	if (f) {
		fprintf(f, "%s", message);
		fprintf(f, "\n\nThis panic was prevented by Dopamine and jailbreakd triggered a userspace reboot instead.");
		fclose(f);
		chown(panicPath, 0, 250);
		chmod(panicPath, 0660);
	}
}

void jailbreakd_received_message(mach_port_t machPort, bool systemwide)
{
	@autoreleasepool {
		xpc_object_t message = nil;
		int err = xpc_pipe_receive(machPort, &message);
		if (err != 0) {
			JBLogError("xpc_pipe_receive error %d", err);
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

			char *description = xpc_copy_description(message);
			JBLogDebug("received %s message %d with dictionary: %s", systemwide ? "systemwide" : "", msgId, description);
			free(description);

			BOOL isAllowedSystemWide = msgId == JBD_MSG_PROCESS_BINARY || 
									msgId == JBD_MSG_DEBUG_ME ||
									msgId == JBD_MSG_SETUID_FIX ||
									msgId == JBD_MSG_FORK_FIX ||
									msgId == JBD_MSG_INTERCEPT_USERSPACE_PANIC;

			if (!systemwide || isAllowedSystemWide) {
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
								@autoreleasepool {
									argv[i] = xpc_array_get_uint64(args, i);
								}
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
								@autoreleasepool {
									threadState.x[i] = xpc_array_get_uint64(xXpcArr, i);
								}
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

					case JBD_MSG_INIT_ENVIRONMENT: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							result = makeFakeLib();
							if (result == 0) {
								result = setFakeLibBindMountActive(true);
							}
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}

					case JBD_MSG_JBUPDATE: {
						dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
							int64_t result = 0;
							if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
								const char *basebinPath = xpc_dictionary_get_string(message, "basebinPath");
								const char *tipaPath = xpc_dictionary_get_string(message, "tipaPath");
								bool rebootWhenDone = xpc_dictionary_get_bool(message, "rebootWhenDone");

								if (basebinPath) {
									result = basebinUpdateFromTar([NSString stringWithUTF8String:basebinPath], rebootWhenDone);
								}
								else if (tipaPath) {
									result = jbUpdateFromTIPA([NSString stringWithUTF8String:tipaPath], rebootWhenDone);
								}
								else {
									result = 101;
								}
							}
							else {
								result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
							}
							xpc_dictionary_set_int64(reply, "result", result);
							xpc_pipe_routine_reply(reply);
						});
						return;
					}


					case JBD_MSG_REBUILD_TRUSTCACHE: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							rebuildDynamicTrustCache();
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}

					case JBD_MSG_SETUID_FIX: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized) {
							proc_fix_setuid(clientPid);
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
							result = proc_set_debugged_pid(pid, true);
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
							result = proc_set_debugged_pid(clientPid, false);
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}

					case JBD_MSG_FORK_FIX: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							pid_t childPid = xpc_dictionary_get_int64(message, "childPid");
							result = apply_fork_fixup(clientPid, childPid);
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}

					case JBD_MSG_INTERCEPT_USERSPACE_PANIC: {
						int64_t result = 0;
						const char *messageString = xpc_dictionary_get_string(message, "message");
						if (boolValueForEntitlement(&auditToken, "com.apple.private.iowatchdog.user-access") == true) {
							if (messageString) {
								dumpUserspacePanicLog(messageString);
							}
							setTweaksEnabled(false);
							bootInfo_setObject(@"jbdShowUserspacePanicMessage", @1);
							reboot3(RB2_USERREBOOT);
						}
						xpc_dictionary_set_int64(reply, "result", result);
					}

					case JBD_SET_FAKELIB_VISIBLE: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							bool visible = xpc_dictionary_get_bool(message, "visible");
							result = setFakeLibVisible(visible);
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}
				}
			}
		}
		if (reply) {
			char *description = xpc_copy_description(reply);
			JBLogDebug("responding to %s message %d with %s", systemwide ? "systemwide" : "", msgId, description);
			free(description);
			err = xpc_pipe_routine_reply(reply);
			if (err != 0) {
				JBLogError("Error %d sending response", err);
			}
		}
	}
}

int main(int argc, char* argv[])
{
	@autoreleasepool {
		JBLogDebug("Hello from the other side!");
		gIsJailbreakd = YES;

		setJetsamEnabled(true);

		gTCPages = [NSMutableArray new];
		gTCUnusedAllocations = [NSMutableArray new];
		gTCAccessQueue = dispatch_queue_create("com.opa334.jailbreakd.tcAccessQueue", DISPATCH_QUEUE_SERIAL);

		mach_port_t machPort = 0;
		kern_return_t kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd", &machPort);
		if (kr != KERN_SUCCESS) {
			JBLogError("Failed com.opa334.jailbreakd bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		mach_port_t machPortSystemWide = 0;
		kr = bootstrap_check_in(bootstrap_port, "com.opa334.jailbreakd.systemwide", &machPortSystemWide);
		if (kr != KERN_SUCCESS) {
			JBLogError("Failed com.opa334.jailbreakd.systemwide bootstrap check in: %d (%s)", kr, mach_error_string(kr));
			return 1;
		}

		if (bootInfo_getUInt64(@"environmentInitialized")) {
			JBLogDebug("launchd already initialized, recovering primitives...");
			int err = launchdInitPPLRW();
			if (err == 0) {
				err = recoverPACPrimitives();
				if (err == 0) {
					tcPagesRecover();
				}
				else {
					JBLogError("error recovering PAC primitives: %d", err);
				}
			}
			else {
				JBLogError("error recovering PPL primitives: %d", err);
			}
		}

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if (bootInfo_getUInt64(@"jbdIconCacheNeedsRefresh")) {
				spawn(prebootPath(@"usr/bin/uicache"), @[@"-a"]);
				bootInfo_setObject(@"jbdIconCacheNeedsRefresh", nil);
			}

			if (bootInfo_getUInt64(@"jbdShowUserspacePanicMessage")) {
				CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), CFSTR("Dopamine has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A detailed log is available under Analytics in the Preferences app. You can reenable tweak injection in the Dopamine app."), NULL, NULL, NULL, NULL);
				bootInfo_setObject(@"jbdShowUserspacePanicMessage", nil);
			}
		});

		dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPort, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(source, ^{
			mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(source);
			jailbreakd_received_message(lMachPort, false);
		});
		dispatch_resume(source);

		dispatch_source_t sourceSystemWide = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)machPortSystemWide, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(sourceSystemWide, ^{
			mach_port_t lMachPort = (mach_port_t)dispatch_source_get_handle(sourceSystemWide);
			jailbreakd_received_message(lMachPort, true);
		});
		dispatch_resume(sourceSystemWide);

		dispatch_main();
		return 0;
	}
}
