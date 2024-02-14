//
//  DOSettingsController.h
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "DOPSListController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOSettingsController : DOPSListController
{
    NSArray *_availableKernelExploits;
    NSArray *_availablePACBypasses;
    NSArray *_availablePPLBypasses;
    NSString *_lastKnownTheme;
}

@end

NS_ASSUME_NONNULL_END
