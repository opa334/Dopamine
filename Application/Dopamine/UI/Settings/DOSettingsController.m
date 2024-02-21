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
#import "DOThemeManager.h"
#import "DOSceneDelegate.h"


@interface DOSettingsController ()

@property (strong, nonatomic) PSSpecifier *mountSpecifier;
@property (strong, nonatomic) PSSpecifier *unmountSpecifier;
@property (strong, nonatomic) PSSpecifier *backupSpecifier;

@end

@implementation DOSettingsController

- (void)viewDidLoad
{
    _lastKnownTheme = [[DOThemeManager sharedInstance] enabledTheme].key;
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)arg1
{
    [super viewWillAppear:arg1];
    if (_lastKnownTheme != [[DOThemeManager sharedInstance] enabledTheme].key)
    {
        [DOSceneDelegate relaunch];
        NSString *icon = [[DOThemeManager sharedInstance] enabledTheme].icon;
        [[UIApplication sharedApplication] setAlternateIconName:icon completionHandler:^(NSError * _Nullable error) {
            if (error)
                NSLog(@"Error changing app icon: %@", error);
        }];
    }
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

- (NSArray *)themeIdentifiers
{
    return [[DOThemeManager sharedInstance] getAvailableThemeKeys];
}

- (NSArray *)themeNames
{
    return [[DOThemeManager sharedInstance] getAvailableThemeNames];
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
        [headerSpecifier setProperty:[NSString stringWithFormat:DOLocalizedString(@"Settings")] forKey:@"title"];
        [specifiers addObject:headerSpecifier];

        if (!envManager.isJailbroken) {
            PSSpecifier *exploitGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            exploitGroupSpecifier.name = DOLocalizedString(@"Section_Exploits");
            [specifiers addObject:exploitGroupSpecifier];
            
            PSSpecifier *kernelExploitSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Kernel Exploit") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
            [kernelExploitSpecifier setProperty:@YES forKey:@"enabled"];
            [kernelExploitSpecifier setProperty:exploitManager.preferredKernelExploit.identfier forKey:@"default"];
            kernelExploitSpecifier.detailControllerClass = [DOPSListItemsController class];
            [kernelExploitSpecifier setProperty:@"availableKernelExploitIdentifiers" forKey:@"valuesDataSource"];
            [kernelExploitSpecifier setProperty:@"availableKernelExploitNames" forKey:@"titlesDataSource"];
            [kernelExploitSpecifier setProperty:@"selectedKernelExploit" forKey:@"key"];
            [specifiers addObject:kernelExploitSpecifier];
            
            if (envManager.isArm64e) {
                PSSpecifier *pacBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"PAC Bypass") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
                [pacBypassSpecifier setProperty:@YES forKey:@"enabled"];
                DOExploit *preferredPACBypass = exploitManager.preferredPACBypass;
                if (!preferredPACBypass) {
                    [pacBypassSpecifier setProperty:@"none" forKey:@"default"];
                }
                else {
                    [pacBypassSpecifier setProperty:preferredPACBypass.identfier forKey:@"default"];
                }
                pacBypassSpecifier.detailControllerClass = [DOPSListItemsController class];
                [pacBypassSpecifier setProperty:@"availablePACBypassIdentifiers" forKey:@"valuesDataSource"];
                [pacBypassSpecifier setProperty:@"availablePACBypassNames" forKey:@"titlesDataSource"];
                [pacBypassSpecifier setProperty:@"selectedPACBypass" forKey:@"key"];
                [specifiers addObject:pacBypassSpecifier];
                
                PSSpecifier *pplBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"PPL Bypass") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
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
        settingsGroupSpecifier.name = DOLocalizedString(@"Section_Jailbreak_Settings");
        [specifiers addObject:settingsGroupSpecifier];
        
        PSSpecifier *tweakInjectionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Tweak_Injection") target:self set:@selector(setTweakInjectionEnabled:specifier:) get:@selector(readTweakInjectionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [tweakInjectionSpecifier setProperty:@YES forKey:@"enabled"];
        [tweakInjectionSpecifier setProperty:@"tweakInjectionEnabled" forKey:@"key"];
        [tweakInjectionSpecifier setProperty:@YES forKey:@"default"];
        [specifiers addObject:tweakInjectionSpecifier];
        
        if (!envManager.isJailbroken) {
            PSSpecifier *verboseLogSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_Verbose_Logs") target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
            [verboseLogSpecifier setProperty:@YES forKey:@"enabled"];
            [verboseLogSpecifier setProperty:@"verboseLogsEnabled" forKey:@"key"];
            [verboseLogSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:verboseLogSpecifier];
        }
        
        PSSpecifier *idownloadSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_iDownload") target:self set:@selector(setIDownloadEnabled:specifier:) get:@selector(readIDownloadEnabled:) detail:nil cell:PSSwitchCell edit:nil];
        [idownloadSpecifier setProperty:@YES forKey:@"enabled"];
        [idownloadSpecifier setProperty:@"idownloadEnabled" forKey:@"key"];
        [idownloadSpecifier setProperty:@NO forKey:@"default"];
        [specifiers addObject:idownloadSpecifier];
	
        if (envManager.isJailbroken) {
  	    PSSpecifier *newfunctionSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Settings_newfunction") target:self set:@selector(setNewfunctionEnabled:specifier:) get:@selector(readNewfunctionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [newfunctionSpecifier setProperty:@YES forKey:@"enabled"];
            [newfunctionSpecifier setProperty:@"newfunctionEnabled" forKey:@"key"];
            [newfunctionSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:newfunctionSpecifier];
	}
 
        if (!envManager.isJailbroken && !envManager.isInstalledThroughTrollStore) {
            PSSpecifier *removeJailbreakSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Button_Remove_Jailbreak") target:self set:@selector(setRemoveJailbreakEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
            [removeJailbreakSwitchSpecifier setProperty:@YES forKey:@"enabled"];
            [removeJailbreakSwitchSpecifier setProperty:@"removeJailbreakEnabled" forKey:@"key"];
            [specifiers addObject:removeJailbreakSwitchSpecifier];
        }
        
        if (envManager.isJailbroken || (envManager.isInstalledThroughTrollStore && envManager.isBootstrapped)) {
            PSSpecifier *actionsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            actionsGroupSpecifier.name = DOLocalizedString(@"Section_Actions");
            [specifiers addObject:actionsGroupSpecifier];
            
            if (envManager.isJailbroken) {
                PSSpecifier *reinstallPackageManagersSpecifier = [PSSpecifier emptyGroupSpecifier];
                reinstallPackageManagersSpecifier.target = self;
                [reinstallPackageManagersSpecifier setProperty:@"Button_Reinstall_Package_Managers" forKey:@"title"];
                [reinstallPackageManagersSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                if (@available(iOS 16.0, *))
                    [reinstallPackageManagersSpecifier setProperty:@"shippingbox.and.arrow.backward" forKey:@"image"];
                else
                    [reinstallPackageManagersSpecifier setProperty:@"shippingbox" forKey:@"image"];
                [reinstallPackageManagersSpecifier setProperty:@"reinstallPackageManagersPressed" forKey:@"action"];
                [specifiers addObject:reinstallPackageManagersSpecifier];
                
                PSSpecifier *refreshAppsSpecifier = [PSSpecifier emptyGroupSpecifier];
                refreshAppsSpecifier.target = self;
                [refreshAppsSpecifier setProperty:@"Button_Refresh_Jailbreak_Apps" forKey:@"title"];
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
                    [hideUnhideJailbreakSpecifier setProperty:@"Button_Unhide_Jailbreak" forKey:@"title"];
                    [hideUnhideJailbreakSpecifier setProperty:@"eye" forKey:@"image"];
                }
                else {
                    [hideUnhideJailbreakSpecifier setProperty:@"Button_Hide_Jailbreak" forKey:@"title"];
                    [hideUnhideJailbreakSpecifier setProperty:@"eye.slash" forKey:@"image"];
                }
                [hideUnhideJailbreakSpecifier setProperty:@"hideUnhideJailbreakPressed" forKey:@"action"];
                BOOL hideJailbreakButtonShown = (envManager.isJailbroken || (envManager.isInstalledThroughTrollStore && envManager.isBootstrapped && !envManager.isJailbreakHidden));
                if (hideJailbreakButtonShown) {
                    [specifiers addObject:hideUnhideJailbreakSpecifier];
                }
                
                PSSpecifier *removeJailbreakSpecifier = [PSSpecifier emptyGroupSpecifier];
                removeJailbreakSpecifier.target = self;
                [removeJailbreakSpecifier setProperty:@"Button_Remove_Jailbreak" forKey:@"title"];
                [removeJailbreakSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
                [removeJailbreakSpecifier setProperty:@"trash" forKey:@"image"];
                [removeJailbreakSpecifier setProperty:@"removeJailbreakPressed" forKey:@"action"];
                if (hideJailbreakButtonShown) {
                    if (envManager.isJailbroken) {
                        [removeJailbreakSpecifier setProperty:DOLocalizedString(@"Hint_Hide_Jailbreak_Jailbroken") forKey:@"footerText"];
                    }
                    else {
                        [removeJailbreakSpecifier setProperty:DOLocalizedString(@"Hint_Hide_Jailbreak") forKey:@"footerText"];
                    }
                }
                [specifiers addObject:removeJailbreakSpecifier];
            }
        }
        
        PSSpecifier *themingGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        themingGroupSpecifier.name = DOLocalizedString(@"Section_Customization");
        [specifiers addObject:themingGroupSpecifier];
        
        PSSpecifier *themeSpecifier = [PSSpecifier preferenceSpecifierNamed:DOLocalizedString(@"Theme") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
        themeSpecifier.detailControllerClass = [DOPSListItemsController class];
        [themeSpecifier setProperty:@YES forKey:@"enabled"];
        [themeSpecifier setProperty:@"theme" forKey:@"key"];
        [themeSpecifier setProperty:[[self themeIdentifiers] firstObject] forKey:@"default"];
        [themeSpecifier setProperty:@"themeIdentifiers" forKey:@"valuesDataSource"];
        [themeSpecifier setProperty:@"themeNames" forKey:@"titlesDataSource"];
        [specifiers addObject:themeSpecifier];

	BOOL newFunctionEnabled = [[DOEnvironmentManager sharedManager] newfunctionEnabled];
        if (newFunctionEnabled && envManager.isJailbroken) {
            PSSpecifier *mountSpecifier = [PSSpecifier emptyGroupSpecifier];
            mountSpecifier.target = self;
            [mountSpecifier setProperty:@"Input_Mmount_Title" forKey:@"title"];
            [mountSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
            [mountSpecifier setProperty:@"doc" forKey:@"image"];
            [mountSpecifier setProperty:@"mountPressed" forKey:@"action"];
            [specifiers addObject:mountSpecifier];

            PSSpecifier *unmountSpecifier = [PSSpecifier emptyGroupSpecifier];
            unmountSpecifier.target = self;
            [unmountSpecifier setProperty:@"Input_Unmount_Title" forKey:@"title"];
            [unmountSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
            [unmountSpecifier setProperty:@"trash" forKey:@"image"];
            [unmountSpecifier setProperty:@"unmountPressed" forKey:@"action"];
            [specifiers addObject:unmountSpecifier];

            PSSpecifier *backupSpecifier = [PSSpecifier emptyGroupSpecifier];
            backupSpecifier.target = self;
            [backupSpecifier setProperty:@"Alert_Back_Up_Title" forKey:@"title"];
            [backupSpecifier setProperty:@"DOButtonCell" forKey:@"headerCellClass"];
            [backupSpecifier setProperty:@"doc" forKey:@"image"];
            [backupSpecifier setProperty:@"backupPressed" forKey:@"action"];
            [specifiers addObject:backupSpecifier];
        }
        
        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Getters & Setters

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[DOPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
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

- (void)setIDownloadEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setIDownloadEnabled:((NSNumber *)value).boolValue];
    }
}

- (id)readNewfunctionEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].newfunctionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setNewfunctionEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setNewfunctionEnabled:((NSNumber *)value).boolValue];
	[self reloadSpecifier:specifier];
    }
}

