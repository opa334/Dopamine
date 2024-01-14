//
//  UIImage+Blur.m
//  Dopamine
//
//  Created by Lars Fröder on 01.10.23.
//

#import <Foundation/Foundation.h>
#import "NSData+Hex.h"

@implementation NSData (Hex)

- (NSString *)hexString {
    const unsigned char *dataBuffer = (const unsigned char *)[self bytes];
    if (!dataBuffer) return [NSString string];

    NSUInteger dataLength = [self length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02lX", (unsigned long)dataBuffer[i]];
    }

    return hexString;
}

@end
