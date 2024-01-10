//
//  Jailbreaker.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "Jailbreaker.h"
#import "EnvironmentManager.h"

@implementation Jailbreaker

+ (void)prepareJailbreak
{
    NSString *kernelPath = [EnvironmentManager accessibleKernelPath];
    printf("Kernel at %s\n", kernelPath.UTF8String);
}


+ (void)run
{
    [self prepareJailbreak];
}

@end