- (id)readTweakInjectionEnabled:(PSSpecifier *)specifier
{
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([DOEnvironmentManager sharedManager].isTweakInjectionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setTweakInjectionEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[DOEnvironmentManager sharedManager] setTweakInjectionEnabled:((NSNumber *)value).boolValue];
        UIAlertController *userspaceRebootAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Title") message:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootNowAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Now") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[DOEnvironmentManager sharedManager] rebootUserspace];
        }];
        UIAlertAction *rebootLaterAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Later") style:UIAlertActionStyleCancel handler:nil];
        
        [userspaceRebootAlertController addAction:rebootNowAction];
        [userspaceRebootAlertController addAction:rebootLaterAction];
        [self presentViewController:userspaceRebootAlertController animated:YES completion:nil];
    }
}

- (void)setRemoveJailbreakEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    if (((NSNumber *)value).boolValue) {
        UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Enabled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:nil];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self setPreferenceValue:@NO specifier:specifier];
            [self reloadSpecifiers];
        }];
        [confirmationAlertController addAction:uninstallAction];
        [confirmationAlertController addAction:cancelAction];
        [self presentViewController:confirmationAlertController animated:YES completion:nil];
    }
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
    UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Remove_Jailbreak_Title") message:DOLocalizedString(@"Alert_Remove_Jailbreak_Pressed_Body") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DOEnvironmentManager sharedManager] deleteBootstrap];
        if ([DOEnvironmentManager sharedManager].isJailbroken) {
            [[DOEnvironmentManager sharedManager] reboot];
        }
        else {
            if (gSystemInfo.jailbreakInfo.rootPath) {
                free(gSystemInfo.jailbreakInfo.rootPath);
                gSystemInfo.jailbreakInfo.rootPath = NULL;
                [[DOEnvironmentManager sharedManager] locateJailbreakRoot];
            }
            [self reloadSpecifiers];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
    [confirmationAlertController addAction:uninstallAction];
    [confirmationAlertController addAction:cancelAction];
    [self presentViewController:confirmationAlertController animated:YES completion:nil];
}

