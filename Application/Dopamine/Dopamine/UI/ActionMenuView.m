//
//  ActionMenuView.m
//  Dopamine
//
//  Created by Lars Fröder on 07.10.23.
//

#import "ActionMenuView.h"

#import "GlobalAppearance.h"

@interface ActionMenuView ()
@property NSArray *actionButtons;
@property NSArray *chevronButtons;
@property NSArray *actionSeperators;
@end

@implementation ActionMenuView

- (instancetype)initWithActions:(NSArray<UIAction*> *)actions delegate:(id<ActionMenuDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        [self updateActions:actions];
    }
    return self;
}

- (void)updateActions:(NSArray<UIAction*> *)actions
{
    [self cleanUp];
    
    UIColor *grayToUse = [[UIColor systemGrayColor] colorWithAlphaComponent:0.8];
    
    NSMutableArray *actionButtons = [NSMutableArray new];
    NSMutableArray *chevronButtons = [NSMutableArray new];
    NSMutableArray *actionSeperators = [NSMutableArray new];
    NSMutableArray *constraints = [NSMutableArray new];

    for (UIAction *action in actions) {
        NSInteger actionIndex = [actions indexOfObject:action];
        UIButton *actionButton = [UIButton buttonWithConfiguration:[GlobalAppearance defaultButtonConfiguration] primaryAction:action];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        actionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        
        UIButton *prevButton = nil;
        if (actionIndex > 0) {
            prevButton = actionButtons[actionIndex - 1];
        }
        
        BOOL lastButton = (actionIndex == (actions.count-1));
        BOOL firstButton = !(BOOL)prevButton;
        
        if (firstButton) {
            [constraints addObjectsFromArray:@[[actionButton.topAnchor constraintEqualToAnchor:self.topAnchor]]];
        }
        else {
            [constraints addObjectsFromArray:@[[actionButton.topAnchor constraintEqualToAnchor:prevButton.bottomAnchor],
                                               [actionButton.heightAnchor constraintEqualToAnchor:prevButton.heightAnchor]]];
            if (lastButton) {
                [constraints addObjectsFromArray:@[[actionButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
            }
            
            UIView *separatorView = [[UIView alloc] init];
            separatorView.translatesAutoresizingMaskIntoConstraints = NO;
            separatorView.backgroundColor = grayToUse;
            [actionSeperators addObject:separatorView];
            
            [constraints addObjectsFromArray:@[[separatorView.topAnchor constraintEqualToAnchor:actionButton.topAnchor],
                                                 [separatorView.heightAnchor constraintEqualToConstant:1],
                                                 [separatorView.widthAnchor constraintEqualToAnchor:actionButton.widthAnchor],
                                                 [separatorView.centerXAnchor constraintEqualToAnchor:actionButton.centerXAnchor]]];
        }
        
        [constraints addObjectsFromArray:@[[actionButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                                          [actionButton.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.8]]];
        [actionButtons addObject:actionButton];
        
        if ([_delegate actionMenuShowsChevronForAction:action]) {
            UIImage *chevronImage = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[GlobalAppearance smallIconImageConfiguration]];
            UIButtonConfiguration *chevronButtonConfig = [GlobalAppearance defaultButtonConfiguration];
            chevronButtonConfig.image = chevronImage;
            chevronButtonConfig.baseForegroundColor = grayToUse;
            UIButton *chevronButton = [UIButton buttonWithConfiguration:chevronButtonConfig primaryAction:nil];
            chevronButton.translatesAutoresizingMaskIntoConstraints = NO;
            chevronButton.userInteractionEnabled = NO;
            
            chevronButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
            [constraints addObjectsFromArray:@[[chevronButton.trailingAnchor constraintEqualToAnchor:actionButton.trailingAnchor],
                                              [chevronButton.topAnchor constraintEqualToAnchor:actionButton.topAnchor],
                                              [chevronButton.heightAnchor constraintEqualToAnchor:actionButton.heightAnchor],
                                              [chevronButton.widthAnchor constraintEqualToConstant:50]]];
            [chevronButtons addObject:chevronButton];
        }
    }
    
    for (UIView *view in actionButtons) {
        [self addSubview:view];
    }
    for (UIView *view in chevronButtons) {
        [self addSubview:view];
    }
    for (UIView *view in actionSeperators) {
        [self addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    
    _actionButtons = actionButtons;
    _chevronButtons = chevronButtons;
    _actionSeperators = actionSeperators;
    _activeConstraints = constraints;
    
}

- (void)cleanUp
{
    if (_activeConstraints) {
        [NSLayoutConstraint deactivateConstraints:_activeConstraints];
        _activeConstraints = nil;
    }
    
    if (_actionButtons) {
        for (UIButton *actionButton in _actionButtons) {
            [actionButton removeFromSuperview];
        }
        _actionButtons = nil;
    }
    if (_chevronButtons) {
        for (UIButton *chevronButton in _chevronButtons) {
            [chevronButton removeFromSuperview];
        }
        _chevronButtons = nil;
    }
    if (_actionSeperators) {
        for (UIButton *actionSeperator in _actionSeperators) {
            [actionSeperator removeFromSuperview];
        }
        _actionSeperators = nil;
    }
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
