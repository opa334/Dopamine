//
//  DOActionMenuDelegate.h
//  Dopamine
//
//  Created by tomt000 on 13/01/2024.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DOActionMenuDelegate <NSObject>

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action;
- (BOOL)actionMenuActionIsEnabled:(UIAction *)action;

@end

NS_ASSUME_NONNULL_END
