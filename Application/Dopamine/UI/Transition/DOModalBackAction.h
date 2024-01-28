//
//  DOModalBackAction.h
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOModalBackAction : UIView

@property (nonatomic) void (^action)(void);
@property (nonatomic) CGRect ignoreFrame;

-(id)initWithAction:(void (^)(void))action;

@end

NS_ASSUME_NONNULL_END
