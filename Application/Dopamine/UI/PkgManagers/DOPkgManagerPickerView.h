//
//  DOPkgManagerPickerView.h
//  Dopamine
//
//  Created by tomt000 on 08/02/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOPkgManagerPickerView : UIView

-(id)initWithCallback:(void (^)(BOOL))callback;

@end

NS_ASSUME_NONNULL_END
