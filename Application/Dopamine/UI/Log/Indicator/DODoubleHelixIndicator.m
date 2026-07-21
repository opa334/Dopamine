//
//  DODoubleHelixIndicator.m
//  Dopamine
//
//  Created by tomt000 on 18/01/2024.
//

#import "DODoubleHelixIndicator.h"

@implementation DODoubleHelixIndicator

/// Bad remake of the double helix indicator from
/// https://github.com/SwiftfulThinking/SwiftfulLoadingIndicators

-(id)init {
    self = [super initWithFrame:CGRectMake(0, 0, 30, 30)];
    if (self) {
        
        int COUNT = 10;
        for (int i = 0; i < COUNT; i++)
        {
            [self createDotForIndex:i top:YES];
        }
        for (int i = 0; i < COUNT; i++)
        {
            [self createDotForIndex:i top:NO];
        }

    }
    return self;
}

-(void)createDotForIndex:(int)i top:(BOOL)top {
    int HEIGHT = 8;
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(i * (2 + 1), top ? HEIGHT : 0, 2, 2)];
    [view setBackgroundColor:[UIColor whiteColor]];
    [view.layer setCornerRadius:1];
    [view setClipsToBounds:YES];
    [self addSubview:view];

    if (top)
        view.alpha = 0.8;

    //infinite animation easeinout + delay
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    animation.repeatCount = INFINITY;
    animation.duration = 2.3;
    animation.beginTime = CACurrentMediaTime() + (0.1 * i);
    animation.keyTimes = @[@0.0, @0.5, @1.0];
    animation.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
    ];
    if (top)
        animation.values = @[@0.0, @(HEIGHT * -1), @0.0];
    else
        animation.values = @[@0.0, @(HEIGHT), @0.0];
    [view.layer addAnimation:animation forKey:@"animation"];
}

@end
