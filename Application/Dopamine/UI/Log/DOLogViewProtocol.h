//
//  DOLogViewProtocol.h
//  Dopamine
//
//  Created by tomt000 on 13/01/2024.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DOLogViewProtocol <NSObject>

-(void)showLog:(NSString *)log;
-(void)didComplete;

@optional
- (void)updateLog:(NSString *)log;

@end

NS_ASSUME_NONNULL_END
