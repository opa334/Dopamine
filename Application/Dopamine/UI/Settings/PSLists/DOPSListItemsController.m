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
