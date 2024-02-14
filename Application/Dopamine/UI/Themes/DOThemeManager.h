//
//  DOThemeManager.h
//  Dopamine
//
//  Created by tomt000 on 14/02/2024.
//

#import <Foundation/Foundation.h>
#import "DOTheme.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOThemeManager : NSObject

@property (nonatomic, retain) NSArray<DOTheme*> *themes;

+ (id)sharedInstance;

+ (UIColor*)menuColorWithAlpha:(float)alpha;
- (NSArray*)getAvailableThemeKeys;
- (NSArray*)getAvailableThemeNames;
- (DOTheme*)getThemeForKey:(NSString*)key;
- (DOTheme*)enabledTheme;

@end

NS_ASSUME_NONNULL_END
