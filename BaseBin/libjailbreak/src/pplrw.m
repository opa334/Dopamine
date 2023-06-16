// Adapted from https://gist.github.com/LinusHenze/4fa58795914fb3c3438531fb3710f3da

#import "pplrw.h"
#import "pte.h"
#import "boot_info.h"
#import "util.h"
#import "kcall.h"
#import "libjailbreak.h"

#import <Foundation/Foundation.h>
#define min(a,b) (((a)<(b))?(a):(b))

static uint64_t *gMagicPage = NULL;
static uint32_t gMagicMappingsRefCounts[2048];

static uint64_t gCpuTTEP = 0;
static dispatch_queue_t gPPLRWQueue = 0;
static void *kPPLRWQueueKey = &kPPLRWQueueKey;
PPLRWStatus gPPLRWStatus = kPPLRWStatusNotInitialized;

void gPPLRWQueue_dispatch(void (^block)(void))
{
	if (dispatch_get_specific(kPPLRWQueueKey) == (__bridge void *)gPPLRWQueue) {
		// Code is already running on the serial queue
		block();
	} else {
		// Code is not running on the serial queue
		dispatch_sync(gPPLRWQueue, block);
	}
}

#define BOGUS_PTE_KADDR 0xFFFFFFE379F84000 // BOGUS address, enough to make fast PPLRW work
#define BOGUS_PTE (BOGUS_PTE_KADDR | KRW_UR_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY)

typedef struct PPLWindow
{
	uint64_t *pteAddress;
	uint32_t *refCountAddress;
	uint64_t *address;
} PPLWindow;

typedef struct MappingContext
{
	PPLWindow* windowsArray;
	uint32_t windowsCount;
} MappingContext;

void tlbFlush(void)
{
	usleep(70);
	usleep(70);
	__asm("dmb sy");
}

static uint64_t __attribute((naked)) __xpaci(uint64_t a)
{
	asm(".long        0xDAC143E0"); // XPACI X0
	asm("ret");
}

uint64_t xpaci(uint64_t a)
{
	// If a looks like a non-pac'd pointer just return it
	if ((a & 0xFFFFFF0000000000) == 0xFFFFFF0000000000) {
		return a;
	}
	return __xpaci(a);
}

// Virtual to physical address translation

uint64_t va_to_pa(uint64_t table, uint64_t virt, bool *err)
{
	JBLogDebug("va_to_pa(table:0x%llX, virt:0x%llX)", table, virt);
	uint64_t table1Off = (virt >> 36ULL) & 0x7ULL;
	uint64_t table1Entry = physread64(table + (8ULL * table1Off));
	if ((table1Entry & 0x3) != 3) {
		JBLogError("[va_to_pa] table1 lookup failure, table1Entry:0x%llX, table1Off: 0x%llX, table:0x%llX virt:0x%llX", table1Entry, table1Off, table, virt);
		if (err) *err = true;
		return 0;
	}
	
	uint64_t table2 = table1Entry & 0xFFFFFFFFC000ULL;
	uint64_t table2Off = (virt >> 25ULL) & 0x7FFULL;
	uint64_t table2Entry = physread64(table2 + (8ULL * table2Off));
	switch (table2Entry & 0x3) {
		case 1:
			// Easy, this is a block
			JBLogDebug("[va_to_pa] translated [tbl2] 0x%llX to 0x%llX", virt, (table2Entry & 0xFFFFFE000000ULL) | (virt & 0x1FFFFFFULL));
			return (table2Entry & 0xFFFFFE000000ULL) | (virt & 0x1FFFFFFULL);
			
		case 3: {
			uint64_t table3 = table2Entry & 0xFFFFFFFFC000ULL;
			uint64_t table3Off = (virt >> 14ULL) & 0x7FFULL;
			JBLogDebug("[va_to_pa] table3: 0x%llX, table3Off: 0x%llX", table3, table3Off);
			uint64_t table3Entry = physread64(table3 + (8ULL * table3Off));
			JBLogDebug("[va_to_pa] table3Entry: 0x%llX", table3Entry);
			
			if ((table3Entry & 0x3) != 3) {
				JBLogError("[va_to_pa] table3 lookup failure, table:0x%llX virt:0x%llX", table3, virt);
				if (err) *err = true;
				return 0;
			}
			
			JBLogDebug("[va_to_pa] translated [tbl3] 0x%llX to 0x%llX", virt, (table3Entry & 0xFFFFFFFFC000ULL) | (virt & 0x3FFFULL));
			return (table3Entry & 0xFFFFFFFFC000ULL) | (virt & 0x3FFFULL);
		}

		default:
			JBLogError("[va_to_pa] table2 lookup failure, table2Entry:%0llX, table:0x%llX virt:0x%llX", table2Entry, table2, virt);
			if (err) *err = true;
			return 0;
	}
}

