//
//  DOModalBackAction.m
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import "DOModalBackAction.h"

@implementation DOModalBackAction

-(id)initWithAction:(void (^)(void))action
{
    if (self = [super init])
    {
        self.action = action;
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.ignoreFrame, point))
        return NO;
    return [super pointInside:point withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.action)
        self.action();
}

@end
