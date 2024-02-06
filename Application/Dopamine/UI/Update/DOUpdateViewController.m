//
//  DOUpdateViewController.m
//  Dopamine
//
//  Created by tomt000 on 06/02/2024.
//

#import "DOUpdateViewController.h"
#import "DOUpdateCircleView.h"

@interface DOUpdateViewController ()

@end

@implementation DOUpdateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    DOUpdateCircleView *circleView = [[DOUpdateCircleView alloc] initWithFrame:CGRectNull];
    circleView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:circleView];

    [NSLayoutConstraint activateConstraints:@[
        [circleView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [circleView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [circleView.widthAnchor constraintEqualToConstant:140],
        [circleView.heightAnchor constraintEqualToConstant:140]
    ]];

    [circleView setProgress:0.4];

}



@end
