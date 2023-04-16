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
#import "dyld_patch.h"
#import "update.h"
#import <sandbox.h>


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

uint64_t kernel_mount(const char* fstype, uint64_t pvp, uint64_t vp, const char *mountPath, uint64_t data, size_t datalen, int syscall_flags, uint32_t kern_flags)
{
	size_t fstype_len = strlen(fstype) + 1;
	uint64_t kern_fstype = kalloc(fstype_len);
	kwritebuf(kern_fstype, fstype, fstype_len);

	size_t mountPath_len = strlen(mountPath) + 1;
	uint64_t kern_mountPath = kalloc(mountPath_len);
	kwritebuf(kern_mountPath, mountPath, mountPath_len);

	uint64_t kernel_mount_kaddr = bootInfo_getSlidUInt64(@"kernel_mount");
	uint64_t kerncontext_kaddr = bootInfo_getSlidUInt64(@"kerncontext");

	uint64_t ret = kcall(kernel_mount_kaddr, 9, (uint64_t[]){kern_fstype, pvp, vp, kern_mountPath, data, datalen, syscall_flags, kern_flags, kerncontext_kaddr});
	kfree(kern_fstype, fstype_len);
	kfree(kern_mountPath, mountPath_len);

	return ret;
}

#define KERNEL_MOUNT_NOAUTH             0x01 /* Don't check the UID of the directory we are mounting on */
#define MNT_RDONLY      0x00000001      /* read only filesystem */

uint64_t bindMount(const char *source, const char *target)
{
	NSString *sourcePath = [[NSString stringWithUTF8String:source] stringByResolvingSymlinksInPath];
	NSString *targetPath = [[NSString stringWithUTF8String:target] stringByResolvingSymlinksInPath];

	int fd = open(sourcePath.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		JBLogError("Bind mount: Failed to open %s", sourcePath.UTF8String);
		return 1;
	}

	uint64_t vnode = proc_get_vnode_by_file_descriptor(self_proc(), fd);
	JBLogDebug("Bind mount: Got vnode 0x%llX for path \"%s\"", vnode, sourcePath.fileSystemRepresentation);

	uint64_t parent_vnode = kread_ptr(vnode + 0xC0);
	JBLogDebug("Bind mount: Got parent vnode: 0x%llX", parent_vnode);

	uint64_t mount_ret = kernel_mount("bindfs", parent_vnode, vnode, targetPath.fileSystemRepresentation, (uint64_t)targetPath.fileSystemRepresentation, 8, MNT_RDONLY, KERNEL_MOUNT_NOAUTH);
	JBLogDebug("Bind mount: kernel_mount returned %lld (%s)", mount_ret, strerror(mount_ret));
	return mount_ret;
}

