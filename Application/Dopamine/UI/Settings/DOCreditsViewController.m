//
//  DOCreditsViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOCreditsViewController.h"

@interface DOCreditsViewController ()

@end

@implementation DOCreditsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (id)specifiers {
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Credits" target:self];
    }
    return _specifiers;
}

@end
