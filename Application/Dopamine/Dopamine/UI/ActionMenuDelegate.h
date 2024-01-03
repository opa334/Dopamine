//
//  ActionMenuDelegate.h
//  Dopamine
//
//  Created by Lars Fröder on 07.10.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ActionMenuDelegate <NSObject>

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action;

@end

NS_ASSUME_NONNULL_END
