//
//  Bootstrapper.h
//  Dopamine
//
//  Created by Lars Fröder on 09.01.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Bootstrapper : NSObject
{
    NSURLSessionDownloadTask *_bootstrapDownloadTask;
}

- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion;
- (BOOL)needsFinalize;
- (NSError *)finalizeBootstrap;

@end

NS_ASSUME_NONNULL_END
