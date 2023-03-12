#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/launchd.h>
#import <mach-o/dyld.h>
#import <xpc/xpc.h>
#import <bsm/libbsm.h>
#import <libproc.h>
#import "substrate.h"

NSString *procPath(pid_t pid)
{
	char pathbuf[4*MAXPATHLEN];
	int ret = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
	if (ret <= 0) return nil;
	return [NSString stringWithUTF8String:pathbuf];
}

// Server routine to make jailbreakd able to get back primitives when it restarts
void (*xpc_handler_orig)(uint64_t a1, uint64_t a2, xpc_object_t xdict);
void xpc_handler_replacement(uint64_t a1, uint64_t a2, xpc_object_t xdict)
{
	if (xdict) {
		if (xpc_get_type(xdict) == XPC_TYPE_DICTIONARY) {
			//jbdRemoteLog(3, @"launchd server got dictionary: %s", xpc_copy_description(xdict));
			bool jbRelated = xpc_dictionary_get_bool(xdict, "jailbreak");
			if (jbRelated) {
				audit_token_t auditToken = {};
				xpc_dictionary_get_audit_token(xdict, &auditToken);
				pid_t clientPid = audit_token_to_pid(auditToken);
				NSString *clientPath = [[procPath(clientPid) stringByResolvingSymlinksInPath] stringByStandardizingPath];
				NSString *jailbreakdPath = [[@"/var/jb/basebin/jailbreakd" stringByResolvingSymlinksInPath] stringByStandardizingPath];
				//jbdRemoteLog(3, @"jailbreak related message coming from binary: %@", clientPath);
				if ([clientPath isEqualToString:jailbreakdPath]) {
					uint64_t jbAction = xpc_dictionary_get_uint64(xdict, "jailbreak-action");
					xpc_object_t xreply = xpc_dictionary_create_reply(xdict);

					switch (jbAction) {
						// get pplrw
						case LAUNCHD_JB_MSG_ID_GET_PPLRW: {
							uint64_t magicPage = 0;
							int ret = handoffPPLPrimitives(clientPid, &magicPage);
							if (ret == 0) {
								xpc_dictionary_set_uint64(xreply, "magicPage", magicPage);
							}
							uint64_t slide = bootInfo_getUInt64(@"kernelslide");
							xpc_dictionary_set_uint64(xreply, "testread", kread64(slide + 0xFFFFFFF007004000));
							xpc_dictionary_set_int64(xreply, "error", ret);
							break;
						}

						// sign thread state
						case LAUNCHD_JB_MSG_ID_SIGN_STATE: {
							uint64_t actContext = xpc_dictionary_get_uint64(xdict, "actContext");
							int error = -1;
							if (actContext) {
								error = signState(actContext);
							}
							xpc_dictionary_set_int64(xreply, "error", error);
							break;
						}
					}

					xpc_pipe_routine_reply(xreply);
					return;
				}
			}
		}
	}
	xpc_handler_orig(a1, a2, xdict);
}

void initXPCHooks(void)
{
	int launchdIndex = -1;
	for (int i = 0; i < _dyld_image_count(); i++) {
		if(!strcmp(_dyld_get_image_name(i), "/sbin/launchd")) {
			launchdIndex = i;
			break;
		}
	}

	if (launchdIndex == -1) return;

	intptr_t launchdSlide = _dyld_get_image_vmaddr_slide(launchdIndex);
	void *xpcHandlerPtr = (void *)(launchdSlide + 0x10003ABD4); //TODO: Patchfind
	// ^ Only works on iPad 8, 15.4.1 for now
	MSHookFunction(xpcHandlerPtr, (void *)xpc_handler_replacement, (void **)&xpc_handler_orig);
}




/*

XPC HANDLER:
sub_10003ABD4

*/