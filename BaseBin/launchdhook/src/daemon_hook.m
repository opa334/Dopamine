#import <xpc/xpc.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <unistd.h>
#import "substrate.h"
#import <libjailbreak/patchfind.h>
#import <mach-o/dyld.h>
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>

extern xpc_object_t xpc_create_from_plist(const void *buf, size_t len);

void xpc_dictionary_add_launch_daemon_plist_at_path(xpc_object_t xdict, const char *path)
{
	int ldFd = open(path, O_RDONLY);
	if (ldFd >= 0) {
		struct stat s = {};
		if(fstat(ldFd, &s) != 0) {
			close(ldFd);
			return;
		}
		size_t len = s.st_size;
		void *addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, ldFd, 0);
		if (addr != MAP_FAILED) {
			xpc_object_t daemonXdict = xpc_create_from_plist(addr, len);
			if (daemonXdict) {
				xpc_dictionary_set_value(xdict, path, daemonXdict);
			}
			munmap(addr, len);
		}
		close(ldFd);
	}
}

xpc_object_t (*xpc_dictionary_get_value_orig)(xpc_object_t xdict, const char *key);
xpc_object_t xpc_dictionary_get_value_hook(xpc_object_t xdict, const char *key)
{
	xpc_object_t origXdict = xpc_dictionary_get_value_orig(xdict, key);
	if (!strcmp(key, "LaunchDaemons")) {
		xpc_dictionary_add_launch_daemon_plist_at_path(origXdict, prebootPath(@"basebin/LaunchDaemons/com.opa334.jailbreakd.plist").fileSystemRepresentation);
		xpc_dictionary_add_launch_daemon_plist_at_path(origXdict, prebootPath(@"basebin/LaunchDaemons/com.opa334.trustcache_rebuild.plist").fileSystemRepresentation);
		for (NSString *daemonPlistName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:prebootPath(@"Library/LaunchDaemons") error:nil]) {
			if ([daemonPlistName.pathExtension isEqualToString:@"plist"]) {
				xpc_dictionary_add_launch_daemon_plist_at_path(origXdict, [prebootPath(@"Library/LaunchDaemons") stringByAppendingPathComponent:daemonPlistName].fileSystemRepresentation);
			}
		}
	}
	else if (!strcmp(key, "Paths")) {
		xpc_array_set_string(origXdict, XPC_ARRAY_APPEND, prebootPath(@"basebin/LaunchDaemons").fileSystemRepresentation);
		xpc_array_set_string(origXdict, XPC_ARRAY_APPEND, prebootPath(@"Library/LaunchDaemons").fileSystemRepresentation);
	}
	return origXdict;
}

void initDaemonHooks(void)
{
	MSHookFunction(&xpc_dictionary_get_value, (void *)xpc_dictionary_get_value_hook, (void **)&xpc_dictionary_get_value_orig);
}