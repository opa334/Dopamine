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

void addLaunchDaemon(xpc_object_t xdict, const char *path)
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
		if (addr) {
			xpc_object_t daemonXdict = xpc_create_from_plist(addr, len);
			if (daemonXdict) {
				xpc_dictionary_set_value(xdict, path, daemonXdict);
			}
		}
		close(ldFd);
	}
}

xpc_object_t (*xpc_dictionary_get_value_orig)(xpc_object_t xdict, const char *key);
xpc_object_t xpc_dictionary_get_value_hook(xpc_object_t xdict, const char *key)
{
	xpc_object_t orgValue = xpc_dictionary_get_value_orig(xdict, key);
	if (!strcmp(key, "LaunchDaemons")) {
		addLaunchDaemon(orgValue, prebootPath(@"basebin/LaunchDaemons/com.opa334.jailbreakd.plist").fileSystemRepresentation);
		addLaunchDaemon(orgValue, prebootPath(@"basebin/LaunchDaemons/com.opa334.trustcache_rebuild.plist").fileSystemRepresentation);
		for (NSString *daemonPlistName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:prebootPath(@"Library/LaunchDaemons") error:nil]) {
			if ([daemonPlistName.pathExtension isEqualToString:@"plist"]) {
				addLaunchDaemon(orgValue, [prebootPath(@"Library/LaunchDaemons") stringByAppendingPathComponent:daemonPlistName].fileSystemRepresentation);
			}
		}
	}
	else if (!strcmp(key, "Paths")) {
		xpc_array_set_string(orgValue, XPC_ARRAY_APPEND, prebootPath(@"basebin/LaunchDaemons").fileSystemRepresentation);
		xpc_array_set_string(orgValue, XPC_ARRAY_APPEND, prebootPath(@"Library/LaunchDaemons").fileSystemRepresentation);
	}
	return orgValue;
}

void initDaemonHooks(void)
{
	MSHookFunction(&xpc_dictionary_get_value, (void *)xpc_dictionary_get_value_hook, (void **)&xpc_dictionary_get_value_orig);
}