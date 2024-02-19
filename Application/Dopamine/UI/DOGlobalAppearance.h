//
//  GlobalAppearance.h
//  Dopamine
//
//  Created by Lars Fröder on 10.10.23.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#define UI_IPAD_MAX_WIDTH 600
#define UI_MODAL_PADDING 30
#define UI_PADDING 30
//Action Menu
#define UI_INNER_PADDING 20
#define UI_INNER_PADDING_TINY 10
#define UI_INNER_TOP_PADDING 5
#define UI_ACTION_HEIGHT 73
#define UI_ACTION_HEIGHT_HOME_BTN 65
#define UI_ACTION_HEIGHT_TINY 52

#define SE_PHONE_SIZE_CONST 568

@interface DOGlobalAppearance : NSObject

+ (UIImageSymbolConfiguration *)smallIconImageConfiguration;
+ (UIButtonConfiguration *)defaultButtonConfiguration;
+ (UIButtonConfiguration *)defaultButtonConfigurationWithImagePadding:(CGFloat)imagePadding;
+ (NSAttributedString*)mainSubtitleString:(NSString*)string;
+ (NSAttributedString*)secondarySubtitleString:(NSString*)string;
+ (BOOL)isHomeButtonDevice;
+ (UIColor*)windowColorWithAlpha:(float)alpha;
+ (BOOL)isRTL;
+ (BOOL)isSmallDevice;

@end

NS_ASSUME_NONNULL_END
