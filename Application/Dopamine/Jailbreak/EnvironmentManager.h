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

- (BOOL)isArm64e;
- (NSString *)versionSupportString;
- (BOOL)installedThroughTrollStore;
- (NSString *)accessibleKernelPath;
- (void)determineJailbreakRootPath;

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
@end

NS_ASSUME_NONNULL_END
