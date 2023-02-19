//
//  OPFileNode.m
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import "OPFileNode.h"
#import "OPFileLeaf.h"
#import "OPFileTree.h"

NSLock *gChangeReceiveLock;

@implementation OPFileNode

- (NSString *)nsName
{
    if (!_name) return nil;
    return [NSString stringWithUTF8String:_name];
}

- (NSString *)fullPath
{
    if (!_parentNode) return self.nsName;
    return [_parentNode.fullPath stringByAppendingPathComponent:self.nsName];
}

+ (instancetype)fileNodeWithName:(const char *)name parentNode:(OPFileNode *)parentNode tree:(OPFileTree *)tree
{
    return [[OPFileNode alloc] initWithName:name parentNode:parentNode tree:tree];
}

+ (instancetype)rootNodeWithName:(const char *)name tree:(OPFileTree *)tree
{
    return [[OPFileNode alloc] initWithName:name parentNode:nil tree:tree];
}

- (instancetype)initWithName:(const char*)name parentNode:(OPFileNode *)parentNode tree:(OPFileTree *)tree
{
    self = [super init];
    
    if (self) {
        _name = strdup(name);
        _parentNode = parentNode;
        _tree = tree;
        _subNodes = [NSMutableArray new];
        _leafs = [NSMutableArray new];
        
        [self populate];
    }
    
    return self;
}

- (id<OPFileItem>)handleItemAdd:(NSString *)subItemPath
{
    if (![_tree shouldIncludeItemAtPath:subItemPath]) return nil;

    NSString *subItem = subItemPath.lastPathComponent;
    
    BOOL isDirectory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:subItemPath isDirectory:&isDirectory];
    
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:subItemPath error:nil];
    if(attributes[NSFileType] == NSFileTypeSymbolicLink)
    {
        return nil;
    }
    
    if (isDirectory) {
        OPFileNode *subNode = [OPFileNode fileNodeWithName:subItem.UTF8String parentNode:self tree:_tree];
        [_subNodes addObject:subNode];
        return subNode;
    }
    else {
        OPFileLeaf *leaf = [[_tree.leafClass alloc] initWithName:subItem.UTF8String parent:self];
        [_leafs addObject:leaf];
        return leaf;
    }
}

- (void)populate
{
    NSString *selfPath = self.fullPath;
    
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:selfPath error:nil];
    
    for (NSString* subItem in contents) {
        NSString *subItemPath = [selfPath stringByAppendingPathComponent:subItem];
        [self handleItemAdd:subItemPath];
    }
}

- (void)enumerateAllSubItems:(void (^)(id<OPFileItem> item, BOOL *stop))enumBlock
{
    for (OPFileNode *subNode in [_subNodes reverseObjectEnumerator]) {
        BOOL stop = NO;
        enumBlock(subNode, &stop);
        if (stop) return;
    }
    for (OPFileLeaf *leaf in [_leafs reverseObjectEnumerator]) {
        BOOL stop = NO;
        enumBlock(leaf, &stop);
        if (stop) return;
    }
}

- (id<OPFileItem>)itemForSubPath:(NSString *)path
{
    NSString *nameInside = path.pathComponents[0];
    
    __block id<OPFileItem> returnItem = nil;
    
    [self enumerateAllSubItems:^(id<OPFileItem> item, BOOL *stop) {
        if ([item.nsName isEqualToString:nameInside]) {
            returnItem = item;
        }
    }];
    
    // If we don't know about this item yet, add it
    if (!returnItem) {
        returnItem = [self handleItemAdd:[self.fullPath stringByAppendingPathComponent:nameInside]];
        NSLog(@"itemForSubPath:%@ created new: %@", path, returnItem);
        if (!returnItem) return nil;
    }
    
    if (path.pathComponents.count > 1 && [returnItem isKindOfClass:OPFileNode.class]) {
        OPFileNode *node = returnItem;
        NSMutableArray *pathComponents = path.pathComponents.mutableCopy;
        [pathComponents removeObjectAtIndex:0];
        return [node itemForSubPath:[NSString pathWithComponents:pathComponents]];
    }
    
    return returnItem;
}

- (void)createReceived
{
    if (_subNodes) {
        [_subNodes makeObjectsPerformSelector:@selector(createReceived)];
    }
    if (_leafs) {
        [_leafs makeObjectsPerformSelector:@selector(createReceived)];
    }
}

- (void)modifyReceived {
    
}

- (void)deleteReceived
{
    if (_subNodes) {
        [_subNodes makeObjectsPerformSelector:@selector(deleteReceived)];
    }
    if (_leafs) {
        [_leafs makeObjectsPerformSelector:@selector(deleteReceived)];
    }
    [_parentNode subItemDeleted:self];
}

- (void)subItemDeleted:(id<OPFileItem>)subItem
{
    if ([subItem isKindOfClass:OPFileNode.class]) {
        NSLog(@"subItemDeleted remove from _subNodes");
        [_subNodes removeObject:subItem];
    }
    else {
        NSLog(@"subItemDeleted remove from _leafs");
        [_leafs removeObject:subItem];
    }
}

- (BOOL)enumerateLeafs:(void (^)(OPFileLeaf *leaf, BOOL *stop))enumBlock
{
    for (OPFileLeaf *leaf in [_leafs reverseObjectEnumerator]) {
        BOOL stop = NO;
        enumBlock(leaf, &stop);
        if (stop) return YES;
    }
    
    for (OPFileNode *node in [_subNodes reverseObjectEnumerator]) {
        BOOL stop = [node enumerateLeafs:enumBlock];
        if (stop) return YES;
    }

    return NO;
}

- (void)dealloc
{
    if (_name) free(_name);
}

@end
