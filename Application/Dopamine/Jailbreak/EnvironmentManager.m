//
//  EnvironmentManager.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "EnvironmentManager.h"

#import <sys/sysctl.h>
#import <libgrabkernel/libgrabkernel.h>

#import <IOKit/IOKitLib.h>
#import "NSData+Hex.h"

@implementation EnvironmentManager

@synthesize bootManifestHash = _bootManifestHash;
@synthesize jailbreakRootPath = _jailbreakRootPath;

+ (instancetype)sharedManager
{
    static EnvironmentManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EnvironmentManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bootstrapper = [[Bootstrapper alloc] init];
    }
    return self;
}

- (NSData *)bootManifestHash
{
    if (!_bootManifestHash) {
        io_registry_entry_t registryEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
        if (registryEntry) {
            _bootManifestHash = (__bridge NSData *)IORegistryEntryCreateCFProperty(registryEntry, CFSTR("boot-manifest-hash"), NULL, 0);
        }
    }
    return _bootManifestHash;
}

- (NSString *)activePrebootPath
{
    return [@"/private/preboot" stringByAppendingPathComponent:[self bootManifestHash].hexString];
}

- (NSString*)jailbreakRootPath
{
    if (!_jailbreakRootPath) {
        NSString *activePrebootPath = [self activePrebootPath];
        
        NSString *randomizedJailbreakPath;
        for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
            if (subItem.length == 9 && [subItem hasPrefix:@"jb-"]) {
                randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:subItem];
                break;
            }
        }

        if (!randomizedJailbreakPath) {
            NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            NSUInteger stringLen = 6;
            NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
            for (NSUInteger i = 0; i < stringLen; i++) {
                NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
                unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
                [randomString appendFormat:@"%C", randomCharacter];
            }
            
            NSString *randomJailbreakFolderName = [NSString stringWithFormat:@"jb-%@", randomString];
            randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:randomJailbreakFolderName];
        }
        
        _jailbreakRootPath = [randomizedJailbreakPath stringByAppendingPathComponent:@"procursus"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:_jailbreakRootPath]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:_jailbreakRootPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    
    return _jailbreakRootPath;
}

- (BOOL)isArm64e
{
    cpu_subtype_t cpusubtype = 0;
    size_t len = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &len, NULL, 0) == -1) { return NO; }
    return (cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E;

}

- (NSString *)versionSupportString
{
    if ([self isArm64e]) {
        return @"iOS 15.0 - 16.5.1 (arm64e)";
    }
    else {
        return @"iOS 15.0 - 16.6.1 (arm64)";
    }
}

- (BOOL)installedThroughTrollStore
{
    NSString* trollStoreMarkerPath = [[[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"_TrollStore"];
    return [[NSFileManager defaultManager] fileExistsAtPath:trollStoreMarkerPath];
}


- (NSString *)accessibleKernelPath
{
    if ([self installedThroughTrollStore]) {
        NSString *kernelcachePath = [[self activePrebootPath] stringByAppendingPathComponent:@"System/Library/Caches/com.apple.kernelcaches/kernelcache"];
        return kernelcachePath;
    }
    else {
        NSString *kernelcachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/kernelcache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            if (grabkernel((char *)kernelcachePath.fileSystemRepresentation, 0) != 0) return nil;
        }
        return kernelcachePath;
    }
}

- (BOOL)isPACBypassRequired
{
    if (![self isArm64e]) return NO;
    
    if (@available(iOS 15.2, *)) {
        return NO;
    }
    return YES;
}

- (BOOL)isPPLBypassRequired
{
    return [self isArm64e];
}

- (NSError *)prepareBootstrap
{
    __block NSError *errOut;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [_bootstrapper prepareBootstrapWithCompletion:^(NSError *error) {
        errOut = error;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return errOut;
}

- (void)finalizeBootstrap
{
    
}

@end
