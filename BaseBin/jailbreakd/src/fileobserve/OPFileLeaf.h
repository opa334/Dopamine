//
//  OPFileLeaf.h
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import <Foundation/Foundation.h>
#import "OPFileNode.h"
#import "OPFileItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface OPFileLeaf : NSObject <OPFileItem>
{
    char *_name;
    __weak OPFileNode *_parentNode;
}

@property (nonatomic, readonly) NSString *nsName;
@property (nonatomic, readonly) NSString *fullPath;

- (instancetype)initWithName:(const char *)name parent:(OPFileNode *)parent;

- (void)createReceived;
- (void)deleteReceived;

@end

NS_ASSUME_NONNULL_END
