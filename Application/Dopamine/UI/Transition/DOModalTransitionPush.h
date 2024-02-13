//
//  DOModalTransitionPush.h
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOModalTransitionPush : NSObject <UIViewControllerAnimatedTransitioning>

- (id)initForwards:(BOOL)forwards;

@end

NS_ASSUME_NONNULL_END
