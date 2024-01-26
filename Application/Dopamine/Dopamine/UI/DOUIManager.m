//
//  DOUIManager.m
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import "DOUIManager.h"

@implementation DOUIManager

+(id)sharedInstance {
    static DOUIManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DOUIManager alloc] init];
    });
    return sharedInstance;
}

-(id)init {
    if (self = [super init]){
        self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

-(NSArray*)availablePackageManagers {
    return @[kSileoPackageManager, kZebraPackageManager];
}

-(BOOL)isDebug {
    BOOL debug = [self.userDefaults boolForKey:@"debug"];
    return debug == nil ? NO : debug;
}

-(BOOL)enableTweaks {
    BOOL tweaks = [self.userDefaults boolForKey:@"tweaks"];
    return tweaks == nil ? YES : tweaks;
}

@end
