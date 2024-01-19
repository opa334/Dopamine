//
//  Jailbreaker.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "Jailbreaker.h"
#import "EnvironmentManager.h"
#import "ExploitManager.h"
#import <sys/stat.h>
#import <compression.h>
#import <xpf/xpf.h>
#import <dlfcn.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/primitives_external.h>
#import <libjailbreak/codesign.h>
#import <libjailbreak/primitives.h>
#import <libjailbreak/primitives_IOSurface.h>
#import <libjailbreak/physrw_pte.h>
#import <libjailbreak/translation.h>
#import <libjailbreak/kernel.h>
#import <libjailbreak/info.h>
#import <libjailbreak/util.h>
#import <libjailbreak/trustcache.h>
#import <libjailbreak/kalloc_pt.h>

NSString *const JBErrorDomain = @"JBErrorDomain";
typedef NS_ENUM(NSInteger, JBErrorCode) {
    JBErrorCodeFailedToFindKernel            = -1,
    JBErrorCodeFailedKernelPatchfinding      = -2,
    JBErrorCodeFailedLoadingExploit          = -3,
    JBErrorCodeFailedExploitation            = -4,
    JBErrorCodeFailedBuildingPhysRW          = -5,
    JBErrorCodeFailedCleanup                 = -6,
    JBErrorCodeFailedGetRoot                 = -7,
    JBErrorCodeFailedUnsandbox               = -8,
    JBErrorCodeFailedPlatformize             = -9,
    JBErrorCodeFailedBasebinTrustcache       = -10,
};

@implementation Jailbreaker

- (NSError *)gatherSystemInformation
{
    NSString *kernelPath = [[EnvironmentManager sharedManager] accessibleKernelPath];
    if (!kernelPath) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedToFindKernel userInfo:@{NSLocalizedDescriptionKey:@"Failed to find kernelcache"}];
    NSLog(@"Kernel at %s", kernelPath.UTF8String);
    
    int r = xpf_start_with_kernel_path(kernelPath.fileSystemRepresentation);
    if (r == 0) {
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
            xpc_dictionary_set_uint64(_systemInfoXdict, "kernelConstant.staticBase", gXPF.kernelBase);
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
    }
    else {
        NSError *error = [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedKernelPatchfinding userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"XPF start failed with error: (%s)", xpf_get_error()]}];
        xpf_stop();
        return error;
    }
    
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

