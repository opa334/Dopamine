//
//  DOJailbreakButton.m
//  Dopamine
//
//  Created by tomt000 on 13/01/2024.
//

#import "DOJailbreakButton.h"
#import "DODoubleHelixIndicator.h"
#import "DOUIManager.h"
#import "DOGlobalAppearance.h"
#import "DOThemeManager.h"

@implementation DOJailbreakButton

- (instancetype)initWithAction:(UIAction *)actions
{
    if (self = [super init])
    {
        self.backgroundColor = [DOThemeManager menuColorWithAlpha:1.0];
        self.layer.cornerRadius = 14;
        self.layer.masksToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        self.button = [DOActionMenuButton buttonWithAction:actions chevron:NO];
        [self.button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
        self.button.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.button];
        [NSLayoutConstraint activateConstraints:@[
            [self.button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.button.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)expandButton:(NSArray<NSLayoutConstraint *> *)constraints
{
    if (self.didExpand)
        return;

    //We're doing some setup, let's lock the mutex
    [self lockMutex];
        
    self.didExpand = TRUE;

    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    float topPadding = (window.frame.size.height * (1 - 0.74));
    topPadding += 35;
    
    [self setupLog: topPadding];
    [self setupPackageManagerPicker: topPadding];
    
    [NSLayoutConstraint deactivateConstraints:constraints];


    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
        [self.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:100] // slightly out of the screen to hide corners on i8
    ]];
    
    [self.button setUserInteractionEnabled:NO];

    [UIView animateWithDuration: 0.2 animations:^{ [self.button setAlpha:0.0]; }];
    [UIView animateWithDuration:0.75 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [window layoutIfNeeded];
        [self.button setAlpha:0.0];
    } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self setupTitle];
    });

    if ([[DOUIManager sharedInstance] enabledPackageManagerKeys].count > 0)
    {
        //we can start, unlock the mutex
        [self unlockMutex];
    }

}

- (void)setupLog: (float)topPadding
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if ([[DOUIManager sharedInstance] isDebug])
        self.logView = [[DODebugLogView alloc] init];
    else
        self.logView = [[DOLyricsLogView alloc] init];
    
    [[DOUIManager sharedInstance] setLogView:self.logView];

    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
        [self.logView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:0]
    ]];

    [window layoutIfNeeded];
}

- (void)setupPackageManagerPicker: (float)topPadding
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    if ([[DOUIManager sharedInstance] enabledPackageManagerKeys].count > 0)
        return;

    self.pkgManagerPickerView = [[DOPkgManagerPickerView alloc] initWithCallback:^(BOOL success) {
        [self.pkgManagerPickerView removeFromSuperview];
        self.logView.hidden = NO;
        [self unlockMutex];
    }];

    self.pkgManagerPickerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.pkgManagerPickerView.alpha = 0.0;

    [self addSubview:self.pkgManagerPickerView];

    [NSLayoutConstraint activateConstraints:@[
       [self.pkgManagerPickerView.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
       [self.pkgManagerPickerView.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
       [self.pkgManagerPickerView.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
       [self.pkgManagerPickerView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:0]
    ]];
    
    [UIView animateWithDuration:0.25 delay:0.25 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        self.pkgManagerPickerView.alpha = 1.0;
    } completion:nil];

    [window layoutIfNeeded];
}

- (void)setupTitle
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = DOLocalizedString(@"Status_Title_Jailbreaking");
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.alpha = 0.0;
    [self addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.centerXAnchor constraintEqualToAnchor:window.centerXAnchor constant:20],
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:20],
    ]];

    [UIView animateWithDuration:0.2 animations:^{
        titleLabel.alpha = 1.0;
    }];

    DODoubleHelixIndicator *indicator = [[DODoubleHelixIndicator alloc] init];
    [self addSubview:indicator];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [indicator.trailingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor constant:-10],
        [indicator.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [indicator.widthAnchor constraintEqualToConstant:30],
        [indicator.heightAnchor constraintEqualToConstant:12],
    ]];
}

- (void)setEnabled:(BOOL)enabled
{
    self.button.userInteractionEnabled = enabled;
    if (enabled) {
        self.alpha = 1.0;
    } else {
        self.alpha = 0.7;
    }
}

- (BOOL)isEnabled
{
    return self.button.userInteractionEnabled;
}

#pragma mark - Mutex

-(void)lockMutex
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pthread_mutex_init(&self->_canStartJailbreak, NULL);
    });
    pthread_mutex_lock(&self->_canStartJailbreak);
}

-(void)unlockMutex
{
    pthread_mutex_unlock(&self->_canStartJailbreak);
}

@end
