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
    BOOL _isJailbroken;
    NSString *_jailbrokenVersion;
    BOOL _bootstrapNeedsMigration;
}

+ (instancetype)sharedManager;

- (NSString *)appVersion;
- (NSString *)appVersionDisplayString;
- (NSString *)nightlyHash;

- (NSString *)privatePrebootPath;
- (NSString *)activePrebootPath;

- (BOOL)isInstalledThroughTrollStore;
- (BOOL)isJailbroken;
- (BOOL)isJailbrokenWithOtherJailbreak;
- (BOOL)isBootstrapped;
- (NSString *)jailbrokenVersion;
- (NSString *)systemVersion;

- (BOOL)isSupported;
- (BOOL)isArm64e;
- (BOOL)isSPTM;
- (NSString *)versionSupportString;
- (NSString *)accessibleKernelPath;
- (NSString *)accessibleSPTMPath;
- (NSString *)accessibleTXMPath;
- (void)locateJailbreakRoot;
- (NSError *)ensureJailbreakRootExists;

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version;


// FIX REMOVE-JAILBREAK EPERM (Issue 2): giờ trả về int (0 = OK / block đã chạy;
// != 0 = KHÔNG unsandbox được, block KHÔNG chạy). Trước đây trả void và bỏ qua
// thất bại unsandbox → block chạy trong sandbox → EPERM(1) trên mọi unlink
// trong jbroot khi Remove Jailbreak.
- (int)runUnsandboxed:(void (^)(void))unsandboxBlock;
- (void)runAsRoot:(void (^)(void))rootBlock;

- (void)respring;
- (void)rebootUserspace;
- (int)spawnJbctlAsRootWithArgs:(NSArray *)args;
- (void)refreshJailbreakApps;
- (void)reboot;
- (void)changeMobilePassword:(NSString *)newPassword;
- (NSError*)updateEnvironment;
- (void)updateJailbreakFromTIPA:(NSString *)tipaPath;

- (BOOL)isTweakInjectionEnabled;
- (void)setTweakInjectionEnabled:(BOOL)enabled;
- (BOOL)isIDownloadEnabled;
- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox;
- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox;
- (BOOL)isFakelibMounted;
- (int)setFakelibMounted:(BOOL)mounted;
- (int)setPrivatePrebootProtected:(BOOL)protected;
- (BOOL)isJailbreakHidden;
- (void)setJailbreakHidden:(BOOL)hidden;

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;
- (NSError *)reinstallPackageManagers;
- (NSError *)updateBootLogo;
@end

NS_ASSUME_NONNULL_END