- (void)mountPressed
{
    UIAlertController *inputAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Input_Mmount_Title") message:DOLocalizedString(@"Input_Mount_Title") preferredStyle:UIAlertControllerStyleAlert];

    [inputAlertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Input_Mount_Title");
    }];
    
    UIAlertAction *mountAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Mount") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {        // 获取用户输入的Jailbreak路径
        UITextField *inputTextField = inputAlertController.textFields.firstObject;
        NSString *mountPath = inputTextField.text;
        
        if (mountPath.length > 1) {
            NSString *plistFilePath = @"/var/mobile/newFakePath.plist";
            NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:plistFilePath];
            if (!plistDictionary) {
                plistDictionary = [NSMutableDictionary dictionary];
            }
            NSMutableArray *pathArray = plistDictionary[@"path"];
            if (!pathArray) {
                pathArray = [NSMutableArray array];
            }
            if (![pathArray containsObject:mountPath]) {
			          [pathArray addObject:mountPath];
								[plistDictionary setObject:pathArray forKey:@"path"];
						 
                [plistDictionary writeToFile:plistFilePath atomically:YES];
            } 

            exec_cmd_root(JBRootPath("/basebin/jbctl"), "internal", "mount", [NSURL fileURLWithPath:mountPath].fileSystemRepresentation, NULL);

        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];

    [inputAlertController addAction:mountAction];
    [inputAlertController addAction:cancelAction];
    
    [self presentViewController:inputAlertController animated:YES completion:nil];
}

