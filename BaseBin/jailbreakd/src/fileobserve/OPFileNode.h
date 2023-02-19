//
//  OPFileNode.h
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import <Foundation/Foundation.h>
#import "OPFileItem.h"

NS_ASSUME_NONNULL_BEGIN

@class OPFileTree, OPFileLeaf;

@interface OPFileNode : NSObject <OPFileItem>
{
    NSMutableArray<OPFileNode *> *_subNodes;
    NSMutableArray<OPFileLeaf *> *_leafs;
    
    __weak OPFileNode *_parentNode;
    __weak OPFileTree *_tree;
}
@property (nonatomic) char *name;
@property (nonatomic, readonly) NSString *nsName;
@property (nonatomic, readonly) NSString *fullPath;

+ (instancetype)fileNodeWithName:(const char *)name parentNode:(OPFileNode *)parentNode tree:(OPFileTree *)tree;
+ (instancetype)rootNodeWithName:(const char *)name tree:(OPFileTree *)tree;

- (instancetype)initWithName:(const char *)name parentNode:(OPFileNode * _Nullable)parentNode tree:(OPFileTree *)tree;

- (void)populate;

- (void)createReceived;
- (void)deleteReceived;

- (void)subItemDeleted:(id<OPFileItem>)subItem;

- (BOOL)enumerateLeafs:(void (^)(OPFileLeaf *leaf, BOOL *stop))enumBlock;
- (id<OPFileItem>)itemForSubPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
