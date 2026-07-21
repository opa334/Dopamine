//
//  GlobalAppearance.m
//  Dopamine
//
//  Created by Lars Fröder on 10.10.23.
//

#import "DOGlobalAppearance.h"
#import <CoreGraphics/CoreGraphics.h>
#import "DOThemeManager.h"

@implementation DOGlobalAppearance

+ (UIImageSymbolConfiguration *)smallIconImageConfiguration
{
    return [UIImageSymbolConfiguration configurationWithPointSize: 14 weight:UIImageSymbolWeightMedium];
}

+ (UIButtonConfiguration *)defaultButtonConfiguration
{
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.imagePadding = 10;
    configuration.baseForegroundColor = [UIColor whiteColor];
    configuration.titleLineBreakMode = NSLineBreakByClipping;

    // IN DARK MODE, APPLE JUST ADDS WHITE WHEN A BUTTON IS HIGHLIGHTED WHEN IT'S SET UP VIA UIButtonConfiguration
    // UNFORTUNATELY THEY FORGOT ABOUT THE POSSIBILITY ABOUT THERE BEING A WHITE BUTTON, SO THOSE JUST DON'T SHOW ANY HIGHLIGHT COLOR
    // HACKY WORKAROUND TO FIX FIX THIS MESS; SCREW APPLE
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> * _Nonnull(NSDictionary<NSAttributedStringKey,id> * _Nonnull textAttributes) {
        // Something makes me think the person that developed this API never actually used it...
        // OR ELSE WHERE IS MY BUTTON REFERENCE TO KNOW WHAT STATE I'M EVEN DEALING WITH???
        // THIS IS A SUPER HACKY WAY OF DETERMINING WHETHER THE BUTTON IS HIGHLIGHTED OR NOT
        // WHEN IT'S HIGHLIGHTED THE COLOR WILL BE IN UIExtendedSRGBColorSpace
        // WHEN NOT HIGHLIGHTED IT WILL BE IN UIExtendedGrayColorSpace
        // WHEN NOT IN DARK MODE IT WILL ALREADY BE WHAT WE WANT, JUST SKIP
        NSMutableDictionary<NSAttributedStringKey,id> *textAttributesM = textAttributes.mutableCopy;
        UIColor *foregroundColor = textAttributes[NSForegroundColorAttributeName];
        CGFloat alpha, white;
        [foregroundColor getWhite:&white alpha:&alpha];
        if ((int)white == 1 && (int)alpha == 1) {
            CGColorSpaceRef colorSpace = CGColorGetColorSpace(foregroundColor.CGColor);
            CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
            if (model == kCGColorSpaceModelRGB) {
                textAttributesM[NSForegroundColorAttributeName] = [[UIColor whiteColor] colorWithAlphaComponent:0.75];
            }
        }
        // textAttributesM[NSFontAttributeName] = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        return textAttributesM;
    };
    configuration.imageColorTransformer = ^UIColor * _Nonnull(UIColor * _Nonnull color) {
        // Something makes me think the person that developed this API never actually used it...
        // OR ELSE WHERE IS MY BUTTON REFERENCE TO KNOW WHAT STATE I'M EVEN DEALING WITH???
        // THIS IS A SUPER HACKY WAY OF DETERMINING WHETHER THE BUTTON IS HIGHLIGHTED OR NOT
        // WHEN IT'S HIGHLIGHTED THE COLOR WILL BE IN UIExtendedSRGBColorSpace
        // WHEN NOT HIGHLIGHTED IT WILL BE IN UIExtendedGrayColorSpace
        // WHEN NOT IN DARK MODE IT WILL ALREADY BE WHAT WE WANT, JUST SKIP
        CGFloat alpha, white;
        [color getWhite:&white alpha:&alpha];
        if ((int)white == 1 && (int)alpha == 1) {
            CGColorSpaceRef colorSpace = CGColorGetColorSpace(color.CGColor);
            CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
            if (model == kCGColorSpaceModelRGB) {
                return [color colorWithAlphaComponent:0.75];
            }
        }
        return color;
    };
    
    return configuration;
}

+ (UIButtonConfiguration *)defaultButtonConfigurationWithImagePadding:(CGFloat)imagePadding
{
    UIButtonConfiguration *configuration = [DOGlobalAppearance defaultButtonConfiguration];
    configuration.imagePadding = imagePadding;
    return configuration;
}

#pragma mark - Attributed Strings

+ (NSAttributedString*)mainSubtitleString:(NSString*)string
{
    return [[NSAttributedString alloc] initWithString:string attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium],
        NSForegroundColorAttributeName: [UIColor whiteColor],
    }];
}

+ (NSAttributedString*)secondarySubtitleString:(NSString*)string
{
    return [[NSAttributedString alloc] initWithString:string attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.60],
    }];
}

+ (BOOL)isHomeButtonDevice
{
   return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone && [[UIApplication sharedApplication] keyWindow].safeAreaInsets.bottom == 0;
}

+ (BOOL)isRTL
{
    return [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

+ (BOOL)isSmallDevice
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    return window.frame.size.height < SE_PHONE_SIZE_CONST + 50;
}

@end