- (void)unmountPressed
{
    UIAlertController *inputAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Input_Mount_Title") message:DOLocalizedString(@"Input_Mount_Title") preferredStyle:UIAlertControllerStyleAlert];
    
    [inputAlertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = DOLocalizedString(@"Input_Mount_Title");
    }];
    
    UIAlertAction *mountAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Mount") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {

        UITextField *inputTextField = inputAlertController.textFields.firstObject;
        NSString *mountPath = inputTextField.text;
        
	
        if (mountPath.length > 1) {
            exec_cmd_root(JBRootPath("/usr/bin/rm"), "-rf", JBRootPath([NSURL fileURLWithPath:mountPath].fileSystemRepresentation), NULL);
            exec_cmd_root(JBRootPath("/basebin/jbctl"), "internal", "unmount", [NSURL fileURLWithPath:mountPath].fileSystemRepresentation, NULL);

            NSString *plistPath = @"/var/mobile/newFakePath.plist";
            NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
            NSMutableArray *paths = plist[@"path"];
        
            for (NSInteger index = 0; index < paths.count; index++) {
                NSString *path = paths[index];
                if ([path isEqualToString:mountPath]) {
                    [paths removeObjectAtIndex:index];
                    plist[@"path"] = paths;
                    [plist writeToFile:plistPath atomically:YES];
                }
            }
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
    
    [inputAlertController addAction:mountAction];
    [inputAlertController addAction:cancelAction];
    
    [self presentViewController:inputAlertController animated:YES completion:nil];
}

