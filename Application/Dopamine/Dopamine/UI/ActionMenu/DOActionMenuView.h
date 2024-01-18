//
//  DOActionMenuView.h
//  Dopamine
//
//  Created by tomt000 on 04/01/2024.
//

#import <UIKit/UIKit.h>
#import "DOActionMenuDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOActionMenuView : UIView

@property (atomic) UIStackView *buttonsView;
@property (atomic) id<DOActionMenuDelegate> delegate;
@property (nonatomic) NSArray *actions;

- (instancetype)initWithActions:(NSArray<UIAction*> *)actions delegate:(id<DOActionMenuDelegate>)delegate;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