uint64_t kaddr_to_pa(uint64_t virt, bool *err)
{
	return va_to_pa(gCpuTTEP, virt, err);
}

// PPL primitives

void clearWindows()
{
	for (int i = 0; i < 10; i++) {
		tlbFlush();
	}
	for (int i = 2; i < 2048; i++) {
		if (gMagicMappingsRefCounts[i] == 0) {
			gMagicPage[i] = BOGUS_PTE;
		}
	}
	for (int i = 0; i < 10; i++) {
		tlbFlush();
	}
}

PPLWindow getWindow(uint64_t page)
{
	// This is a stress test
	// If shit is broken and this is enabled, it will slow everything down but increse the amount of crashes by a lot
	// If everything works however, it will not cause any crashes
	/*static int shit = 0;
	shit++;
	if (shit == 15) {
		JBLogDebug("shit clearWindows");
		clearWindows();
		shit = 0;
	}*/

	uint64_t pte = page | KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
	int pteIndex = -1;
	for (int i = 2; i < 2048; i++) {
		if (gMagicPage[i] == pte) {
			pteIndex = i;
			//JBLogDebug("existing entry %d for page %llX", i, page);
			break;
		}
	}

	if (pteIndex == -1) {
		for (int i = 2; i < 2048; i++) {
			if (gMagicPage[i] == BOGUS_PTE) {
				pteIndex = i;
				//JBLogDebug("unused entry %d for page %llX", i, page);
				break;
			}
		}
	}

	if (pteIndex != -1) {
		uint64_t* mapped = (uint64_t*)(((uint64_t)gMagicPage) + (pteIndex << 14));
		PPLWindow window;
		window.pteAddress = &gMagicPage[pteIndex];
		window.refCountAddress = &gMagicMappingsRefCounts[pteIndex];
		window.address = mapped;
		(*window.refCountAddress)++;
		if (*window.pteAddress != pte) {
			*window.pteAddress = pte;
			JBLogDebug("mapping page %ld to physical page 0x%llX (refCount:%u)", window.pteAddress - gMagicPage, page, *window.refCountAddress);
		}
		else {
			JBLogDebug("reusing page %ld for physical page 0x%llX (refCount:%u)", window.pteAddress - gMagicPage, page, *window.refCountAddress);
		}
		usleep(0); // VERY IMPORTANT, DO NOT REMOVE
		__asm("dmb sy");
		return window;
	}

	clearWindows();
	return getWindow(page);
}

PPLWindow* getConcurrentWindows(uint32_t count, uint64_t *pages)
{
	int contiguousPagesStartIndex = -1;

	// Check if these pages are already mapped in contiguously somewhere
	uint32_t curMatchingCount = 0;
	for (int i = 2; i < 2048; i++) {
		uint64_t pte = pages[curMatchingCount] | KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
		if (gMagicPage[i] == pte) {
			curMatchingCount++;
			if (curMatchingCount >= count) {
				contiguousPagesStartIndex = i - (count - 1);
				break;
			}
		}
		else {
			curMatchingCount = 0;
		}
	}

	// If not, find free space
	uint32_t curUnusedCount = 0;
	if (contiguousPagesStartIndex == -1) {
		for (int i = 2; i < 2048; i++) {
			if (gMagicPage[i] == BOGUS_PTE) {
				curUnusedCount++;
				if (curUnusedCount >= count) {
					contiguousPagesStartIndex = i - (count - 1);
					break;
				}
			}
			else
			{
				curUnusedCount = 0;
			}
		}
	}

	if (contiguousPagesStartIndex != -1) {
		PPLWindow* output = malloc(count * sizeof(PPLWindow));
		for (int i = 0; i < count; i++) {
			int pageIndex = contiguousPagesStartIndex+i;
			uint64_t page = pages[i];
			uint64_t pte = page | KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;

			JBLogDebug("[batch] reserving page %d", pageIndex);
			output[i].pteAddress = &gMagicPage[pageIndex];
			output[i].refCountAddress = &gMagicMappingsRefCounts[pageIndex];
			output[i].address = (uint64_t*)(((uint64_t)gMagicPage) + (pageIndex << 14));

			(*output[i].refCountAddress)++;
			if (*output[i].pteAddress != pte) {
				*output[i].pteAddress = pte;
				JBLogDebug("[batch] mapping page %ld to physical page 0x%llX (refCount:%u)", output[i].pteAddress - gMagicPage, page, *output[i].refCountAddress);
			}
			else {
				JBLogDebug("[batch] reusing page %ld for physical page 0x%llX (refCount:%u)", output[i].pteAddress - gMagicPage, page, *output[i].refCountAddress);
			}
			usleep(0); // VERY IMPORTANT, DO NOT REMOVE
			__asm("dmb sy");
		}
		return output;
	}

	clearWindows();
	return getConcurrentWindows(count, pages);
}

