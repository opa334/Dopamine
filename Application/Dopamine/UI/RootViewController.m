//
//  ViewController.m
//  Dopamine
//
//  Created by Lars Fröder on 23.09.23.
//

#import "RootViewController.h"
#import "ActionMenuView.h"

#import "EnvironmentManager.h"
#import "Jailbreaker.h"

#import "GlobalAppearance.h"
#import "UIImage+Blur.h"

@interface RootViewController ()

@property (nonatomic) UIImageView *backgroundImageView;
@property (nonatomic) UIVisualEffectView *backgroundBlurView;

@property (nonatomic) UIImageView *titleView;
@property (nonatomic) UILabel *subtitleLabel;

@property (nonatomic) ActionMenuView *actionView;

@property (nonatomic) ExpandableButton *jailbreakButton;
@property (nonatomic) UIView *jailbreakButtonPlaceholder;
@property (nonatomic) UIButton *updateButton;


@property (nonatomic) BOOL updateIsAvailable;
@end

@implementation RootViewController

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (void)setUpBackground
{
    _backgroundImageView = [[UIImageView alloc] init];
    _backgroundImageView.image = [[UIImage imageNamed:@"Background"] imageWithBlur:18.0];
    _backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    _backgroundImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_backgroundImageView];
    
    [NSLayoutConstraint activateConstraints:@[
        [_backgroundImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_backgroundImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_backgroundImageView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:-100],
        [_backgroundImageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:100],
    ]];
}

- (void)setUpSubviews
{
    _containerView = [[UIView alloc] init];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    _containerView.clipsToBounds = NO;
    
    _jailbreakButtonPlaceholder = [[UIView alloc] init];
    _jailbreakButtonPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    _jailbreakButtonPlaceholder.userInteractionEnabled = NO;
    
    UIImage *jailbreakImage = [UIImage systemImageNamed:@"lock.open" withConfiguration:[GlobalAppearance smallIconImageConfiguration]];
    _jailbreakButton = [ExpandableButton buttonWithConfiguration:[GlobalAppearance defaultButtonConfigurationWithImagePadding:5] primaryAction:[UIAction actionWithTitle:@"Jailbreak" image:jailbreakImage identifier:@"jailbreak" handler:^(__kindof UIAction * _Nonnull action) {
        //self.updateIsAvailable = !self.updateIsAvailable;
        [self setJailbreakButtonExpanded:!self.jailbreakButtonExpanded animated:YES];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void){
            Jailbreaker *jailbreaker = [[Jailbreaker alloc] init];
            
            NSString *title;
            NSString *message;
            NSError *error = [jailbreaker run];
            if (error) {
                NSLog(@"FAIL: %@", error);
                title = @"Error";
                message = error.localizedDescription;
            }
            else {
                title = @"Success";
                //message = @"The device should panic with a corrupted TTE when killing the app.";
                message = @"";
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:nil];
                [alertController addAction:doneAction];
                
                [self presentViewController:alertController animated:YES completion:nil];
            });
        });
    }]];
    _jailbreakButton.translatesAutoresizingMaskIntoConstraints = NO;
    _jailbreakButton.configuration.imagePadding = 100;
    _jailbreakButton.enabledBackgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    _jailbreakButton.disabledBackgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    
    UIImage *updateImage = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[GlobalAppearance smallIconImageConfiguration]];
    _updateButton = [UIButton buttonWithConfiguration:[GlobalAppearance defaultButtonConfigurationWithImagePadding:5] primaryAction:[UIAction actionWithTitle:@"Update Available" image:updateImage identifier:@"update" handler:^(__kindof UIAction * _Nonnull action) {
    }]];
    _updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    _updateButton.hidden = YES;
    _updateButton.alpha = 0.0;
    
    _actionView = [[ActionMenuView alloc] initWithActions:@[
        [UIAction actionWithTitle:@"Settings" image:[UIImage systemImageNamed:@"gear" withConfiguration:[GlobalAppearance smallIconImageConfiguration]] identifier:@"settings" handler:^(__kindof UIAction * _Nonnull action) {
        }],
        [UIAction actionWithTitle:@"Respring" image:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:[GlobalAppearance smallIconImageConfiguration]] identifier:@"respring" handler:^(__kindof UIAction * _Nonnull action) {
        }],
        [UIAction actionWithTitle:@"Reboot Userspace" image:[UIImage systemImageNamed:@"arrow.clockwise.circle" withConfiguration:[GlobalAppearance smallIconImageConfiguration]] identifier:@"reboot-userspace" handler:^(__kindof UIAction * _Nonnull action) {
        }],
        [UIAction actionWithTitle:@"Credits" image:[UIImage systemImageNamed:@"info.circle" withConfiguration:[GlobalAppearance smallIconImageConfiguration]] identifier:@"credits" handler:^(__kindof UIAction * _Nonnull action) {
        }]
    ] delegate:self];
    _actionView.translatesAutoresizingMaskIntoConstraints = NO;
    _actionView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    _actionView.layer.cornerRadius = 16;
    
    _titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Dopamine"]];
    _titleView.contentMode = UIViewContentModeScaleAspectFit;
    //[_titleView setValue:@1 forKeyPath:@"alignTop"];
    _titleView.translatesAutoresizingMaskIntoConstraints = NO;
    
    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.text = [NSString stringWithFormat:@"for %@\nby opa334, ElleKit by évelyne", [[EnvironmentManager sharedManager] versionSupportString]];
    _subtitleLabel.font = [_subtitleLabel.font fontWithSize:12];
    _subtitleLabel.textColor = [UIColor whiteColor];
    
    [_containerView addSubview:_titleView];
    [_containerView addSubview:_subtitleLabel];
    [_containerView addSubview:_actionView];
    [_containerView addSubview:_jailbreakButtonPlaceholder];
    [_containerView addSubview:_updateButton];
    
    _spaceView1 = [[UIView alloc] init];
    _spaceView2 = [[UIView alloc] init];
    _spaceView1.translatesAutoresizingMaskIntoConstraints = NO;
    _spaceView2.translatesAutoresizingMaskIntoConstraints = NO;
    [_containerView addSubview:_spaceView1];
    [_containerView addSubview:_spaceView2];
    
    [self.view addSubview:_containerView];
    [self.view addSubview:_jailbreakButton];
}

