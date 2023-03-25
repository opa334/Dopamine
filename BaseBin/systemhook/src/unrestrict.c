#import "common.h"
#import <stdio.h>
#include <xpc/xpc.h>
#include <sys/stat.h>

extern int64_t sandbox_extension_consume(const char *extension_token);

extern xpc_object_t xpc_create_from_plist(const void *buf, size_t len);

static void unsandbox(void) {
    size_t len = 0;
    void *addr = NULL;
    struct stat s = {};
    int fd = 0;
    fd = open("/usr/lib/sandbox.plist", O_RDONLY);
    if(fd < 0)
    {
//        printf("systemhook: %s: fd < 0\n", __func__);
        return;
    }
    if(fstat(fd, &s) != 0) {
//        printf("systemhook: %s: fstat(fd, &s) != 0\n", __func__);
        return;
    }
    len = s.st_size;
    addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
    if(addr == MAP_FAILED) {
//        printf("systemhook: %s: addr == MAP_FAILED\n", __func__);
        return;
    }
    xpc_object_t xobj = xpc_create_from_plist(addr, len);
    if(xobj) {
        if(xpc_get_type(xobj) == &_xpc_type_dictionary) {
            xpc_object_t obj = xpc_dictionary_get_value(xobj, "extensions");
            if(obj) {
                if(xpc_get_type(obj) == &_xpc_type_array) {
                    size_t count = xpc_array_get_count(obj);
                    for(int i = 0; i < count; i++) {
                        const char *extensionToken = xpc_array_get_string(obj, i);
                        if (extensionToken) {
                            sandbox_extension_consume(extensionToken);
                        } else {
                            xpc_release(xobj);
//                            printf("systemhook: %s: if (extensionToken) {\n", __func__);
                            return;
                        }
                    }
                } else {
//                    printf("systemhook: %s: xpc_get_type(obj) == &_xpc_type_array\n", __func__);
                    xpc_release(xobj);
                    return;
                }
            } else {
//                printf("systemhook: %s: if(obj) {\n", __func__);
                xpc_release(xobj);
                return;
            }
        } else {
//            printf("systemhook: %s: xpc_get_type(xobj) == &_xpc_type_dictionary\n", __func__);
            xpc_release(xobj);
            return;
        }
    }
//    printf("systemhook: %s: end\n", __func__);
    xpc_release(xobj);
}

void unrestrict(void)
{
	unsandbox();
	jbdDebugMe();
}