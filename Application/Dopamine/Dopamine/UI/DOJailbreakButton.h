//
//  DOJailbreakButton.h
//  Dopamine
//
//  Created by tomt000 on 13/01/2024.
//

#import <UIKit/UIKit.h>
#import "DOActionMenuButton.h"
#import "DOLyricsLogView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOJailbreakButton : UIView

@property DOActionMenuButton *button;
@property UIView<DOLogViewProtocol> *logView;

- (instancetype)initWithAction:(UIAction *)actions;
- (void)showLog:(NSArray<NSLayoutConstraint *> *)constraints;

@end

NS_ASSUME_NONNULL_END