- (NSError *)doExploitation
{
    Exploit *kernelExploit = [ExploitManager sharedManager].preferredKernelExploit;
    printf("Picked Kernel Exploit: %s\n", kernelExploit.description.UTF8String);
    
    if ([kernelExploit load] != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedLoadingExploit userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load kernel exploit: %s", dlerror()]}];
    if ([kernelExploit run] != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedExploitation userInfo:@{NSLocalizedDescriptionKey:@"Failed to exploit kernel"}];
    
    jbinfo_initialize_boot_constants();
    libjailbreak_translation_primitives_init();
    libjailbreak_IOSurface_primitives_init();
    
    Exploit *pacBypass;
    if ([[EnvironmentManager sharedManager] isPACBypassRequired]) {
        pacBypass = [ExploitManager sharedManager].preferredPACBypass;
        if (pacBypass) {
            NSLog(@"Using PAC Bypass: %s\n", pacBypass.description.UTF8String);
            if ([pacBypass load] != 0) {[kernelExploit cleanup]; return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedLoadingExploit userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load PAC bypass: %s", dlerror()]}];};
            if ([pacBypass run] != 0) {[kernelExploit cleanup]; return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedExploitation userInfo:@{NSLocalizedDescriptionKey:@"Failed to bypass PAC"}];}
            // At this point we presume the PAC bypass has given us stable kcall primitives
            gSystemInfo.jailbreakInfo.usesPACBypass = true;
        }
    }
    
    if ([[EnvironmentManager sharedManager] isPPLBypassRequired]) {
        Exploit *pplBypass = [ExploitManager sharedManager].preferredPPLBypass;
        printf("Picked PPL Bypass: %s\n", pplBypass.description.UTF8String);
        if ([pplBypass load] != 0) {[pacBypass cleanup]; [kernelExploit cleanup]; return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedLoadingExploit userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to load PPL bypass: %s", dlerror()]}];};
        if ([pplBypass run] != 0) {[pacBypass cleanup]; [kernelExploit cleanup]; return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedExploitation userInfo:@{NSLocalizedDescriptionKey:@"Failed to bypass PPL"}];}
        // At this point we presume the PPL bypass gave us unrestricted phys write primitives
        if (!jbinfo(usesPACBypass)) {
            if (@available(iOS 16.0, *)) {
                // IOSurface kallocs don't work on iOS 16+, use these instead
                libjailbreak_init_kalloc_pt();
            }
        }
    }
    return nil;
}

- (NSError *)buildPhysRWPrimitive
{
    int r = libjailbreak_physrw_pte_init();
    if (r != 0) {
        return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedBuildingPhysRW userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to build phys r/w primitive: %d", r]}];
    }
    return nil;
}

- (NSError *)cleanUpExploits
{
    int r = [[ExploitManager sharedManager] cleanUpExploits];
    if (r != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedCleanup userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to cleanup exploits: %d", r]}];
    return nil;
}

- (NSError *)elevatePrivileges
{
    uint64_t proc = proc_self();
    uint64_t ucred = proc_ucred(proc);
    
    // Get uid 0
    kwrite32(proc + koffsetof(proc, svuid), 0);
    kwrite32(ucred + koffsetof(ucred, svuid), 0);
    kwrite32(ucred + koffsetof(ucred, ruid), 0);
    kwrite32(ucred + koffsetof(ucred, uid), 0);
    
    // Get gid 0
    kwrite32(proc + koffsetof(proc, svgid), 0);
    kwrite32(ucred + koffsetof(ucred, rgid), 0);
    kwrite32(ucred + koffsetof(ucred, svgid), 0);
    kwrite32(ucred + koffsetof(ucred, groups), 0);
    
    // Add P_SUGID
    uint32_t flag = kread32(proc + koffsetof(proc, flag));
    if ((flag & P_SUGID) != 0) {
        flag &= P_SUGID;
        kwrite32(proc + koffsetof(proc, flag), flag);
    }
    
    if (getuid() != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedGetRoot userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to get root, uid still %d", getuid()]}];
    if (getgid() != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedGetRoot userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to get root, gid still %d", getgid()]}];
    
    // Unsandbox
    uint64_t label = kread_ptr(ucred + koffsetof(ucred, label));
    kwrite64(label + 0x10, -1);
    NSError *error = nil;
    [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var" error:&error];
    if (error) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedUnsandbox userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to unsandbox, /var does not seem accessible (%s)", error.description.UTF8String]}];
    setenv("HOME", "/var/root", true);
    setenv("CFFIXED_USER_HOME", "/var/root", true);
    setenv("TMPDIR", "/var/tmp", true);
    
    // Get CS_PLATFORM_BINARY
    proc_csflags_set(proc, CS_PLATFORM_BINARY);
    uint32_t csflags;
    csops(getpid(), CS_OPS_STATUS, &csflags, sizeof(csflags));
    if (!(csflags & CS_PLATFORM_BINARY)) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedPlatformize userInfo:@{NSLocalizedDescriptionKey:@"Failed to get CS_PLATFORM_BINARY"}];
    
    return nil;
}

- (NSError *)loadBasebinTrustcache
{
    int basebinTcFd = open([[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"BaseBin.tc"].fileSystemRepresentation, O_RDONLY);
    if (basebinTcFd < 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedBasebinTrustcache userInfo:@{NSLocalizedDescriptionKey : @"Failed to open BaseBin trustcache"}];

    struct stat s;
    fstat(basebinTcFd, &s);
    trustcache_file_v1 *basebinTcFile = malloc(s.st_size);
    if (read(basebinTcFd, basebinTcFile, s.st_size) != s.st_size) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedBasebinTrustcache userInfo:@{NSLocalizedDescriptionKey : @"Failed to read BaseBin trustcache"}];

    int r = trustcache_file_upload_with_uuid(basebinTcFile, BASEBIN_TRUSTCACHE_UUID);
    if (r != 0) return [NSError errorWithDomain:JBErrorDomain code:JBErrorCodeFailedBasebinTrustcache userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to upload BaseBin trustcache: %d", r]}];
    
    free(basebinTcFile);
    close(basebinTcFd);
    return nil;
}

- (NSError *)run
{
    NSError *err = nil;
    err = [self gatherSystemInformation];
    if (err) return err;
    err = [self doExploitation];
    if (err) return err;
    err = [self buildPhysRWPrimitive];
    if (err) return err;
    err = [self cleanUpExploits];
    if (err) return err;

    //for (int i = 0; i < 200; i++) {
    //    printf("We out here! Test read: %x\n", kread32(kconstant(base) + i*0x4000));
    //}
    
    err = [self elevatePrivileges];
    if (err) return err;
    printf("Got UID %d\n", getuid());
    
    //for (int i = 0; i < 200; i++) {
    //    uint64_t alloc = pmap_alloc_page_table(0, 0);
    //    printf("%d: allocated %llx\n", i, alloc);
    //}

    err = [[EnvironmentManager sharedManager] prepareBootstrap];
    if (err) return err;
    printf("Bootstrap done\n");
    
    err = [self loadBasebinTrustcache];
    if (err) return err;
    int r = exec_cmd("/var/jb/basebin/jbctl", NULL);
    printf("jbctl returned %d\n", r);
    
    return nil;
}

@end
