//
//  ActionMenuView.h
//  Dopamine
//
//  Created by Lars Fröder on 07.10.23.
//

#import <UIKit/UIKit.h>
#import "ActionMenuDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface ActionMenuView : UIView
{
    id <ActionMenuDelegate> _delegate;
    NSArray *_activeConstraints;
}

- (instancetype)initWithActions:(NSArray<UIAction*> *)actions delegate:(id<ActionMenuDelegate>)delegate;
- (void)updateActions:(NSArray<UIAction*> *)actions;

@end

NS_ASSUME_NONNULL_END
