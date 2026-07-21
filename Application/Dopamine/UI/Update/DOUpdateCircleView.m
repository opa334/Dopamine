//
//  DOUpdateCircleView.m
//  Dopamine
//
//  Created by tomt000 on 06/02/2024.
//

#import "DOUpdateCircleView.h"

@interface DOUpdateCircleView ()

@property (nonatomic, strong) CAShapeLayer *circleLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, strong) UILabel *label;

@end

@implementation DOUpdateCircleView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

-(void)setup {
    self.backgroundColor = [UIColor clearColor];

    self.circleLayer = [CAShapeLayer layer];
    self.circleLayer.fillColor = [UIColor clearColor].CGColor;
    self.circleLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    self.circleLayer.lineWidth = 10.0;

    self.progressLayer = [CAShapeLayer layer];
    self.progressLayer.fillColor = [UIColor clearColor].CGColor;
    self.progressLayer.strokeColor = [UIColor whiteColor].CGColor;
    self.progressLayer.lineWidth = 10.0;
    self.progressLayer.lineCap = kCALineCapRound;

    [self.layer addSublayer:self.circleLayer];
    [self.layer addSublayer:self.progressLayer];
    
    self.label = [[UILabel alloc] initWithFrame:self.bounds];
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.textColor = [UIColor whiteColor];
    self.label.font = [UIFont systemFontOfSize:29 weight:UIFontWeightMedium];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:self.label];

    [NSLayoutConstraint activateConstraints:@[
        [self.label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.label.widthAnchor constraintEqualToAnchor:self.widthAnchor],
        [self.label.heightAnchor constraintEqualToAnchor:self.heightAnchor]
    ]];
}

- (void)setProgress:(float)progress {
    _progress = progress;
    self.label.text = [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
    [self updateCirclePaths];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateCirclePaths];
}

- (void)updateCirclePaths {
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2 - self.circleLayer.lineWidth / 2;

    CGFloat startAngle = -((float)M_PI / 2);
    CGFloat endAngle = (2 * (float)M_PI) + startAngle;

    UIBezierPath *circlePath = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
    self.circleLayer.path = circlePath.CGPath;

    UIBezierPath *progressPath = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:(endAngle - startAngle) * self.progress + startAngle clockwise:YES];
    self.progressLayer.path = progressPath.CGPath;
}


@end
