//
//  Jailbreaker.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "Jailbreaker.h"
#import "EnvironmentManager.h"
#import <sys/stat.h>
#import "Util.h"
#import <compression.h>
#import <xpf/xpf.h>
#include <dlfcn.h>

NSString *const JBErrorDomain = @"JBErrorDomain";
typedef NS_ENUM(NSInteger, JBErrorCode) {
    JBErrorCodeFailedToFindKernel            = -1,
    JBErrorCodeFailedKernelPatchfinding      = -2,
    JBErrorCodeFailedLoadingExploit          = -3,
};

#include <libjailbreak/primitives_external.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/primitives_IOSurface.h>
#include <libjailbreak/translation.h>
#include <libjailbreak/info.h>

@implementation Jailbreaker

- (NSError *)gatherSystemInformation
{
    NSString *kernelPath = [EnvironmentManager accessibleKernelPath];
    if (!kernelPath) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedToFindKernel userInfo:@{NSLocalizedDescriptionKey:@"Failed to find kernelcache"}];
    printf("Kernel at %s\n", kernelPath.UTF8String);
    
    xpf_start_with_kernel_path(kernelPath.fileSystemRepresentation);
    
    const char *sets[] = {
        "translation",
        "trustcache",
        "physmap",
        "struct",
        "physrw",
        "perfkrw",
        "badRecovery",
        NULL
    };
    
    if (!xpf_set_is_supported("badRecovery")) {
        sets[6] = NULL;
    }

    _systemInfoXdict = xpf_construct_offset_dictionary(sets);
    if (_systemInfoXdict) {
        printf("System Info:\n");
        xpc_dictionary_apply(_systemInfoXdict, ^bool(const char *key, xpc_object_t value) {
            if (xpc_get_type(value) == XPC_TYPE_UINT64) {
                printf("0x%016llx <- %s\n", xpc_uint64_get_value(value), key);
            }
            return true;
        });
    }
    if (!_systemInfoXdict) {
        return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedKernelPatchfinding userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"XPF failed with error: (%s)", xpf_get_error()]}];
    }
    xpf_stop();
    
    jbinfo_initialize_dynamic_offsets(_systemInfoXdict);
    jbinfo_initialize_hardcoded_offsets();
    _systemInfoXdict = jbinfo_get_serialized();
    
    if (_systemInfoXdict) {
        printf("System Info libjailbreak:\n");
        xpc_dictionary_apply(_systemInfoXdict, ^bool(const char *key, xpc_object_t value) {
            if (xpc_get_type(value) == XPC_TYPE_UINT64) {
                if (xpc_uint64_get_value(value)) {
                    printf("0x%016llx <- %s\n", xpc_uint64_get_value(value), key);
                }
            }
            return true;
        });
    }
    
    return nil;
}

- (NSError *)exploitKernel
{
    void *kfdHandle = dlopen([[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/Exploits/kfd.framework/kfd"].fileSystemRepresentation, RTLD_NOW);
    if (!kfdHandle) {
        return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedLoadingExploit userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load exploit: %s", dlerror()]}];
    }
    void (*exploit_init)(const char *flavor) = dlsym(kfdHandle, "exploit_init");
    void (*explot_deinit)(void) = dlsym(kfdHandle, "exploit_deinit");
    
    exploit_init("landa");
    explot_deinit();
    
    return nil;
}


- (NSError *)run
{
    NSError *err = nil;
    err = [self gatherSystemInformation];
    if (err) return err;
    err = [self exploitKernel];
    if (err) return err;
    
    return nil;
}

@end
