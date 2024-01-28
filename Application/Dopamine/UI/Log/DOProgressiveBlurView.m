//
//  DOProgressiveBlurView.m
//  Dopamine
//
//  Created by tomt000 on 18/01/2024.
//

#import "DOProgressiveBlurView.h"

@interface UIBlurEffect (Private)
- (id)effectSettings;
@end
@interface DOBlurEffect : UIBlurEffect
@end
@implementation DOBlurEffect
- (id)effectSettings {
    id settings = [super effectSettings];
    [settings setValue:@(1.0) forKey:@"scale"];
    [settings setValue:@0 forKey:@"grayscaleTintAlpha"];
    [settings setValue:@1 forKey:@"saturationDeltaFactor"];
    return settings;
}

@end

@implementation DOProgressiveBlurView

- (instancetype)initWithGradientMask:(UIImage *)gradientMask maxBlurRadius:(CGFloat)maxBlurRadius {
    self = [super initWithEffect:[DOBlurEffect effectWithStyle:UIBlurEffectStyleRegular]];
    if (self) {
        Class CAFilter = NSClassFromString(@"CAFilter");
        id variableBlur = [CAFilter performSelector:NSSelectorFromString(@"filterWithType:") withObject:@"variableBlur"];

        CGImageRef gradientImageRef = gradientMask.CGImage;
        [variableBlur setValue:@(maxBlurRadius) forKey:@"inputRadius"];
        [variableBlur setValue:(__bridge id)(gradientImageRef) forKey:@"inputMaskImage"];
        [variableBlur setValue:@YES forKey:@"inputNormalizeEdges"];

        [self.subviews.firstObject.layer setValue:@[variableBlur] forKey:@"filters"];
    }
    return self;
}

@end
