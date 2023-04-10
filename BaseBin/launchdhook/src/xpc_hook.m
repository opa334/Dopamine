#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/launchd.h>
#import <libjailbreak/patchfind.h>
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
void xpc_handler_hook(uint64_t a1, uint64_t a2, xpc_object_t xdict)
{
	if (xdict) {
		if (xpc_get_type(xdict) == XPC_TYPE_DICTIONARY) {
			bool jbRelated = xpc_dictionary_get_bool(xdict, "jailbreak");
			if (jbRelated) {
				audit_token_t auditToken = {};
				xpc_dictionary_get_audit_token(xdict, &auditToken);
				pid_t clientPid = audit_token_to_pid(auditToken);
				NSString *clientPath = [[procPath(clientPid) stringByResolvingSymlinksInPath] stringByStandardizingPath];
				NSString *jailbreakdPath = [[@"/var/jb/basebin/jailbreakd" stringByResolvingSymlinksInPath] stringByStandardizingPath];
				char *xdictDescription = xpc_copy_description(xdict);
				JBLogDebug("jailbreak related message %s coming from binary: %s", xdictDescription, clientPath.UTF8String);
				free(xdictDescription);
				if ([clientPath isEqualToString:jailbreakdPath]) {
					uint64_t msgId = xpc_dictionary_get_uint64(xdict, "id");
					xpc_object_t xreply = xpc_dictionary_create_reply(xdict);
					switch (msgId) {
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
	extern int gLaunchdImageIndex;

	// Credits to Cryptic for the patchfinding metrics
	unsigned char xpcHandlerBytes[] = "\xE0\x03\x00\xAA\xE0\x03\x00\xAA\xE0\x03\x00\xAA\x00\x00\x80\x52\x00\x00\x00\x39";
	unsigned char xpcHandlerBytesMask[] = "\xE0\xFF\xE0\xFF\xE0\xFF\xE0\xFF\xE0\xFF\xE0\xFF\x00\xFF\xE0\xFF\x00\x00\x00\xFF";
	
	void *xpcHandlerMid = patchfind_find(gLaunchdImageIndex, (unsigned char*)xpcHandlerBytes, (unsigned char*)xpcHandlerBytesMask, sizeof(xpcHandlerBytes));
	JBLogDebug("Launchd patchfinder found mid 0x%llX", xpcHandlerMid);

	void *xpcHandlerPtr = patchfind_seek_back(xpcHandlerMid, 0xD503237F, 0xFFFFFFFF, 50 * 4);

	JBLogDebug("Launchd patchfinder found 0x%llX", xpcHandlerPtr);
	if (xpcHandlerPtr)
	{
		MSHookFunction(xpcHandlerPtr, (void *)xpc_handler_hook, (void **)&xpc_handler_orig);
	}
}
