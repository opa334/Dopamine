#import "common.h"
#import <stdio.h>
#include <xpc/xpc.h>
#include <sys/stat.h>

extern int64_t sandbox_extension_consume(const char *extension_token);

extern xpc_object_t xpc_create_from_plist(const void *buf, size_t len);

void unsandbox(void) {
	size_t len = 0;
	void *addr = NULL;
	struct stat s = {};
	int fd = 0;
	fd = open("/usr/lib/sandbox.plist", O_RDONLY);
	if(fd < 0) return;
	if(fstat(fd, &s) != 0) {
		close(fd);
		return;
	}
	len = s.st_size;
	addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
	if(addr != MAP_FAILED) {
		xpc_object_t xplist = xpc_create_from_plist(addr, len);
		if(xplist) {
			if(xpc_get_type(xplist) == XPC_TYPE_DICTIONARY) {
				xpc_object_t xextensions = xpc_dictionary_get_value(xplist, "extensions");
				if(xextensions) {
					if(xpc_get_type(xextensions) == XPC_TYPE_ARRAY) {
						size_t count = xpc_array_get_count(xextensions);
						for(int i = 0; i < count; i++) {
							const char *extensionToken = xpc_array_get_string(xextensions, i);
							if (extensionToken) {
								sandbox_extension_consume(extensionToken);
							}
						}
					}
				}
			}
			xpc_release(xplist);
		}
	}
	close(fd);
}
