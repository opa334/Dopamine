#import <Foundation/Foundation.h>

#import "trustcache_structs.h"

// 742 cdhashes fit into one page
#define TC_ENTRY_COUNT_PER_PAGE 742

@class JBDTCPage;

extern NSMutableArray<JBDTCPage *> *gTCPages;
extern NSMutableArray<NSNumber *> *gTCUnusedAllocations;
extern dispatch_queue_t gTCAccessQueue;
BOOL tcPagesRecover(void);
void tcPagesChanged(void);


@interface JBDTCPage : NSObject
{
	trustcache_page* _mappedInPage;
	void *_mappedInPageCtx;
	uint32_t _mapRefCount;
}

@property (nonatomic,readonly) uint64_t kaddr;

- (instancetype)initWithKernelAddress:(uint64_t)kaddr;
- (instancetype)initAllocateAndLink;

- (BOOL)mapIn;
- (void)mapOut;

- (void)sort;
- (uint32_t)amountOfSlotsLeft;
- (BOOL)addEntry:(trustcache_entry)entry;
- (BOOL)removeEntry:(trustcache_entry)entry;

- (void)unlinkAndFree;

@end