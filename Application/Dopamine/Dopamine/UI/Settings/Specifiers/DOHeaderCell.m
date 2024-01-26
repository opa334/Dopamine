//
//  DOHeaderCell.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOHeaderCell.h"

@implementation DOHeaderCell

- (id)initWithSpecifier:(PSSpecifier*)specifier
{
    if (self = [super init])
    {
        UILabel *titleLabel = [[UILabel alloc] init];
        [titleLabel setText:[specifier propertyForKey:@"title"]];
        [titleLabel setFont:[UIFont systemFontOfSize:18 weight:UIFontWeightMedium]];
        [titleLabel setTextColor:[UIColor whiteColor]];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self.contentView addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-6],
            [titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor]
        ]];

        UIView *border = [[UIView alloc] init];
        border.translatesAutoresizingMaskIntoConstraints = NO;
        border.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        [self.contentView addSubview:border];

        [NSLayoutConstraint activateConstraints:@[
            [border.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [border.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [border.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
            [border.heightAnchor constraintEqualToConstant:1]
        ]];
    }
    return self;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width
{
	return 75;
}

@end
