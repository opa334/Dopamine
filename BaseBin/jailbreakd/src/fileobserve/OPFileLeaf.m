//
//  OPFileLeaf.m
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import "OPFileLeaf.h"

@implementation OPFileLeaf

- (NSString *)nsName
{
    if (!_name) return nil;
    return [NSString stringWithUTF8String:_name];
}

- (NSString *)fullPath
{
    return [_parentNode.fullPath stringByAppendingPathComponent:self.nsName];
}

- (instancetype)initWithName:(const char *)name parent:(OPFileNode *)parent
{
    self = [super init];
    if (self) {
        _name = strdup(name);
        _parentNode = parent;
    }
    return self;
}

- (void)createReceived
{
    NSLog(@"created %@", self.fullPath);
}

- (void)modifyReceived
{
    NSLog(@"modified %@", self.fullPath);
}

- (void)deleteReceived
{
    NSLog(@"deleted %@", self.fullPath);
    [_parentNode subItemDeleted:self];
}

- (void)dealloc
{
    if (_name) free(_name);
}

@end
