//
//  DONavigationController.m
//  Dopamine
//
//  Created by tomt000 on 04/01/2024.
//

#import "DONavigationController.h"

@interface DONavigationController ()

@property (nonatomic) UIImageView *backgroundImageView;
@property (nonatomic) DOMainViewController *mainView;

@end

@interface UINavigationController (Private)
-(CGRect)_frameForViewController:(id)arg1;
@end

#define UI_MODAL_PADDING 30

@implementation DONavigationController

- (void)viewDidLoad
{
    [self setupBackground];
    [super viewDidLoad];
    [self setNavigationBarHidden:YES];
    [self pushViewController:(self.mainView = [[DOMainViewController alloc] init]) animated:NO];
    [self setDelegate:self];
}

- (void)setupBackground
{
    self.view.backgroundColor = [UIColor blackColor];
    self.backgroundImageView = [[UIImageView alloc] init];
    self.backgroundImageView.image = [[[UIImage imageNamed:@"Background"] imageWithBlur:18.0] imageWithHue: M_PI * 2]; // 0 - 2PI
    self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundImageView.userInteractionEnabled = NO;
    self.backgroundImageView.layer.zPosition = -1;

    [self.view addSubview:self.backgroundImageView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.backgroundImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.backgroundImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.backgroundImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-100],
        [self.backgroundImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:100],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(goBackToMainView)];
    [self.backgroundImageView addGestureRecognizer:tap];
}

- (void)goBackToMainView
{
    [self popToRootViewControllerAnimated:YES];
}

- (void)setBackgroundDimmed:(BOOL)dimmed
{
    [UIView animateWithDuration:0.3 animations:^{
        self.backgroundImageView.alpha = dimmed ? 0.4 : 1;
    }];
    self.backgroundImageView.userInteractionEnabled = dimmed;
}

#pragma mark - Delegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
           animationControllerForOperation:(UINavigationControllerOperation)operation
                        fromViewController:(UIViewController *)fromVC
                          toViewController:(UIViewController *)toVC {
    if (operation == UINavigationControllerOperationPush) {
        return [[DOModalTransitionPush alloc] init];
    }
    else if (operation == UINavigationControllerOperationPop) {
        return [[DOModalTransitionPop alloc] init];
    }
    return nil;
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [self setBackgroundDimmed:![viewController isKindOfClass:[DOMainViewController class]]];
}

#pragma mark - Overrides

-(CGRect)_frameForViewController:(id)viewController
{
    CGRect orig = [super _frameForViewController: viewController];
    if ([[viewController class] isEqual: [DOMainViewController class]])
        return orig;
    
    orig.size.width -= UI_MODAL_PADDING * 2;
    orig.size.height *= 0.7;
    orig.origin.x = (self.view.frame.size.width - orig.size.width) / 2;
    orig.origin.y = (self.view.frame.size.height - orig.size.height) / 2;

    return orig;

}


@end
