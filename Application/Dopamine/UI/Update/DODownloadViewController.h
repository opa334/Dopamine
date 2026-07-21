//
//  DODownloadViewController.h
//  Dopamine
//
//  Created by tomt000 on 07/02/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DODownloadViewController : UIViewController

- (id)initWithUrl:(NSString *)urlString callback:(void (^)(NSURL *file))callback;

@end

NS_ASSUME_NONNULL_END
