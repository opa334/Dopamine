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
struct kernel_primitives *gPrimitivesPtr = NULL;
void (*libjailbreak_initialize_dynamic_offsets)(xpc_object_t xoffsetDict);
void (*libjailbreak_initialize_hardcoded_offsets)(void);
void (*libjailbreak_initialize_boot_constants)(xpc_object_t xoffsetDict);
xpc_object_t (*libjailbreak_get_system_info)(void);

int libjailbreak_load(void)
{
    static void *libjailbreakHandle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        libjailbreakHandle = dlopen([[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libjailbreak.dylib"].fileSystemRepresentation, RTLD_NOW);
        if (libjailbreakHandle) {
            gPrimitivesPtr = (struct kernel_primitives *)dlsym(libjailbreakHandle, "gPrimitives");
            libjailbreak_initialize_dynamic_offsets = dlsym(libjailbreakHandle, "libjailbreak_initialize_dynamic_offsets");
            libjailbreak_initialize_hardcoded_offsets = dlsym(libjailbreakHandle, "libjailbreak_initialize_hardcoded_offsets");
            libjailbreak_initialize_boot_constants = dlsym(libjailbreakHandle, "libjailbreak_initialize_boot_constants");
            libjailbreak_get_system_info = dlsym(libjailbreakHandle, "libjailbreak_get_system_info");
        }
    });
    
    if (!gPrimitivesPtr) return -1;
    if (!libjailbreak_initialize_dynamic_offsets) return -1;
    if (!libjailbreak_initialize_hardcoded_offsets) return -1;
    if (!libjailbreak_initialize_boot_constants) return -1;
    if (!libjailbreak_get_system_info) return -1;
    return 0;
}

@implementation Jailbreaker

- (NSError *)initializeLibJailbreak
{
    if (libjailbreak_load() == 0) return nil;
    return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedKernelPatchfinding userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load libjailbreak: (%s)", dlerror()]}];
}

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
    
    libjailbreak_initialize_dynamic_offsets(_systemInfoXdict);
    libjailbreak_initialize_hardcoded_offsets();
    _systemInfoXdict = libjailbreak_get_system_info();
    
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
    void (*exploit_init)(const char *flavor, struct kernel_primitives *primitives, xpc_object_t systemInfoXdict) = dlsym(kfdHandle, "exploit_init");
    //void (*explot_deinit)(struct kernel_primitives *primitives) = dlsym(kfdHandle, "exploit_deinit");
    
    exploit_init("landa", gPrimitivesPtr, _systemInfoXdict);
    
    return nil;
}


- (NSError *)run
{
    NSError *err = nil;
    err = [self initializeLibJailbreak];
    if (err) return err;
    err = [self gatherSystemInformation];
    if (err) return err;
    err = [self exploitKernel];
    if (err) return err;
    
    return nil;
}

@end