void windowDestroy(PPLWindow* window)
{
	JBLogDebug("unmapping page %ld (previously mapped to: 0x%llX)", window->pteAddress - gMagicPage, *window->pteAddress & ~(KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY));
	(*window->refCountAddress)--;
}

// Map a chunk of virtual memory into this process
void *mapInVirtual(uint64_t pageVirtStart, uint32_t pageCount, uint8_t **mappingStart)
{
	if (pageCount == 0) return NULL;

	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		if (mappingStart) *mappingStart = 0;
		return NULL;
	}
	
	__block void *retval = NULL;
	gPPLRWQueue_dispatch(^{
		uint64_t pagesToMap[pageCount];
		for (int i = 0; i < pageCount; i++) {
			bool err = false;
			uint64_t page = kaddr_to_pa(pageVirtStart + (i * 0x4000), &err);
			if (err) {
				JBLogError("[mapInRange] fatal error, aborting");
				return;
			}
			pagesToMap[i] = page;
		}

		PPLWindow *windows = getConcurrentWindows(pageCount, pagesToMap);
		if (mappingStart) *mappingStart = (uint8_t *)windows[0].address;
		MappingContext *mCtx = malloc(sizeof(MappingContext));
		mCtx->windowsArray = windows;
		mCtx->windowsCount = pageCount;
		retval = mCtx;
	});
	return retval;
}

void mappingDestroy(void* ctx)
{
	gPPLRWQueue_dispatch(^{
		MappingContext *mCtx = (MappingContext *)ctx;
		for (int i = 0; i < mCtx->windowsCount; i++) {
			windowDestroy(&mCtx->windowsArray[i]);
		}
		free(mCtx->windowsArray);
		free(mCtx);
	});
}

// Physical read / write

int physreadbuf(uint64_t physaddr, void* output, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		bzero(output, size);
		return -1;
	}

	__block int retval = -1;
	gPPLRWQueue_dispatch(^{
		JBLogDebug("before physread of 0x%llX (size: %zd)", physaddr, size);

		uint64_t pa = physaddr;
		uint8_t *data = output;
		size_t sizeLeft = size;

		while (sizeLeft > 0) {
			uint64_t page = pa & ~P_PAGE_MASK;
			uint64_t pageOffset = pa & P_PAGE_MASK;
			uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

			PPLWindow window = getWindow(page);
			uint8_t *pageAddress = (uint8_t *)window.address;
			memcpy(&data[size - sizeLeft], &pageAddress[pageOffset], readSize);
			windowDestroy(&window);

			pa += readSize;
			sizeLeft -= readSize;
		}

		JBLogDebug("after physread of 0x%llX", physaddr);
		retval = 0;
	});

	return retval;
}

int physwritebuf(uint64_t physaddr, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	__block int retval = -1;
	gPPLRWQueue_dispatch(^{
		JBLogDebug("before physwrite at 0x%llX (size: %zd)", physaddr, size);

		uint64_t pa = physaddr;
		const uint8_t *data = input;
		size_t sizeLeft = size;

		while (sizeLeft > 0) {
			uint64_t page = pa & ~P_PAGE_MASK;
			uint64_t pageOffset = pa & P_PAGE_MASK;
			uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

			PPLWindow window = getWindow(page);
			uint8_t *pageAddress = (uint8_t *)window.address;
			memcpy(&pageAddress[pageOffset], &data[size - sizeLeft], writeSize);
			windowDestroy(&window);

			pa += writeSize;
			sizeLeft -= writeSize;
		}

		JBLogDebug("after physwrite at 0x%llX", physaddr);
		retval = 0;
	});

	return retval;
}

// Virtual read / write

