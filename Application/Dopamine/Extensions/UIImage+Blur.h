//
//  UIImage+UIImage_Blur.h
//  Dopamine
//
//  Created by Lars Fröder on 01.10.23.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (Blur)

- (instancetype)imageWithBlur:(float)radius;

@end

NS_ASSUME_NONNULL_END