- (void)setUpConstraints
{
    CGFloat edgeSize = 25;
    
    NSArray *lowerPriorityConstraints = @[
        [_containerView.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [_containerView.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [_containerView.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor],
        [_containerView.heightAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.heightAnchor],
    ];
    for (NSLayoutConstraint *constraint in lowerPriorityConstraints) {
        constraint.priority = 900;
    }
    [NSLayoutConstraint activateConstraints:lowerPriorityConstraints];
    
    [NSLayoutConstraint activateConstraints:@[
        [_containerView.widthAnchor constraintLessThanOrEqualToConstant:500],
        [_containerView.heightAnchor constraintLessThanOrEqualToConstant:900],
    ]];
    
    _titleViewConstraints = @[
        // Horizontal
        [_titleView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:(edgeSize+10)],
        [_titleView.widthAnchor constraintEqualToAnchor:_titleView.heightAnchor multiplier:_titleView.image.size.width / _titleView.image.size.height],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleView.leadingAnchor],
        
        // Vertical
        [_titleView.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:(edgeSize)],
        [_titleView.heightAnchor constraintEqualToConstant:40],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleView.bottomAnchor constant:5],
    ];
    
    _actionViewContraints = @[
        // Horizontal
        [_actionView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:edgeSize],
        [_actionView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-edgeSize],
        
        [_spaceView1.heightAnchor constraintGreaterThanOrEqualToConstant:10],
        [_spaceView2.heightAnchor constraintEqualToAnchor:_spaceView1.heightAnchor],
        
        [_actionView.heightAnchor constraintEqualToAnchor:_containerView.heightAnchor multiplier:0.45],
        
        [_actionView.topAnchor constraintEqualToAnchor:_spaceView1.bottomAnchor],
        [_actionView.bottomAnchor constraintEqualToAnchor:_spaceView2.topAnchor],
        
        [_spaceView1.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor],
        [_spaceView2.bottomAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.topAnchor],
    ];

    _jailbreakButtonPlaceholderContraints = @[
        // Horizontal
        [_jailbreakButtonPlaceholder.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:edgeSize],
        [_jailbreakButtonPlaceholder.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-edgeSize],
        
        // Vertical
        [_jailbreakButtonPlaceholder.heightAnchor constraintEqualToConstant:50],
    ];
    
    _updateButtonConstraints = @[
        // Horizontal
        [_updateButton.centerXAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.centerXAnchor],

        // Vertical
        [_updateButton.topAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.bottomAnchor constant:10],
    ];
    
    _updateButtonEnabledContraints = @[
        // Vertical
        [_jailbreakButtonPlaceholder.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-50],
    ];
    
    _updateButtonDisabledContraints = @[
        // Vertical
        [_jailbreakButtonPlaceholder.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-30],
    ];
    
    _jailbreakButtonAttachedConstraints = @[
        [_jailbreakButton.topAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.topAnchor],
        [_jailbreakButton.bottomAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.bottomAnchor],
        [_jailbreakButton.trailingAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.trailingAnchor],
        [_jailbreakButton.leadingAnchor constraintEqualToAnchor:_jailbreakButtonPlaceholder.leadingAnchor],
    ];
    
    _jailbreakButtonExpandedConstraints = @[
        [_jailbreakButton.topAnchor constraintEqualToAnchor:_spaceView1.centerYAnchor],
        [_jailbreakButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_jailbreakButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_jailbreakButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    ];
    
    [NSLayoutConstraint activateConstraints:_titleViewConstraints];
    [NSLayoutConstraint activateConstraints:_jailbreakButtonPlaceholderContraints];
    [NSLayoutConstraint activateConstraints:_actionViewContraints];
    
    [NSLayoutConstraint activateConstraints:_updateButtonConstraints];
    [NSLayoutConstraint activateConstraints:_updateButtonDisabledContraints];
    
    self.jailbreakButtonExpanded = NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _updateIsAvailable = NO;
    
    [self setUpBackground];
    [self setUpSubviews];
    [self setUpConstraints];
}

- (void)setUpdateIsAvailable:(BOOL)updateIsAvailable
{
    _updateIsAvailable = updateIsAvailable;
    
    if (self->_updateIsAvailable) {
        self->_updateButton.hidden = NO;
    }
    [UIView animateWithDuration:0.5 delay:0
                        options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut)
                     animations:^
    {
        if (self->_updateIsAvailable) {
            self->_updateButton.alpha = 1.0;
            [NSLayoutConstraint deactivateConstraints:self->_updateButtonDisabledContraints];
            [NSLayoutConstraint activateConstraints:self->_updateButtonEnabledContraints];
        }
        else {
            self->_updateButton.alpha = 0.0;
            [NSLayoutConstraint deactivateConstraints:self->_updateButtonEnabledContraints];
            [NSLayoutConstraint activateConstraints:self->_updateButtonDisabledContraints];
        }
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (!self->_updateIsAvailable && finished) {
            self->_updateButton.hidden = YES;
        }
    }];
}

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)jailbreakButtonExpanded
{
    return _jailbreakButtonExpanded;
}