void generateSystemWideSandboxExtensions(NSString *targetPath)
{
	NSMutableArray *extensions = [NSMutableArray new];

	char *extension = NULL;

	// Make /var/jb readable
	extension = sandbox_extension_issue_file("com.apple.app-sandbox.read", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Make binaries in /var/jb executable
	extension = sandbox_extension_issue_file("com.apple.sandbox.executable", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Ensure the whole system has access to com.opa334.jailbreakd.systemwide
	extension = sandbox_extension_issue_mach("com.apple.app-sandbox.mach", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];
	extension = sandbox_extension_issue_mach("com.apple.security.exception.mach-lookup.global-name", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	NSDictionary *dictToSave = @{ @"extensions" : extensions };
	[dictToSave writeToFile:targetPath atomically:NO];
}

// This did not work, what did work however was some xpcproxy hook
/*void increaseJetsamLimit(pid_t pid)
{
	memorystatus_memlimit_properties2_t mmprops;
	memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, pid, 0, &mmprops, sizeof(mmprops));

	JBLogDebug("JETSAM %d previous limit (%u/%u)", pid, mmprops.v1.memlimit_active, mmprops.v1.memlimit_inactive);

	//mmprops.v1.memlimit_active = mmprops.v1.memlimit_active * 10;
	//mmprops.v1.memlimit_inactive = mmprops.v1.memlimit_inactive * 10;

	// for whatever fucking reason it expects the v1 struct when setting but gives you the v2 struct when getting
	// don't ask me why lol
	//memorystatus_control(MEMORYSTATUS_CMD_SET_MEMLIMIT_PROPERTIES, pid, 0, &mmprops.v1, sizeof(mmprops.v1));

	//int current = getCurrentHighwatermark(pid);
	//memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, pid, current * 5, 0, 0);

	memorystatus_control(MEMORYSTATUS_CMD_GET_MEMLIMIT_PROPERTIES, pid, 0, &mmprops, sizeof(mmprops));

	JBLogDebug("JETSAM %d new limit (%u/%u)", pid, mmprops.v1.memlimit_active, mmprops.v1.memlimit_inactive);

	int rc; memorystatus_priority_properties_t props = {JETSAM_PRIORITY_CRITICAL, 0};
	rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES, pid, 0, &props, sizeof(props));
	JBLogDebug("rc %d", rc);
	rc = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK, pid, -1, NULL, 0);
	JBLogDebug("rc %d", rc);
	rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_MANAGED, pid, 0, NULL, 0);
	JBLogDebug("rc %d", rc);
	rc = memorystatus_control(MEMORYSTATUS_CMD_SET_PROCESS_IS_FREEZABLE, pid, 0, NULL, 0);
	JBLogDebug("rc %d", rc);
	rc = proc_track_dirty(pid, 0);
	JBLogDebug("rc %d", rc);
}*/

int64_t initEnvironment(NSDictionary *settings)
{
	NSString *fakeLibPath = @"/var/jb/basebin/.fakelib";
	NSString *libPath = @"/usr/lib";

	BOOL copySuc = [[NSFileManager defaultManager] copyItemAtPath:libPath toPath:fakeLibPath error:nil];
	if (!copySuc) {
		return 1;
	}
	JBLogDebug("copied %s to %s", libPath.UTF8String, fakeLibPath.UTF8String);
	
	
	
	
	int dyldRet = applyDyldPatches(@"/var/jb/basebin/.fakelib/dyld");
	if (dyldRet != 0) {
		return 1 + dyldRet;
	}
	
	NSData *dyldCDHash;
	evaluateSignature([NSURL fileURLWithPath:@"/var/jb/basebin/.fakelib/dyld"], &dyldCDHash, nil);
	if (!dyldCDHash) {
		return 5;
	}

	JBLogDebug("got dyld cd hash %s", dyldCDHash.description.UTF8String);

	size_t dyldTCSize = 0;
	uint64_t dyldTCKaddr = staticTrustCacheUploadCDHashesFromArray(@[dyldCDHash], &dyldTCSize);
	if(dyldTCSize == 0 || dyldTCKaddr == 0) {
		return 6;
	}
	bootInfo_setObject(@"dyld_trustcache_kaddr", @(dyldTCKaddr));
	bootInfo_setObject(@"dyld_trustcache_size", @(dyldTCSize));

	JBLogDebug("dyld trust cache allocated to %llX (size: %zX)", dyldTCKaddr, dyldTCSize);

	copySuc = [[NSFileManager defaultManager] copyItemAtPath:@"/var/jb/basebin/systemhook.dylib" toPath:@"/var/jb/basebin/.fakelib/systemhook.dylib" error:nil];
	if (!copySuc) {
		return 7;
	}
	JBLogDebug("copied systemhook");

	generateSystemWideSandboxExtensions(@"/var/jb/basebin/.fakelib/sandbox.plist");
	JBLogDebug("generated sandbox extensions"); 

	uint64_t bindMountRet = bindMount(libPath.fileSystemRepresentation, fakeLibPath.fileSystemRepresentation);
	
         BOOL noFonts = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/.nofonts"];
	 BOOL noLock = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/.nolock"];
	if (!noFonts) {
		NSString *fakeFontsPath = @"/var/jb/System/Library/Fonts";
		NSString *fontsPath = @"/System/Library/Fonts";
		if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/System/Library/Fonts/CoreUI"]) {
			[[NSFileManager defaultManager] removeItemAtPath:fakeFontsPath error:nil];
			[[NSFileManager defaultManager] copyItemAtPath:fontsPath toPath:fakeFontsPath error:nil];
		}
		uint64_t bindMountRetB = bindMount(fontsPath.fileSystemRepresentation, fakeFontsPath.fileSystemRepresentation);
	}
	
	if (!noLock) {
		
	NSString *fakeLockPath = @"/var/jb/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/lock@3x-896h.ca";
	NSString *lockPath = @"/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/lock@3x-896h.ca";
	 
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/System/Library/PrivateFrameworks/SpringBoardUIServices.framework"]) {
		
    		 
		[[NSFileManager defaultManager] createDirectoryAtPath:@"/var/jb/System/Library/PrivateFrameworks/SpringBoardUIServices.framework" withIntermediateDirectories:YES attributes:nil error:nil];
	}
		
	if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/lock@3x-896h.ca"]) {
		[[NSFileManager defaultManager] removeItemAtPath:fakeLockPath error:nil];
		[[NSFileManager defaultManager] copyItemAtPath:lockPath toPath:fakeLockPath error:nil];
	
	}
	
		
		 
	}
 
	
	if (bindMountRet != 0   ) {
		return 8;
	}

	return 0;
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
									msgId == JBD_MSG_SETUID_FIX;

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

					case JBD_MSG_INIT_ENVIRONMENT: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							result = initEnvironment(nil);
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
					}

					case JBD_MSG_JBUPDATE: {
						int64_t result = 0;
						if (gPPLRWStatus == kPPLRWStatusInitialized && gKCallStatus == kKcallStatusFinalized) {
							const char *basebinPath = xpc_dictionary_get_string(message, "basebinPath");
							const char *tipaPath = xpc_dictionary_get_string(message, "tipaPath");

							if (basebinPath) {
								result = basebinUpdateFromTar([NSString stringWithUTF8String:basebinPath]);
							}
							else if (tipaPath) {
								result = jbUpdateFromTIPA([NSString stringWithUTF8String:tipaPath]);
							}
							else {
								result = 101;
							}
						}
						else {
							result = JBD_ERR_PRIMITIVE_NOT_INITIALIZED;
						}
						xpc_dictionary_set_int64(reply, "result", result);
						break;
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

int launchdInitPPLRW(void)
{
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "id", LAUNCHD_JB_MSG_ID_GET_PPLRW);
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
		JBLogDebug("Hello from the other side!");
		gIsJailbreakd = YES;

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
				spawn(@"/var/jb/usr/bin/uicache", @[@"-a"]);
				bootInfo_setObject(@"jbdIconCacheNeedsRefresh", nil);
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
