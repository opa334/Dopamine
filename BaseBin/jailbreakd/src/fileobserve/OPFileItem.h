//
//  OPFileItem.h
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OPFileItem <NSObject>

@property (nonatomic, readonly) NSString *nsName;

- (void)createReceived;
- (void)modifyReceived;
- (void)deleteReceived;

@end

NS_ASSUME_NONNULL_END
