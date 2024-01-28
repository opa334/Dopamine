
#import <UIKit/UITableViewCell.h>

@class UIImageView, NSString, PSSpecifier, UILongPressGestureRecognizer;

@interface PSTableCell : UITableViewCell {
    
	id _value;
	UIImageView* _checkedImageView;
	BOOL _checked;
	BOOL _shouldHideTitle;
	NSString* _hiddenTitle;
	int _alignment;
	SEL _pAction;
	id _pTarget;
	BOOL _cellEnabled;
	PSSpecifier* _specifier;
	int _type;
	BOOL _lazyIcon;
	BOOL _lazyIconDontUnload;
	BOOL _lazyIconForceSynchronous;
	NSString* _lazyIconAppID;
	BOOL _reusedCell;
	BOOL _isCopyable;
	UILongPressGestureRecognizer* _longTapRecognizer;
    
}

@property (assign,nonatomic) int type;                                                      //@synthesize type=_type - In the implementation block
@property (assign,nonatomic) BOOL reusedCell;                                               //@synthesize reusedCell=_reusedCell - In the implementation block
@property (assign,nonatomic) BOOL isCopyable;                                               //@synthesize isCopyable=_isCopyable - In the implementation block
@property (nonatomic,retain) PSSpecifier * specifier;                                       //@synthesize specifier=_specifier - In the implementation block
@property (nonatomic,retain) UILongPressGestureRecognizer * longTapRecognizer;              //@synthesize longTapRecognizer=_longTapRecognizer - In the implementation block
+(int)cellStyle;
+(id)reuseIdentifierForSpecifier:(id)arg1 ;
+(Class)cellClassForSpecifier:(id)arg1 ;
+(id)stringFromCellType:(int)arg1 ;
+(id)reuseIdentifierForClassAndType:(int)arg1 ;
+(id)reuseIdentifierForBasicCellTypes:(int)arg1 ;
+(int)cellTypeFromString:(id)arg1 ;
-(id)specifier;
-(id)valueLabel;
-(void)dealloc;
-(void)layoutSubviews;
-(void)setChecked:(BOOL)arg1 ;
-(void)setTitle:(id)arg1 ;
-(BOOL)canPerformAction:(SEL)arg1 withSender:(id)arg2 ;
-(void)setTarget:(id)arg1 ;
-(void)setType:(int)arg1 ;
-(int)type;
-(SEL)action;
-(void)setValue:(id)arg1 ;
-(id)_automationID;
-(void)setAlignment:(int)arg1 ;
-(id)scriptingInfoWithChildren;
-(id)value;
-(BOOL)canBecomeFirstResponder;
-(id)target;
-(id)title;
-(id)titleLabel;
-(void)setHighlighted:(BOOL)arg1 animated:(BOOL)arg2 ;
-(void)setSelected:(BOOL)arg1 animated:(BOOL)arg2 ;
-(void)prepareForReuse;
-(id)_contentString;
-(void)setAction:(SEL)arg1 ;
-(void)copy:(id)arg1 ;
-(void)setIcon:(id)arg1 ;
-(float)textFieldOffset;
-(BOOL)isChecked;
-(id)iconImageView;
-(void)setCellEnabled:(BOOL)arg1 ;
-(BOOL)cellEnabled;
-(BOOL)canReload;
-(void)reloadWithSpecifier:(id)arg1 animated:(BOOL)arg2 ;
-(id)initWithStyle:(int)arg1 reuseIdentifier:(id)arg2 specifier:(id)arg3 ;
-(void)setReusedCell:(BOOL)arg1 ;
-(void)refreshCellContentsWithSpecifier:(id)arg1 ;
-(void)forceSynchronousIconLoadOnNextIconLoad;
-(void)cellRemovedFromView;
-(BOOL)canBeChecked;
-(id)_copyableText;
-(void)longPressed:(id)arg1 ;
-(void)setShouldHideTitle:(BOOL)arg1 ;
-(id)blankIcon;
-(id)getLazyIcon;
-(id)getLazyIconID;
-(void)setValueChangedTarget:(id)arg1 action:(SEL)arg2 specifier:(id)arg3 ;
-(void)setCellTarget:(id)arg1 ;
-(void)setCellAction:(SEL)arg1 ;
-(id)cellTarget;
-(SEL)cellAction;
-(id)titleTextLabel;
-(id)getIcon;
-(BOOL)reusedCell;
-(BOOL)isCopyable;
-(void)setIsCopyable:(BOOL)arg1 ;
-(id)longTapRecognizer;
@end