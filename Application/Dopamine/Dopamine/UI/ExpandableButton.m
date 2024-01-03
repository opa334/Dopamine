//
//  FancyButton.m
//  Dopamine
//
//  Created by Lars Fröder on 10.10.23.
//

#import "ExpandableButton.h"

@implementation ExpandableButton

+ (instancetype)buttonWithConfiguration:(UIButtonConfiguration *)configuration
                          primaryAction:(UIAction *)primaryAction
{
    return [[ExpandableButton alloc] initWithButton:[UIButton buttonWithConfiguration:configuration primaryAction:primaryAction]];
}

- (instancetype)initWithButton:(UIButton *)button
{
    self = [super init];
    if (self) {
        self.button = button;
    }
    return self;
}

- (void)setButton:(UIButton *)button
{
    if (_button != button) {
        if (_button) {
            [NSLayoutConstraint deactivateConstraints:_buttonConstraints];
            [_button removeFromSuperview];
        }
        
        _button = button;
        [_button addObserver:self forKeyPath:@"enabled" options:0 context:NULL];
        
        _button.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_button];
        _buttonConstraints = @[
            [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_button.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ];
        [NSLayoutConstraint activateConstraints:_buttonConstraints];
    }
}

- (UIButton *)button
{
    return _button;
}

- (UIButtonConfiguration *)configuration
{
    return _button.configuration;
}

- (BOOL)enabled
{
    return _button.enabled;
}

- (void)setEnabled:(BOOL)enabled
{
    _button.enabled = enabled;
}

- (void)updateBackground
{
    if ([self.button isEnabled]) {
        self.backgroundColor = _enabledBackgroundColor;
    }
    else {
        self.backgroundColor = _disabledBackgroundColor;
    }
}

- (void)setDisabledBackgroundColor:(UIColor *)disabledBackgroundColor
{
    _disabledBackgroundColor = disabledBackgroundColor;
    [self updateBackground];
}

- (void)setEnabledBackgroundColor:(UIColor *)enabledBackgroundColor
{
    _enabledBackgroundColor = enabledBackgroundColor;
    [self updateBackground];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context
{
    if (object == _button) {
        [self updateBackground];
    }
}

@end
