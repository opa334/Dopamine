#import "launchd.h"
#import "util.h"

#define OS_ALLOC_ONCE_KEY_MAX    100

struct _os_alloc_once_s {
	long once;
	void *ptr;
};

struct xpc_global_data {
	uint64_t    a;
	uint64_t    xpc_flags;
	mach_port_t    task_bootstrap_port;  /* 0x10 */
#ifndef _64
	uint32_t    padding;
#endif
	xpc_object_t    xpc_bootstrap_pipe;   /* 0x18 */
	// and there's more, but you'll have to wait for MOXiI 2 for those...
	// ...
};

extern struct _os_alloc_once_s _os_alloc_once_table[];
extern void* _os_alloc_once(struct _os_alloc_once_s *slot, size_t sz, os_function_t init);

xpc_object_t launchd_xpc_send_message(xpc_object_t xdict)
{
	void* pipePtr = NULL;
	
	if(_os_alloc_once_table[1].once == -1)
	{
		pipePtr = _os_alloc_once_table[1].ptr;
	}
	else
	{
		pipePtr = _os_alloc_once(&_os_alloc_once_table[1], 472, NULL);
		if (!pipePtr) _os_alloc_once_table[1].once = -1;
	}

	xpc_object_t xreply = nil;
	if (pipePtr) {
		struct xpc_global_data* globalData = pipePtr;
		xpc_object_t pipe = globalData->xpc_bootstrap_pipe;
		if (pipe) {
			int err = xpc_pipe_routine_with_flags(pipe, xdict, &xreply, 0);
			if (err != 0) {
				return nil;
			}
		}
	}
	return xreply;
}

void patchBaseBinLaunchDaemonPlist(NSString *plistPath)
{
	NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
	if (plistDict) {
		NSMutableArray *programArguments = ((NSArray *)plistDict[@"ProgramArguments"]).mutableCopy;
		if (programArguments.count >= 1) {
			programArguments[0] = prebootPath(programArguments[0]);
			plistDict[@"ProgramArguments"] = programArguments.copy;
			[plistDict writeToFile:plistPath atomically:YES];
		}
	}
}

void patchBaseBinLaunchDaemonPlists(void)
{
	NSURL *launchDaemonURL = [NSURL fileURLWithPath:prebootPath(@"basebin/LaunchDaemons") isDirectory:YES];
	NSArray<NSURL *> *launchDaemonPlistURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:launchDaemonURL includingPropertiesForKeys:nil options:0 error:nil];
	for (NSURL *launchDaemonPlistURL in launchDaemonPlistURLs) {
		patchBaseBinLaunchDaemonPlist(launchDaemonPlistURL.path);
	}
}