int kreadbuf(uint64_t kaddr, void* output, size_t size)
{
	bzero(output, size);
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	__block int retval = -1;
	gPPLRWQueue_dispatch(^{
		JBLogDebug("before virtread of 0x%llX (size: %zd)", kaddr, size);

		uint64_t va = kaddr;
		uint8_t *data = output;
		size_t sizeLeft = size;

		while (sizeLeft > 0) {
			uint64_t page = va & ~P_PAGE_MASK;
			uint64_t pageOffset = va & P_PAGE_MASK;
			uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

			bool failure = false;
			uint64_t pa = kaddr_to_pa(page, &failure);
			if (failure)
			{
				JBLogError("[kreadbuf] Lookup failure when trying to read %zu bytes at 0x%llX, aborting", size, kaddr);
				return;
			}

			PPLWindow window = getWindow(pa);
			uint8_t *pageAddress = (uint8_t *)window.address;
			memcpy(&data[size - sizeLeft], &pageAddress[pageOffset], readSize);
			windowDestroy(&window);

			va += readSize;
			sizeLeft -= readSize;
		}
		JBLogDebug("after virtread of 0x%llX", kaddr);
		retval = 0;
	});

	return retval;
}

int kwritebuf(uint64_t kaddr, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	__block int retval = -1;
	gPPLRWQueue_dispatch(^{
		JBLogDebug("before virtwrite at 0x%llX (size: %zd)", kaddr, size);

		uint64_t va = kaddr;
		const uint8_t *data = input;
		size_t sizeLeft = size;

		while (sizeLeft > 0) {
			uint64_t page = va & ~P_PAGE_MASK;
			uint64_t pageOffset = va & P_PAGE_MASK;
			uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

			bool failure = false;
			uint64_t pa = kaddr_to_pa(page, &failure);
			if (failure)
			{
				JBLogError("[kwritebuf] Lookup failure when trying to write %zu bytes to 0x%llX, aborting", size, kaddr);
				return;
			}

			PPLWindow window = getWindow(pa);
			uint8_t *pageAddress = (uint8_t *)window.address;
			memcpy(&pageAddress[pageOffset], &data[size - sizeLeft], writeSize);
			windowDestroy(&window);

			va += writeSize;
			sizeLeft -= writeSize;
		}

		JBLogDebug("after virtwrite at 0x%llX", kaddr);
		retval = 0;
	});

	return retval;
}


// Wrappers

uint64_t physread64(uint64_t pa)
{
	uint64_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint64_t physread_ptr(uint64_t pa)
{
	return xpaci(physread64(pa));
}

uint32_t physread32(uint64_t pa)
{
	uint32_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint16_t physread16(uint64_t pa)
{
	uint16_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint8_t physread8(uint64_t pa)
{
	uint8_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}


int physwrite64(uint64_t pa, uint64_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite32(uint64_t pa, uint32_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite16(uint64_t pa, uint16_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite8(uint64_t pa, uint8_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}


uint64_t kread64(uint64_t va)
{
	uint64_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint64_t kread_ptr(uint64_t va)
{
	return xpaci(kread64(va));
}

uint32_t kread32(uint64_t va)
{
	uint32_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint16_t kread16(uint64_t va)
{
	uint16_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint8_t kread8(uint64_t va)
{
	uint8_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}


int kwrite64(uint64_t va, uint64_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite32(uint64_t va, uint32_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite16(uint64_t va, uint16_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite8(uint64_t va, uint8_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

void initPPLPrimitives(uint64_t magicPage)
{
	if (gPPLRWStatus == kPPLRWStatusNotInitialized)
	{
		uint64_t kernelslide = bootInfo_getUInt64(@"kernelslide");

		dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
		gPPLRWQueue = dispatch_queue_create("com.opa334.pplrw", queueAttributes);
		dispatch_queue_set_specific(gPPLRWQueue, kPPLRWQueueKey, (__bridge void *)gPPLRWQueue, NULL);

		gCpuTTEP = bootInfo_getUInt64(@"physical_ttep");
		gMagicPage = (uint64_t*)magicPage;

		memset(&gMagicMappingsRefCounts[0], 0, sizeof(gMagicMappingsRefCounts));
		gMagicMappingsRefCounts[0] = 0xFFFFFFFF;
		gMagicMappingsRefCounts[1] = 0xFFFFFFFF;
		gPPLRWStatus = kPPLRWStatusInitialized;

		JBLogDebug("Initialized PPL primitives with magic page: 0x%llX", magicPage);
	}
}
