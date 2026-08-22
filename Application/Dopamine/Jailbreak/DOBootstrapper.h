//
//  Bootstrapper.h
//  Dopamine
//
//  Created by Lars Fröder on 09.01.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const bootstrapErrorDomain;
typedef NS_ENUM(NSInteger, BootstrapErrorCode) {
    BootstrapErrorCodeFailedToGetURL            = -1,
    BootstrapErrorCodeFailedToDownload          = -2,
    BootstrapErrorCodeFailedDecompressing       = -3,
    BootstrapErrorCodeFailedExtracting          = -4,
    BootstrapErrorCodeFailedRemount             = -5,
    BootstrapErrorCodeFailedFinalising          = -6,
    BootstrapErrorCodeFailedReplacing           = -7,
};

@interface DOBootstrapper : NSObject <NSURLSessionDelegate, NSURLSessionDownloadDelegate>
{
    NSURLSession *_urlSession;
    NSURLSessionDownloadTask *_bootstrapDownloadTask;
    void (^_downloadCompletionBlock)(NSURL * _Nullable location, NSError * _Nullable error);
}

- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion;
- (NSError *)updateVarJbSymlink;
- (NSError *)ensurePrivatePrebootIsWritable;
- (NSError *)installPackageManagers;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;

@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
extern "C" {
#endif
uint64_t jbrand_new(void);
uint64_t jbrand_current(void);
int is_jbroot_name(char *name);
NSString *find_jbroot(BOOL force);
NSString *jbrootPrefix(NSString *path);
NSString *rootfsPrefix(NSString *path);
#ifdef __cplusplus
}
#endif
