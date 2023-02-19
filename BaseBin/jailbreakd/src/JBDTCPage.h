#import <Foundation/Foundation.h>

#import "trustcache_structs.h"

@class JBDTCPage;

extern NSMutableArray<JBDTCPage *> *gTCPages;
BOOL tcPagesRecover(void);
void tcPagesChanged(void);


@interface JBDTCPage : NSObject
{
	trustcache_page* _mappedInPage;
	void *_mappedInPageCtx;
}

@property (nonatomic,readonly) uint64_t kaddr;

- (instancetype)initWithKernelAddress:(uint64_t)kaddr;
- (instancetype)initAllocateAndLink;

- (void)mapIn;
- (void)mapOut;

- (void)sort;
- (uint32_t)amountOfSlotsLeft;
- (BOOL)addEntry:(trustcache_entry)entry;
- (BOOL)removeEntry:(trustcache_entry)entry;

- (void)unlinkAndFree;

@end