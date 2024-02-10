//
//  DOAppSwitch.m
//  Dopamine
//
//  Created by tomt000 on 08/02/2024.
//

#import "DOAppSwitch.h"

@interface DOAppSwitch ()

@property (strong, nonatomic) UIImageView *iconView;
@property (strong, nonatomic) UIStackView *stackView;
@property (strong, nonatomic) UIImageView *selector;
@property (strong, nonatomic) UIImpactFeedbackGenerator *hapticGenerator;


@end

#define TITLE_HEIGHT 40
#define CIRCLE_SIZE 19

@implementation DOAppSwitch

-(id)initWithIcon:(UIImage *)icon title:(NSString *)title {
    self = [super init];
    if (self) {
        self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        
        self.iconView = [[UIImageView alloc] initWithImage:icon];
        self.iconView.layer.masksToBounds = YES;
        self.iconView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconView.layer.cornerCurve = kCACornerCurveContinuous;
        self.iconView.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:self.iconView];

        [NSLayoutConstraint activateConstraints:@[
            [self.iconView.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-TITLE_HEIGHT],
            [self.iconView.widthAnchor constraintEqualToAnchor:self.iconView.heightAnchor],
            [self.iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.iconView.topAnchor constraintEqualToAnchor:self.topAnchor]
        ]];

        UIStackView *stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.alignment = UIStackViewAlignmentCenter;
        stackView.spacing = 7;
        stackView.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *label = [[UILabel alloc] init];
        label.text = title;
        label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        label.textColor = [UIColor colorWithWhite:1.0 alpha:1.0];

        self.selector = [[UIImageView alloc] init];
        self.selector.translatesAutoresizingMaskIntoConstraints = NO;

        [stackView addArrangedSubview:label];
        [stackView addArrangedSubview:self.selector];

        [self addSubview:stackView];

        [NSLayoutConstraint activateConstraints:@[
            [stackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [stackView.heightAnchor constraintEqualToConstant:TITLE_HEIGHT],
            [self.selector.widthAnchor constraintEqualToConstant:CIRCLE_SIZE],
            [self.selector.heightAnchor constraintEqualToAnchor:label.heightAnchor]
        ]];

        [self setSelected:NO];
    }
    return self;
}

-(void)layoutSubviews {
    [super layoutSubviews];
    self.iconView.layer.cornerRadius = (10.0 / 57.0) * self.iconView.bounds.size.width;
}

-(void)setSelected:(BOOL)selected {
    _selected = selected;
    self.selector.image = selected ? [UIImage systemImageNamed:@"checkmark.circle.fill"] : [UIImage systemImageNamed:@"circle"];
    self.selector.tintColor = selected ? [UIColor whiteColor] : [UIColor colorWithWhite:1.0 alpha:0.5];
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.hapticGenerator impactOccurred];
    self.iconView.alpha = 0.75;
}

-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [UIView animateWithDuration:0.2 animations:^{
        self.iconView.alpha = 1.0;
    }];
    [self setSelected:!self.selected];
    if (self.onSwitch) {
        self.onSwitch(self.selected);
    }
}

-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [UIView animateWithDuration:0.2 animations:^{
        self.iconView.alpha = 1.0;
    }];
}

@end
