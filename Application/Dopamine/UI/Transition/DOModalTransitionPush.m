//
//  DOModalTransitionPush.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOModalTransitionPush.h"

@interface DOModalTransitionPush ()

@property (nonatomic, assign) BOOL forwards;

@end

@implementation DOModalTransitionPush

- (id)initForwards:(BOOL)forwards {
    self = [super init];
    if (self) {
        _forwards = forwards;
    }
    return self;
}


- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.5;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    
    int screen_width = fromViewController.navigationController.view.bounds.size.width;

    [[transitionContext containerView] addSubview:toViewController.view];

    screen_width *= _forwards ? 1 : -1;

    
    toViewController.view.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, screen_width, 0);
    fromViewController.view.transform = CGAffineTransformIdentity;
    
    [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        toViewController.view.transform = CGAffineTransformIdentity;
        fromViewController.view.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, -screen_width, 0);
    } completion:^(BOOL finished) {
        fromViewController.view.transform = CGAffineTransformIdentity;
        [transitionContext completeTransition:!transitionContext.transitionWasCancelled];
    }];   
}

@end
