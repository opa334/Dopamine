//
//  FancyButton.h
//  Dopamine
//
//  Created by Lars Fröder on 10.10.23.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExpandableButton : UIView
{
    UIButton *_button;
    NSArray *_buttonConstraints;
}

+ (instancetype)buttonWithConfiguration:(UIButtonConfiguration *)configuration
                          primaryAction:(UIAction *)primaryAction;

@property (nonatomic, readonly) UIButtonConfiguration *configuration;
@property (nonatomic) BOOL enabled;

@property (nonatomic) UIColor *enabledBackgroundColor;
@property (nonatomic) UIColor *disabledBackgroundColor;

@property (nonatomic) UIButton *button;
@property (nonatomic) UIView *expandedView;

@end

NS_ASSUME_NONNULL_END
