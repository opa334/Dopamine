//
//  DOLogCrashViewController.m
//  Dopamine
//
//  Created by tomt000 on 14/02/2024.
//

#import "DOLogCrashViewController.h"
#import "DOPSListController.h"
#import "DOPSListItemsController.h"
#import "DOActionMenuButton.h"
#import "DOGlobalAppearance.h"
#import "DOUIManager.h"

@interface DOLogCrashViewController ()

@property (nonatomic, retain) NSString *title;

@end

@implementation DOLogCrashViewController

- (id)initWithTitle:(NSString*)title
{
    if (self = [super init])
    {
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [DOPSListController setupViewControllerStyle:self];

    UIView *header = [DOPSListItemsController makeHeader:NSLocalizedString(@"Log_Error", nil) withTarget:self];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:5],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:70]
    ]];
    
    DOActionMenuButton *shareButton = [DOActionMenuButton buttonWithAction:[UIAction actionWithTitle:NSLocalizedString(@"Button_Share", nil) image:[UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"share" handler:^(__kindof UIAction * _Nonnull action) {
        [[DOUIManager sharedInstance] shareLogRecord];
    }] chevron:NO];
    
    shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:shareButton];

    [NSLayoutConstraint activateConstraints:@[
        [shareButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [shareButton.heightAnchor constraintEqualToConstant:30],
        [shareButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-30]
    ]];

    

    UITextView *license = [[UITextView alloc] init];
    license.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:license];

    [NSLayoutConstraint activateConstraints:@[
        [license.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [license.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [license.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [license.bottomAnchor constraintEqualToAnchor:shareButton.topAnchor constant:-10]
    ]];

    license.text = [[[DOUIManager sharedInstance] logRecord] componentsJoinedByString:@"\n"];
    license.editable = NO;
    license.font = [UIFont systemFontOfSize:14];
    license.textColor = [UIColor whiteColor];
    license.backgroundColor = [UIColor clearColor];


    [[[DOUIManager sharedInstance] logRecord] insertObject:self.title atIndex:0];
    [[[DOUIManager sharedInstance] logRecord] insertObject:@"----" atIndex:1];
}

- (void)dismiss
{
    [self.navigationController popViewControllerAnimated:YES];
}


@end
