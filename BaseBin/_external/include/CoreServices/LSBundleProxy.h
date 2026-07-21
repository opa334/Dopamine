@interface LSBundleProxy : NSObject
@property (nonatomic) NSURL *bundleURL;
@property (nonatomic,readonly) NSString *bundleExecutable;
@end