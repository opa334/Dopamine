//
//  DOActionMenuButton.m
//  Dopamine
//
//  Created by tomt000 on 07/01/2024.
//

#import "DOActionMenuButton.h"
#import "DOGlobalAppearance.h"

@interface DOActionMenuButton () {
    UIView *_separator;
}

@property (nonatomic) UIImpactFeedbackGenerator *feedbackGenerator;

@end

@implementation DOActionMenuButton 

+(DOActionMenuButton*)buttonWithAction:(UIAction *)action chevron:(BOOL)chevron
{
    DOActionMenuButton *button = [DOActionMenuButton buttonWithConfiguration:[DOGlobalAppearance defaultButtonConfiguration] primaryAction:action];
    [button.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];

    if ([DOGlobalAppearance isRTL])
        [button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentRight];

    if (chevron)
    {
        UIImage *chevronImage = [UIImage systemImageNamed:@"chevron.right"];
        chevronImage = [chevronImage imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular]];
        UIImageView *chevronView = [[UIImageView alloc] initWithImage:chevronImage];
        chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        chevronView.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
        [button addSubview:chevronView];
        [NSLayoutConstraint activateConstraints:@[
            [chevronView.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-10],
            [chevronView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        ]];
    }

    button.feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [button addTarget:button action:@selector(buttonPressed) forControlEvents:UIControlEventTouchUpInside];

    return button;
}

-(void)buttonPressed
{
    [self.feedbackGenerator impactOccurred];
}

-(void)setBottomSeparator:(BOOL)bottomSeparator
{
    _bottomSeparator = bottomSeparator;
    if (_separator)
        [_separator removeFromSuperview];
    if (bottomSeparator)
    {
        _separator = [[UIView alloc] init];
        _separator.backgroundColor = [UIColor colorWithWhite:0.6 alpha:0.3];
        _separator.translatesAutoresizingMaskIntoConstraints = NO;
        _separator.layer.cornerRadius = 0.5;
        _separator.layer.masksToBounds = YES;
        [self addSubview:_separator];
        [NSLayoutConstraint activateConstraints:@[
            [_separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_separator.heightAnchor constraintEqualToConstant:1],
        ]];
    }
}

@end
