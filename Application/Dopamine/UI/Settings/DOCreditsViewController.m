//
//  DOCreditsViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOCreditsViewController.h"
#import "DOLicenseViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import <Preferences/PSSpecifier.h>

@interface DOCreditsViewController ()

@end

@implementation DOCreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Credits" target:self];

        PSSpecifier *headerSpecifier = _specifiers[0];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Dopamine %@ - %@", [DOEnvironmentManager sharedManager].appVersionDisplayString, DOLocalizedString(@"Menu_Credits_Title")] forKey:@"title"];
    }
    return _specifiers;
}

- (void)openSourceCode
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/opa334/Dopamine"] options:@{} completionHandler:nil];
}

- (void)openDiscord
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://discord.gg/jb"] options:@{} completionHandler:nil];
}

- (void)openLicense
{
    [self.navigationController pushViewController:[[DOLicenseViewController alloc] init] animated:YES];
}

@end
