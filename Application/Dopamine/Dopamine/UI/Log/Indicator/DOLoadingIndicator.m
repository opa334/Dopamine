//
//  DOLoadingIndicator.m
//  Dopamine
//
//  Created by tomt000 on 18/01/2024.
//

#import "DOLoadingIndicator.h"

@implementation DOLoadingIndicator

-(id)init {
    if (self = [super init]) {
        UIImage *image = [UIImage imageNamed:@"Loading"];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:imageView];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        animation.fromValue = @0.0;
        animation.toValue = @(2 * M_PI);
        animation.duration = 1.0;
        animation.repeatCount = INFINITY;
        [imageView.layer addAnimation:animation forKey:@"rotationAnimation"];
    }
    return self;
}

@end
