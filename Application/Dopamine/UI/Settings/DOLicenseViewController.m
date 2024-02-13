//
//  DOLicenseViewController.m
//  Dopamine
//
//  Created by Mac on 13/02/2024.
//

#import "DOLicenseViewController.h"
#import "DOPSListController.h"
#import "DOPSListItemsController.h"

@interface DOLicenseViewController ()

@end

@implementation DOLicenseViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [DOPSListController setupViewControllerStyle:self];

    UIView *header = [DOPSListItemsController makeHeader:@"License" withTarget:self];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:5],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:70]
    ]]; 
    
    UITextView *license = [[UITextView alloc] init];
    license.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:license];

    [NSLayoutConstraint activateConstraints:@[
        [license.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [license.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [license.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [license.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:0]
    ]];

    NSString *licenseText = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"LICENSE" ofType:@"md"] encoding:NSUTF8StringEncoding error:nil];
    license.text = [NSString stringWithFormat:@"\n%@", licenseText];
    license.editable = NO;
    license.font = [UIFont systemFontOfSize:14];
    license.textColor = [UIColor whiteColor];
    license.backgroundColor = [UIColor clearColor];
}

- (void)dismiss {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
