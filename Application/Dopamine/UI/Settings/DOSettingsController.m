//
//  DOSettingsController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOSettingsController.h"
#import <objc/runtime.h>
#import "DOUIManager.h"

@interface DOSettingsController ()

@end

@implementation DOSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (id)specifiers {
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Settings" target:self];
    }
    return _specifiers;
}

#pragma mark - Button Actions

-(void)hideJailbreak
{
    //TODO
    NSLog(@"Hide Jailbreak");
}

-(void)removeJailbreak
{
    //TODO
    NSLog(@"Remove Jailbreak");
}

-(void)resetSettings
{
    [[DOUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
}

@end
