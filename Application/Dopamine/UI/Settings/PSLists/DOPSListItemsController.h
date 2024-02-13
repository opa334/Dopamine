//
//  DOPSListItemsController.h
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>


NS_ASSUME_NONNULL_BEGIN

@interface PSListItemsController : PSListController
- (id)itemsFromDataSource;
@end

@interface DOPSListItemsController : PSListItemsController

+ (UIView *)makeHeader:(NSString *)title withTarget:(id)target;

@end

NS_ASSUME_NONNULL_END
