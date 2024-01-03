//
//  RootViewController.h
//  Dopamine
//
//  Created by Lars Fröder on 23.09.23.
//

#import <UIKit/UIKit.h>
#import "ActionMenuDelegate.h"
#import "ExpandableButton.h"

@interface RootViewController : UIViewController <ActionMenuDelegate>
{
    UIView *_containerView;
    
    UIView *_spaceView1;
    UIView *_spaceView2;
    
    NSArray *_titleViewConstraints;
    NSArray *_actionViewContraints;
    NSArray *_jailbreakButtonPlaceholderContraints;
    NSArray *_updateButtonConstraints;
    
    NSArray *_updateButtonEnabledContraints;
    NSArray *_updateButtonDisabledContraints;
    
    NSArray *_jailbreakButtonAttachedConstraints;
    NSArray *_jailbreakButtonExpandedConstraints;
    
    BOOL _jailbreakButtonExpanded;
}

@property (nonatomic) BOOL jailbreakButtonExpanded;


@end
