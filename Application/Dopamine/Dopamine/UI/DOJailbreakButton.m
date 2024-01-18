//
//  DOJailbreakButton.m
//  Dopamine
//
//  Created by tomt000 on 13/01/2024.
//

#import "DOJailbreakButton.h"
#import "DODoubleHelixIndicator.h"


@implementation DOJailbreakButton

- (instancetype)initWithAction:(UIAction *)actions
{
    if (self = [super init])
    {
        self.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.45];
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

- (void)showLog:(NSArray<NSLayoutConstraint *> *)constraints
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    [NSLayoutConstraint deactivateConstraints:constraints];

    float topPadding = (window.frame.size.height * (1 - 0.74));
    topPadding += 55;

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
    [self setupLog: topPadding];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self setupTitle];
    });
}

-(void)setupLog: (float)topPadding
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    self.logView = [[DOLyricsLogView alloc] init];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logView.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:window.topAnchor constant:topPadding],
        [self.logView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:0]
    ]];

    [self simulateJailbreak: self.logView];
}

-(void)setupTitle
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Jailbreaking";
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

-(void)simulateJailbreak: (UIView<DOLogViewProtocol>*)log
{
    // Let's simulate a jailbreak using grand central dispatch
    static BOOL didFinish = NO;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [log didComplete];
        didFinish = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.2];
        [log showLog:@"Launching kexploitd"];
        [NSThread sleepForTimeInterval:0.7];
        [log showLog:@"Launching oobPCI"];
        [NSThread sleepForTimeInterval:0.15];
        [log showLog:@"Gaining r/w"];
        [NSThread sleepForTimeInterval:1.5];
        [log showLog:@"Patchfinding"];
        NSArray *types = @[@"AMFI", @"PAC", @"KTRR", @"KPP", @"PPL", @"KPF", @"APRR", @"AMCC", @"PAN", @"PXN", @"ASLR", @"OPA"]; //Ever heard of the legendary opa bypass
        while (true)
        {
            [NSThread sleepForTimeInterval:1.0 * rand() / RAND_MAX];
            if (didFinish) break;
            NSString *type = types[arc4random_uniform((uint32_t)types.count)];
            [log showLog:[NSString stringWithFormat:@"Bypassing %@", type]];
        }
    });
}

@end
