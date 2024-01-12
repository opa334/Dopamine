//
//  Jailbreaker.h
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import <Foundation/Foundation.h>

#import <xpc/xpc.h>

NS_ASSUME_NONNULL_BEGIN

@interface Jailbreaker : NSObject
{
    xpc_object_t _systemInfoXdict;
}

- (NSError *)run;

@end

NS_ASSUME_NONNULL_END
