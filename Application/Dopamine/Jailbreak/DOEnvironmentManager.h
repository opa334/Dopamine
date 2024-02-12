//
//  EnvironmentManager.h
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import <Foundation/Foundation.h>
#import "DOBootstrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOEnvironmentManager : NSObject
{
    DOBootstrapper *_bootstrapper;
}

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSData *bootManifestHash;

- (BOOL)isInstalledThroughTrollStore;
- (BOOL)isJailbroken;

- (BOOL)isSupported;
- (BOOL)isArm64e;
- (NSString *)versionSupportString;
- (NSString *)accessibleKernelPath;
- (void)determineJailbreakRootPath;

- (void)runUnsandboxed:(void (^)(void))unsandboxBlock;
- (void)runAsRoot:(void (^)(void))rootBlock;

- (void)respring;
- (void)rebootUserspace;
- (void)reboot;
- (void)setTweakInjectionEnabled:(BOOL)enabled;
- (void)setIDownloadEnabled:(BOOL)enabled;
- (BOOL)isJailbreakHidden;
- (void)setJailbreakHidden:(BOOL)hidden;

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;
@end

NS_ASSUME_NONNULL_END
