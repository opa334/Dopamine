//
//  DOLogCrashViewController.h
//  Dopamine
//
//  Created by tomt000 on 14/02/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOLogCrashViewController : UIViewController
{
    UITextView *_logView;
}

- (id)initWithTitle:(NSString*)title;

@end

NS_ASSUME_NONNULL_END
