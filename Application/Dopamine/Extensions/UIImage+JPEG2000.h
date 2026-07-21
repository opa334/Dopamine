#import <UIKit/UIKit.h>

@interface UIImage (JPEG2000)
- (NSData *)jp2DataWithCompressionQuality:(CGFloat)quality;
@end