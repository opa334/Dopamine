//
//  DOCreditsCell.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOCreditsCell.h"
#import "DOGlobalAppearance.h"

#define CREDITS_CELL_HEIGHT 35

@interface DOCreditsCellItem : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSURL *url;
@end

@implementation DOCreditsCellItem

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        self.label = [[UILabel alloc] init];
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        self.label.textColor = [UIColor whiteColor];
        self.label.alpha = 0.65;
        self.label.textAlignment = NSTextAlignmentLeft;

        [self.contentView addSubview:self.label];
        [NSLayoutConstraint activateConstraints:@[
            [self.label.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor constant:-17 * ([DOGlobalAppearance isRTL] ? -1 : 1)],
            [self.label.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];

        UIImage *chevronImage = [UIImage systemImageNamed:@"chevron.right"];
        chevronImage = [chevronImage imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular]];
        UIImageView *chevronView = [[UIImageView alloc] initWithImage:chevronImage];
        chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        chevronView.tintColor = [UIColor colorWithWhite:1 alpha:self.label.alpha];
        [self.contentView addSubview:chevronView];
        [NSLayoutConstraint activateConstraints:@[
            [chevronView.trailingAnchor constraintEqualToAnchor:self.label.trailingAnchor constant:17],
            [chevronView.centerYAnchor constraintEqualToAnchor:self.label.centerYAnchor],
        ]];
        
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    self.alpha = 0.5;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 1.0;
    }];
    if (self.url)
        [[UIApplication sharedApplication] openURL:self.url options:@{} completionHandler:nil];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 1.0;
    }];
}

- (void)setName:(NSString*)name url:(NSURL*)url
{
    self.label.text = name;
    self.url = url;
}

@end


@interface DOCreditsCell ()
@property (nonatomic, strong) NSArray<NSDictionary*> *names;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation DOCreditsCell

- (id)initWithSpecifier:(PSSpecifier*)specifier
{
    if (self = [super init])
    {
        self.names = [specifier propertyForKey:@"names"];
        
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionVertical;
        layout.minimumInteritemSpacing = 0;
        layout.minimumLineSpacing = 0;
        layout.sectionInset = UIEdgeInsetsMake(0, 0, 0, 0);

        self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        self.collectionView.backgroundColor = [UIColor clearColor];
        self.collectionView.showsVerticalScrollIndicator = NO;
        self.collectionView.showsHorizontalScrollIndicator = NO;

        [self.collectionView registerClass:[DOCreditsCellItem class] forCellWithReuseIdentifier:@"item"];
        self.collectionView.delegate = self;
        self.collectionView.dataSource = self;
        
        [self.contentView addSubview:self.collectionView];

        [NSLayoutConstraint activateConstraints:@[
            [self.collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [self.collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [self.collectionView.topAnchor constraintEqualToAnchor:self.topAnchor constant:0],
            [self.collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-0],
        ]];
        
    }
    return self;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.names.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    DOCreditsCellItem *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"item" forIndexPath:indexPath];
    NSDictionary *name = self.names[indexPath.row];
    [cell setName:name[@"name"] url:[NSURL URLWithString:name[@"link"]]];
    return cell;
}


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return CGSizeMake(collectionView.frame.size.width/2, CREDITS_CELL_HEIGHT);
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width
{
    return CREDITS_CELL_HEIGHT * ceil(self.names.count/2.0);
}



@end
