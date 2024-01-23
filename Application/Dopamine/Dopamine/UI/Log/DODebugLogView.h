//
//  DODebugLogView.h
//  Dopamine
//
//  Created by tomt000 on 23/01/2024.
//

#import <UIKit/UIKit.h>
#import "DOLogViewProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface DODebugLogView : UIView<DOLogViewProtocol>

@property (nonatomic, strong) UITextView *textView;

@end

NS_ASSUME_NONNULL_END