- (void)setJailbreakButtonExpanded:(BOOL)jailbreakButtonExpanded
{
    [self setJailbreakButtonExpanded:jailbreakButtonExpanded animated:NO];
}

- (void)setJailbreakButtonExpanded:(BOOL)expanded animated:(BOOL)animated
{
    _jailbreakButtonExpanded = expanded;
    if (!expanded) {
        self->_actionView.hidden = NO;
        self->_jailbreakButton.layer.maskedCorners = (kCALayerMaxXMaxYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMinXMinYCorner);
    }

    void (^animationHandler)(void) = ^{
        if (expanded) {
            self->_jailbreakButton.layer.cornerRadius = 16;
            self->_actionView.alpha = 0;
            [NSLayoutConstraint deactivateConstraints:self->_jailbreakButtonAttachedConstraints];
            [NSLayoutConstraint activateConstraints:self->_jailbreakButtonExpandedConstraints];
        }
        else {
            self->_jailbreakButton.layer.cornerRadius = 8;
            self->_actionView.alpha = 1;
            [NSLayoutConstraint deactivateConstraints:self->_jailbreakButtonExpandedConstraints];
            [NSLayoutConstraint activateConstraints:self->_jailbreakButtonAttachedConstraints];
        }
        [self.view layoutIfNeeded];
    };
    
    void (^completionHandler)(BOOL) = ^(BOOL finished) {
        if (finished) {
            if (expanded) {
                self->_actionView.hidden = YES;
                self->_jailbreakButton.layer.maskedCorners = (kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner);
            }
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.3 delay:0
                            options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut)
                         animations:animationHandler completion:completionHandler];
    }
    else {
        animationHandler();
        completionHandler(YES);
    }
}

@end
