//
//  OPFileTree.h
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import <Foundation/Foundation.h>
#import <FSEvents.h>
@class OPFileNode, OPFileLeaf;

NS_ASSUME_NONNULL_BEGIN

@interface OPFileTree : NSObject
{
    OPFileNode *_rootNode;
    NSString *_observePath;
    dispatch_queue_t _eventDispatchQueue;
    FSEventStreamRef _stream;
}

@property (nonatomic) Class leafClass;

+ (instancetype)treeForObservingPath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)path;

- (void)enumerateLeafs:(void (^)(__kindof OPFileLeaf *leaf, BOOL *stop))enumBlock;
- (void)openTree;

- (void)receivedEvents:(size_t)numEvents forPaths:(void *)eventPaths withFlags:(const FSEventStreamEventFlags[])eventFlags andIds:(const FSEventStreamEventId[])eventIds;

- (BOOL)shouldIncludeItemAtPath:(NSString *)path;
- (void)mustRescan;

@end

NS_ASSUME_NONNULL_END
