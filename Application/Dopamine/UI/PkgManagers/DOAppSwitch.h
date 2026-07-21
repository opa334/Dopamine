//
//  DOAppSwitch.h
//  Dopamine
//
//  Created by tomt000 on 08/02/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOAppSwitch : UIView

@property (nonatomic, assign) BOOL selected;
@property (nonatomic) void (^onSwitch)(BOOL);

-(id)initWithIcon:(UIImage *)icon title:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
