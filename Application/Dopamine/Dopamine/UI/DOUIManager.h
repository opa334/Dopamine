//
//  DOUIManager.h
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define kSileoPackageManager @"Sileo"
#define kZebraPackageManager @"Zebra"


@interface DOUIManager : NSObject

@property (nonatomic, retain) NSUserDefaults *userDefaults;

+(id)sharedInstance;
-(NSArray*)availablePackageManagers;
-(BOOL)isDebug;

@end

NS_ASSUME_NONNULL_END
