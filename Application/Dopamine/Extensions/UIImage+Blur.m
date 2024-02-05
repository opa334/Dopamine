//
//  UIImage+Blur.m
//  Dopamine
//
//  Created by Lars Fröder on 01.10.23.
//

#import <Foundation/Foundation.h>
#import "UIImage+Blur.h"
#import <CoreImage/CoreImage.h>

@implementation UIImage (Blur)

- (instancetype)imageWithBlur:(float)radius
{
    CIImage *ciImage = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setDefaults];
    [filter setValue:ciImage forKey:kCIInputImageKey];
    [filter setValue:@(radius) forKey:kCIInputRadiusKey];
    
    CIImage *outputImage = [filter outputImage];
    CIContext *context   = [CIContext contextWithOptions:nil];
    CGImageRef cgImg     = [context createCGImage:outputImage fromRect:[ciImage extent]];
    
    return [UIImage imageWithCGImage:cgImg];

}

- (instancetype)imageWithHue:(float)hue
{
    CIImage *ciImage = [CIImage imageWithCGImage:self.CGImage];
    CIFilter *filter = [CIFilter filterWithName:@"CIHueAdjust"];
    [filter setDefaults];
    [filter setValue:ciImage forKey:kCIInputImageKey];
    [filter setValue:@(hue) forKey:kCIInputAngleKey];
    
    CIImage *outputImage = [filter outputImage];
    CIContext *context   = [CIContext contextWithOptions:nil];
    CGImageRef cgImg     = [context createCGImage:outputImage fromRect:[ciImage extent]];
    
    return [UIImage imageWithCGImage:cgImg];
}


@end
