//
//  PreferenceManager.h
//  Dopamine
//
//  Created by Lars Fröder on 13.01.24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOPreferenceManager : NSObject
{
    NSString *_preferencesPath;
    NSMutableDictionary *_preferences;
}

- (NSObject *)preferenceValueForKey:(NSString *)key;
- (void)setPreferenceValue:(NSObject *)obj forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
