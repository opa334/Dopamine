//
//  DOUIManager.h
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import <Foundation/Foundation.h>
#import "DOLogViewProtocol.h"
#import "DODebugLogView.h"

NS_ASSUME_NONNULL_BEGIN

#define kSileoPackageManager @"Sileo"
#define kZebraPackageManager @"Zebra"


@interface DOUIManager : NSObject

@property (nonatomic, retain) NSUserDefaults *userDefaults;
@property (nonatomic, retain) NSObject<DOLogViewProtocol> *logView;

+(id)sharedInstance;

- (NSArray*)availablePackageManagers;
- (BOOL)isDebug;
- (void)sendLog:(NSString*)log debug:(BOOL)debug update:(BOOL)update;
- (void)sendLog:(NSString*)log debug:(BOOL)debug;
- (void)completeJailbreak;
- (void)startLogCapture;
- (BOOL)isUpdateAvailable;
- (NSArray *)getLatestReleases;

@end

NS_ASSUME_NONNULL_END
