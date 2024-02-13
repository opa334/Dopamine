//
//  DOSettingsController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOSettingsController.h"
#import <objc/runtime.h>
#import <libjailbreak/util.h>
#import "DOUIManager.h"
#import "DOPkgManagerPickerViewController.h"
#import "DOHeaderCell.h"
#import "DOEnvironmentManager.h"
#import "DOExploitManager.h"
#import "DOPSListItemsController.h"


@interface DOSettingsController ()

@end

@implementation DOSettingsController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (NSArray *)availableKernelExploitIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [identifiers addObject:exploit.identfier];
    }
    return identifiers;
}

- (NSArray *)availableKernelExploitNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availableKernelExploits) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePACBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availablePACBypasses) {
        [identifiers addObject:exploit.identfier];
    }
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [identifiers addObject:@"none"];
    }
    return identifiers;
}

- (NSArray *)availablePACBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availablePACBypasses) {
        [names addObject:exploit.name];
    }
    if (![DOEnvironmentManager sharedManager].isPACBypassRequired) {
        [names addObject:@"None"];
    }
    return names;
}

- (NSArray *)availablePPLBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [identifiers addObject:exploit.identfier];
    }
    return identifiers;
}

- (NSArray *)availablePPLBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (DOExploit *exploit in _availablePPLBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (id)specifiers
{
    if(_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray new];
        DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
        DOExploitManager *exploitManager = [DOExploitManager sharedManager];
        
        SEL defGetter = @selector(readPreferenceValue:);
        SEL defSetter = @selector(setPreferenceValue:specifier:);
        
        _availableKernelExploits = [exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL].allObjects;
        if (envManager.isArm64e) {
            _availablePACBypasses = [exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC].allObjects;
            _availablePPLBypasses = [exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL].allObjects;
        }
        
        PSSpecifier *headerSpecifier = [PSSpecifier emptyGroupSpecifier];
        [headerSpecifier setProperty:@"DOHeaderCell" forKey:@"headerCellClass"];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Settings"] forKey:@"title"];
        [specifiers addObject:headerSpecifier];
        
        if (!envManager.isJailbroken) {
            PSSpecifier *exploitGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            exploitGroupSpecifier.name = @"Exploits";
            [specifiers addObject:exploitGroupSpecifier];
        
            PSSpecifier *kernelExploitSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Kernel Exploit" target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
            [kernelExploitSpecifier setProperty:@YES forKey:@"enabled"];
            [kernelExploitSpecifier setProperty:exploitManager.preferredKernelExploit.identfier forKey:@"default"];
            kernelExploitSpecifier.detailControllerClass = [DOPSListItemsController class];
            [kernelExploitSpecifier setProperty:@"availableKernelExploitIdentifiers" forKey:@"valuesDataSource"];
            [kernelExploitSpecifier setProperty:@"availableKernelExploitNames" forKey:@"titlesDataSource"];
            [kernelExploitSpecifier setProperty:@"selectedKernelExploit" forKey:@"key"];
            [specifiers addObject:kernelExploitSpecifier];
            
            if (envManager.isArm64e) {
                PSSpecifier *pacBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:@"PAC Bypass" target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
                [pacBypassSpecifier setProperty:@YES forKey:@"enabled"];
                if (!envManager.isPACBypassRequired) {
                    [pacBypassSpecifier setProperty:@"none" forKey:@"default"];
                }
                else {
                    [pacBypassSpecifier setProperty:exploitManager.preferredPACBypass.identfier forKey:@"default"];
                }
                pacBypassSpecifier.detailControllerClass = [DOPSListItemsController class];
                [pacBypassSpecifier setProperty:@"availablePACBypassIdentifiers" forKey:@"valuesDataSource"];
                [pacBypassSpecifier setProperty:@"availablePACBypassNames" forKey:@"titlesDataSource"];
                [pacBypassSpecifier setProperty:@"selectedPACBypass" forKey:@"key"];
                [specifiers addObject:pacBypassSpecifier];
                
                PSSpecifier *pplBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:@"PPL Bypass" target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
                [pplBypassSpecifier setProperty:@YES forKey:@"enabled"];
                [pplBypassSpecifier setProperty:exploitManager.preferredPPLBypass.identfier forKey:@"default"];
                pplBypassSpecifier.detailControllerClass = [DOPSListItemsController class];
                [pplBypassSpecifier setProperty:@"availablePPLBypassIdentifiers" forKey:@"valuesDataSource"];
                [pplBypassSpecifier setProperty:@"availablePPLBypassNames" forKey:@"titlesDataSource"];
                [pplBypassSpecifier setProperty:@"selectedPPLBypass" forKey:@"key"];
                [specifiers addObject:pplBypassSpecifier];
            }
        }
        
        PSSpecifier *settingsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        settingsGroupSpecifier.name = @"Jailbreak Settings";
        [specifiers addObject:settingsGroupSpecifier];
        
        PSSpecifier *tweakInjectionSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Tweak Injection" target:self set:@selector(setTweakInjectionEnabled:specifier:) get:@selector(readTweakInjectionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [tweakInjectionSpecifier setProperty:@YES forKey:@"enabled"];
        [tweakInjectionSpecifier setProperty:@"tweakInjectionEnabled" forKey:@"key"];
        [tweakInjectionSpecifier setProperty:@YES forKey:@"default"];
        [specifiers addObject:tweakInjectionSpecifier];
        
        if (!envManager.isJailbroken) {
            PSSpecifier *verboseLogSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Verbose Logs" target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
            [verboseLogSpecifier setProperty:@YES forKey:@"enabled"];
            [verboseLogSpecifier setProperty:@"verboseLogsEnabled" forKey:@"key"];
            [verboseLogSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:verboseLogSpecifier];
        }
        
        PSSpecifier *idownloadSpecifier = [PSSpecifier preferenceSpecifierNamed:@"iDownload (Developer Shell)" target:self set:@selector(setIDownloadEnabled:specifier:) get:@selector(readIDownloadEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [idownloadSpecifier setProperty:@YES forKey:@"enabled"];
        [idownloadSpecifier setProperty:@"idownloadEnabled" forKey:@"key"];
        [idownloadSpecifier setProperty:@NO forKey:@"default"];
        [specifiers addObject:idownloadSpecifier];
        
        if (!envManager.isJailbroken && !envManager.isInstalledThroughTrollStore) {
            PSSpecifier *removeJailbreakSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Remove Jailbreak" target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
            [removeJailbreakSwitchSpecifier setProperty:@YES forKey:@"enabled"];
            [removeJailbreakSwitchSpecifier setProperty:@"removeJailbreakEnabled" forKey:@"key"];
            [specifiers addObject:removeJailbreakSwitchSpecifier];
        }
        
        if (envManager.isJailbroken || envManager.isInstalledThroughTrollStore) {
            PSSpecifier *actionsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            actionsGroupSpecifier.name = @"Actions";
            [specifiers addObject:actionsGroupSpecifier];
            
            if (envManager.isJailbroken) {
                PSSpecifier *reinstallPackageManagersSpecifier = [PSSpecifier emptyGroupSpecifier];
                reinstallPackageManagersSpecifier.target = self;
                [reinstallPackageManagersSpecifier setProperty:@"Reinstall Package Managers" forKey:@"title"];
                [reinstallPackageManagersSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                [reinstallPackageManagersSpecifier setProperty:@"shippingbox.and.arrow.backward" forKey:@"image"];
                [reinstallPackageManagersSpecifier setProperty:@"reinstallPackageManagersPressed" forKey:@"action"];
                [specifiers addObject:reinstallPackageManagersSpecifier];
                
                PSSpecifier *refreshAppsSpecifier = [PSSpecifier emptyGroupSpecifier];
                refreshAppsSpecifier.target = self;
                [refreshAppsSpecifier setProperty:@"Refresh Jailbreak Apps" forKey:@"title"];
                [refreshAppsSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                [refreshAppsSpecifier setProperty:@"arrow.triangle.2.circlepath" forKey:@"image"];
                [refreshAppsSpecifier setProperty:@"refreshJailbreakAppsPressed" forKey:@"action"];
                [specifiers addObject:refreshAppsSpecifier];
            }
            if ((envManager.isJailbroken || envManager.isInstalledThroughTrollStore) && envManager.isBootstrapped) {
                PSSpecifier *hideUnhideJailbreakSpecifier = [PSSpecifier emptyGroupSpecifier];
                hideUnhideJailbreakSpecifier.target = self;
                [hideUnhideJailbreakSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                if (envManager.isJailbreakHidden) {
                    [hideUnhideJailbreakSpecifier setProperty:@"Unhide Jailbreak" forKey:@"title"];
                    [hideUnhideJailbreakSpecifier setProperty:@"eye" forKey:@"image"];
                }
                else {
                    [hideUnhideJailbreakSpecifier setProperty:@"Hide Jailbreak" forKey:@"title"];
                    [hideUnhideJailbreakSpecifier setProperty:@"eye.slash" forKey:@"image"];
                }
                [hideUnhideJailbreakSpecifier setProperty:@"hideUnhideJailbreakPressed" forKey:@"action"];
                BOOL hideJailbreakButtonShown = (envManager.isJailbroken || (envManager.isInstalledThroughTrollStore && envManager.isBootstrapped && !envManager.isJailbreakHidden));
                if (hideJailbreakButtonShown) {
                    [specifiers addObject:hideUnhideJailbreakSpecifier];
                }
                
                PSSpecifier *removeJailbreakSpecifier = [PSSpecifier emptyGroupSpecifier];
                removeJailbreakSpecifier.target = self;
                [removeJailbreakSpecifier setProperty:@"Remove Jailbreak" forKey:@"title"];
                [removeJailbreakSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                [removeJailbreakSpecifier setProperty:@"trash" forKey:@"image"];
                [removeJailbreakSpecifier setProperty:@"removeJailbreakPressed" forKey:@"action"];
                if (hideJailbreakButtonShown) {
                    if (envManager.isJailbroken) {
                        [removeJailbreakSpecifier setProperty:@"\"Hide Jailbreak\" temporarily removes jailbreak-related files and disables the jailbreak until you unhide it again." forKey:@"footerText"];
                    }
                    else {
                        [removeJailbreakSpecifier setProperty:@"\"Hide Jailbreak\" temporarily removes jailbreak-related files until the next jailbreak." forKey:@"footerText"];
                    }
                }
                [specifiers addObject:removeJailbreakSpecifier];
            }
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Getters & Setters

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [[DOPreferenceManager sharedManager] preferenceValueForKey:key];
    if (!value) {
        return [specifier propertyForKey:@"default"];
    }
    return value;
}

- (id)readIDownloadEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isIDownloadEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setIDownloadEnabled:(id)value specifier:(PSSpecifier *)specifier {
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setIDownloadEnabled:((NSNumber *)value).boolValue];
    }
    [self setPreferenceValue:value specifier:specifier];
}

- (id)readTweakInjectionEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isTweakInjectionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setTweakInjectionEnabled:(id)value specifier:(PSSpecifier *)specifier {
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setTweakInjectionEnabled:((NSNumber *)value).boolValue];
    }
    [self setPreferenceValue:value specifier:specifier];
}

#pragma mark - Button Actions

- (void)reinstallPackageManagersPressed
{
    [self.navigationController pushViewController:[[DOPkgManagerPickerViewController alloc] init] animated:YES];
}

- (void)refreshJailbreakAppsPressed
{
    [[DOEnvironmentManager sharedManager] refreshJailbreakApps];
}

- (void)hideUnhideJailbreakPressed
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    [envManager setJailbreakHidden:!envManager.isJailbreakHidden];
    [self reloadSpecifiers];
}

- (void)removeJailbreakPressed
{
    [[DOEnvironmentManager sharedManager] deleteBootstrap];
    if ([DOEnvironmentManager sharedManager].isJailbroken) {
        [[DOEnvironmentManager sharedManager] reboot];
    }
    else {
        [self reloadSpecifiers];
    }
}

- (void)resetSettingsPressed
{
    [[DOUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
    [self reloadSpecifiers];
}


@end
