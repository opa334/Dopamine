#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Foundation/Foundation.h>
#import "UIImage+JPEG2000.h"

@implementation UIImage (JPEG2000) 

- (NSData *)jp2DataWithCompressionQuality:(CGFloat)quality
{
	NSMutableData *data = [NSMutableData data];
	CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, kUTTypeJPEG2000, 1, NULL);
	if (!destination) {
		return nil;
	}
	
	NSDictionary *options = @{
		(NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)
	};
	
	CGImageDestinationAddImage(destination, self.CGImage, (__bridge CFDictionaryRef)options);
	if (!CGImageDestinationFinalize(destination)) {
		CFRelease(destination);
		return nil;
	}
	
	CFRelease(destination);
	return data;
}

@end