//
//  EnvironmentManager.h
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import <Foundation/Foundation.h>
#import "Bootstrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface EnvironmentManager : NSObject
{
    Bootstrapper *_bootstrapper;
}

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSData *bootManifestHash;

- (BOOL)isInstalledThroughTrollStore;
- (BOOL)isJailbroken;

- (BOOL)isArm64e;
- (NSString *)versionSupportString;
- (NSString *)accessibleKernelPath;
- (void)determineJailbreakRootPath;

- (void)runAsRoot:(void (^)(void))rootBlock;
- (void)respring;
- (void)rebootUserspace;

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
@end

NS_ASSUME_NONNULL_END
