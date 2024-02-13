//
//  DOPSListItemsController.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOPSListItemsController.h"

@interface DOPSListItemsController ()

@end

@implementation DOPSListItemsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    self.view.layer.cornerRadius = 16;
    self.view.layer.masksToBounds = YES;
    self.view.layer.cornerCurve = kCACornerCurveContinuous;
    
    [_table setSeparatorColor:[UIColor clearColor]];
    [_table setBackgroundColor:[UIColor clearColor]];
    
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = [UIColor colorWithRed: 71.0/255.0 green: 169.0/255.0 blue: 135.0/255.0 alpha: 1.0];
    [self setupHeader: ((PSSpecifier*)self.specifier).name];
}

- (void)setupHeader:(NSString *)title
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 70)];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 60)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];

    UIView *border = [[UIView alloc] init];
    border.translatesAutoresizingMaskIntoConstraints = NO;
    border.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [header addSubview:border];

    UIImage *backImage = [UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
    backImage = [backImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [backButton setImage:backImage forState:UIControlStateNormal];
    [backButton setTintColor:[UIColor colorWithWhite:1.0 alpha:0.6]];
    [backButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:backButton];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:-8],
        [label.centerXAnchor constraintEqualToAnchor:header.centerXAnchor]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [border.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [border.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [border.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],
        [border.heightAnchor constraintEqualToConstant:1]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [backButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:10],
        [backButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:-7],
        [backButton.widthAnchor constraintEqualToConstant:30],
        [backButton.heightAnchor constraintEqualToConstant:30]
    ]];

    _table.tableHeaderView = header;
}

- (void)dismiss {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor clearColor];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _table.frame = CGRectMake(12, 5, self.view.bounds.size.width - 24, self.view.bounds.size.height - 10);
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}


@end
