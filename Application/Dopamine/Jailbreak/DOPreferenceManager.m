//
//  PreferenceManager.m
//  Dopamine
//
//  Created by Lars Fröder on 13.01.24.
//

#import "DOPreferenceManager.h"

@implementation DOPreferenceManager

+ (instancetype)sharedManager
{
    static DOPreferenceManager *preferenceManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferenceManager = [[DOPreferenceManager alloc] init];
    });
    return preferenceManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _preferencesPath = [NSHomeDirectory() stringByAppendingString:@"Library/Preferences/com.opa334.dopamine.plist"];
    }
    return self;
}

- (void)loadPreferences
{
    _preferences = [NSDictionary dictionaryWithContentsOfFile:_preferencesPath].mutableCopy ?: [NSMutableDictionary new];
}

- (void)savePreferences
{
    [_preferences writeToFile:_preferencesPath atomically:YES];
}

- (NSObject *)preferenceValueForKey:(NSString *)key
{
    return [_preferences objectForKey:key];
}

- (void)setPreferenceValue:(NSObject *)obj forKey:(NSString *)key
{
    [_preferences setObject:obj forKey:key];
    [self savePreferences];
}

@end
