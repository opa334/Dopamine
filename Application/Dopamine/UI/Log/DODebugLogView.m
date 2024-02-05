//
//  DODebugLogView.m
//  Dopamine
//
//  Created by tomt000 on 23/01/2024.
//

#import "DODebugLogView.h"

@implementation DODebugLogView

-(id)init
{
    if (self = [super init])
    {
        self.textView = [[UITextView alloc] init];
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        self.textView.backgroundColor = [UIColor clearColor];
        self.textView.textColor = [UIColor whiteColor];
        self.textView.font = [UIFont systemFontOfSize:14];
        self.textView.editable = NO;
        self.textView.scrollEnabled = YES;
        self.textView.textContainerInset = UIEdgeInsetsMake(0, 15, 15, 15);
        self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

        [self addSubview:self.textView];

        [NSLayoutConstraint activateConstraints:@[
            [self.textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.textView.topAnchor constraintEqualToAnchor:self.topAnchor constant:65],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];        
        
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    }
    return self;
}

-(void)showLog:(NSString *)log
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showLog:log];
        });
        return;
    }

    self.textView.text = [self.textView.text stringByAppendingString:[NSString stringWithFormat:@"> %@\n", log]];
    [UIView performWithoutAnimation:^{
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
    }];
}

-(void)didComplete
{

}


@end