- (void)backupPressed
{
    NSString *debBackupPath = @"/var/mobile/Documents/DebBackup/";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *files = [fileManager contentsOfDirectoryAtPath:debBackupPath error:nil];

    if (files.count == 0) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"备份失败" message:@"请先使用“DEB备份”app备份插件！！！" preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:closeAction];
        [self presentViewController:alertController animated:YES completion:nil];
    } else {   
        UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Alert_Back_Up_Title") message:DOLocalizedString(@"Alert_Back_Up_Pressed_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *backupAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self performBackup];
            [self showBackupSuccessAlert];
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
        [confirmationAlertController addAction:backupAction];
        [confirmationAlertController addAction:cancelAction];
        [self presentViewController:confirmationAlertController animated:YES completion:nil];
    }
}

- (void)showBackupSuccessAlert {
    UIAlertController *successAlertController = [UIAlertController alertControllerWithTitle:@"提示：恭喜你，备份成功！！！" message:nil preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
    [successAlertController addAction:okAction];
    [self presentViewController:successAlertController animated:YES completion:nil];
}

- (void)performBackup {
    NSFileManager *fileManager = [NSFileManager defaultManager];   
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy.MM.dd_HH:mm:ss"];
    [dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
    NSDate *currentDate = [NSDate date];
    NSString *dateString = [dateFormatter stringFromDate:currentDate];
    
    NSArray *filePaths = @[
        [NSString stringWithFormat:@"/var/mobile/backup_%@/Dopamine插件", dateString],
        [NSString stringWithFormat:@"/var/mobile/backup_%@/插件配置", dateString],
        [NSString stringWithFormat:@"/var/mobile/backup_%@/插件源", dateString]
    ];
    
    for (NSString *filePath in filePaths) {
        if (![fileManager fileExistsAtPath:filePath]) {
            NSError *error = nil;
            BOOL success = [fileManager createDirectoryAtPath:filePath withIntermediateDirectories:YES attributes:nil error:&error];
            if (!success) {
                NSLog(@"创建文件夹失败: %@", error);
            }
        }
    }
    
    NSString *dopaminedebPath = @"/var/mobile/Documents/DebBackup/";
    NSString *preferencesPath = @"/var/jb/User/Library/";
    NSString *sourcesPath = @"/var/jb/etc/apt/sources.list.d/";
    
    NSArray *moveItems = @[
        @[dopaminedebPath, filePaths[0], @"剪切Dopamine插件失败"],
    ];
    
    NSArray *copyItems = @[
        @[preferencesPath, filePaths[1], @"复制Preferences失败"],
        @[sourcesPath, filePaths[2], @"复制sources.list.d失败"]
    ];
    
    for (NSArray *item in moveItems) {
        NSString *sourcePath = item[0];
        NSString *destinationPath = item[1];
        NSString *errorMessage = item[2];
        
        NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:sourcePath];
        for (NSString *file in enumerator) {
            NSError *error = nil;
            NSString *sourceFilePath = [sourcePath stringByAppendingPathComponent:file];
            NSString *destinationFilePath = [destinationPath stringByAppendingPathComponent:file];
            BOOL success = [fileManager moveItemAtPath:sourceFilePath toPath:destinationFilePath error:&error];
            if (!success) {
                NSLog(@"%@", errorMessage);
            }
        }
    }
    
    for (NSArray *item in copyItems) {
        NSString *sourcePath = item[0];
        NSString *destinationPath = item[1];
        NSString *errorMessage = item[2];
        
        NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:sourcePath];
        for (NSString *file in enumerator) {
            NSError *error = nil;
            NSString *sourceFilePath = [sourcePath stringByAppendingPathComponent:file];
            NSString *destinationFilePath = [destinationPath stringByAppendingPathComponent:file];
            BOOL success = [fileManager copyItemAtPath:sourceFilePath toPath:destinationFilePath error:&error];
            if (!success) {
                NSLog(@"%@", errorMessage);
            }
        }
    }
    
    NSString *scriptContent = @"#!/bin/sh\n\n"
    "#环境变量\n"
    "PATH=/var/jb/bin:/var/jb/sbin:/var/jb/usr/bin:/var/jb/usr/sbin:$PATH\n\n"
    "echo \"..........................\"\n"
    "echo \"..........................\"\n"
    "echo \"******Dopamine插件安装******\"\n"
    "sleep 1s\n"
    "#安装当前路径下所有插件\n"
    "dpkg -i ./Dopamine插件/*.deb\n"
    "echo \"..........................\"\n"
    "echo \"..........................\"\n"
    "echo \"..........................\"\n\n"
    "echo \"******开始恢复插件设置******\"\n"
    "sleep 1s\n"
    "cp -a ./插件源/* /var/jb/etc/apt/sources.list.d/\n"
    "cp -a ./插件配置/* /var/jb/User/Library/\n"
    "echo \"******插件设置恢复成功*******\"\n\n"
    "echo \"******正在准备注销生效******\"\n"
    "sleep 1s\n"
    "killall -9 backboardd\n"
    "echo \"done\"\n";
    
    NSString *filePath = [NSString stringWithFormat:@"/var/mobile/backup_%@/一键恢复插件及配置.sh", dateString];
    NSError *error = nil;
    BOOL success = [scriptContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (success) {
        NSLog(@"成功添加代码到文件：%@", filePath);
        
        NSDictionary *attributes = @{
            NSFilePosixPermissions: @(0755),
            NSFileOwnerAccountName: @"mobile",
            NSFileGroupOwnerAccountName: @"mobile"
        };
        success = [fileManager setAttributes:attributes ofItemAtPath:filePath error:&error];
        if (success) {
            NSLog(@"成功设置文件权限为0755，用户和组权限为mobile");
        } else {
            NSLog(@"设置文件权限失败: %@", error);
        }
    } else {
        NSLog(@"操作失败: %@", error);
    }
}

- (void)resetSettingsPressed
{
    [[DOUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
    [self reloadSpecifiers];
}

@end
