// Adapted from https://gist.github.com/LinusHenze/4fa58795914fb3c3438531fb3710f3da

#import "pplrw.h"
#import "pte.h"
#import "boot_info.h"
#import "util.h"
#import "kcall.h"
#import "libjailbreak.h"

#import <Foundation/Foundation.h>
#define min(a,b) (((a)<(b))?(a):(b))

//#undef JBLogDebug
//#undef JBLogError
//#define JBLogDebug(x ...) printf("DEBUG: " x); printf("\n")
//#define JBLogError(x ...) printf("ERROR: " x); printf("\n"); abort()

static uint64_t *gMagicPage = NULL;
static uint32_t gMagicMappingsRefCounts[2048];
static uint64_t gPlaceholderPage = 0;

static uint64_t gCpuTTEP = 0;
static NSLock* gLock = nil;
PPLRWStatus gPPLRWStatus = kPPLRWStatusNotInitialized;

#define PLACEHOLDER_PAGE_ADDR gMagicPage + 0x4000
#define PLACEHOLDER_PAGE_KADDR gPlaceholderPage
#define PLACEHOLDER_PAGE_PTE (PLACEHOLDER_PAGE_KADDR | KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY)

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

// PPL primitives

void clearWindows()
{
	tlbFlush();
	for (int i = 1; i < 2048; i++) {
		if (gMagicMappingsRefCounts[i] == 0) {
			gMagicPage[i] = PLACEHOLDER_PAGE_PTE;
		}
	}
	tlbFlush();
}

// This is the most fucking cursed shit I have ever written but it is fast + reliable
// DO NOT FUCKING TOUCH ANYTHING IN HERE
void windowWaitUntilMapped(PPLWindow *window, uint64_t page)
{
	//JBLogDebug("windowWaitUntilMapped pte %llX", *(uint64_t*)window->pteAddress);
	bool toMapIsPlaceholderPage = (page == PLACEHOLDER_PAGE_KADDR);

	bool worked = false;
	for (int i = 0; i <= 20; i++) {
		usleep(i*16);
		__asm("dmb sy");

		int cmpRet = 0;
		if (PLACEHOLDER_PAGE_KADDR == gCpuTTEP) {
			cmpRet = memcmp((uint8_t *)PLACEHOLDER_PAGE_ADDR, (uint8_t *)window->address, 0x4000);
		}
		else {
			cmpRet = !(*(uint64_t*)PLACEHOLDER_PAGE_ADDR == PLACEHOLDER_PAGE_KADDR);
		}

		//JBLogDebug("memcmp(%p, %p, 0x100) => %d (i:%d)", (uint8_t *)PLACEHOLDER_PAGE_ADDR, (uint8_t *)window->address, cmpRet, i);
		bool mappedInIsPlaceholderPage = (cmpRet == 0);
		if (toMapIsPlaceholderPage == mappedInIsPlaceholderPage) {
			//JBLogDebug("Mapped in PA 0x%llX to local address %p after %dus (PTE: 0x%llX)", page, (uint8_t *)window->address, i+1, *(uint64_t*)window->pteAddress);
			worked = true;
			break;
		}
	}

	if (!worked) {
		// If shit is broken, just do an old flavour flush (not aware of a single instance of this ever not working) and continue
		tlbFlush();
	}
}

PPLWindow getWindow(uint64_t page)
{
	[gLock lock];

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
			if (gMagicPage[i] == PLACEHOLDER_PAGE_PTE) {
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
			JBLogDebug("mapping page %ld to physical page 0x%llX", window.pteAddress - gMagicPage, page);
			windowWaitUntilMapped(&window, page);
		}
		[gLock unlock];
		return window;
	}

	clearWindows();
	[gLock unlock];
	return getWindow(page);
}

PPLWindow* getConcurrentWindows(uint32_t count, uint64_t *pages)
{
	[gLock lock];

	int contiguousPagesStartIndex = -1;

	// Check if these pages are already mapped in contiguously somewhere
	uint32_t curMatchingCount = 0;
	for (int i = 2; i < 2048; i++) {
		uint64_t pte = pages[curMatchingCount] | KRW_URW_PERM | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
		if (gMagicPage[i] == pte) {
			curMatchingCount++;
			if (curMatchingCount >= count) {
				contiguousPagesStartIndex = i - (count - 1);
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
			if (gMagicPage[i] == PLACEHOLDER_PAGE_PTE) {
				curUnusedCount++;
				if (curUnusedCount >= count) {
					contiguousPagesStartIndex = i - (count - 1);
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
				windowWaitUntilMapped(&output[i], page);
			}
		}
		[gLock unlock];
		return output;
	}

	clearWindows();
	[gLock unlock];
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

	uint64_t pagesToMap[pageCount];
	for (int i = 0; i < pageCount; i++) {
		bool err = false;
		uint64_t page = va_to_pa(gCpuTTEP, pageVirtStart + (i * 0x4000), &err);
		if (err) {
			JBLogError("[mapInRange] fatal error, aborting");
			return NULL;
		}
		pagesToMap[i] = page;
	}

	PPLWindow *windows = getConcurrentWindows(pageCount, pagesToMap);
	if (mappingStart) *mappingStart = (uint8_t *)windows[0].address;
	MappingContext *mCtx = malloc(sizeof(MappingContext));
	mCtx->windowsArray = windows;
	mCtx->windowsCount = pageCount;
	return (void *)mCtx;
}

void mappingDestroy(void* ctx)
{
	MappingContext *mCtx = (MappingContext *)ctx;
	for (int i = 0; i < mCtx->windowsCount; i++) {
		windowDestroy(&mCtx->windowsArray[i]);
	}
	free(mCtx->windowsArray);
	free(mCtx);
}

// Physical read / write

int physreadbuf(uint64_t physaddr, void* output, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		bzero(output, size);
		return -1;
	}

	JBLogDebug("before physread of 0x%llX (size: %zd)", physaddr, size);

	uint64_t pa = physaddr;
	uint8_t *data = output;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t page = pa & ~P_PAGE_MASK;
		uint64_t pageOffset = pa & P_PAGE_MASK;
		uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		PPLWindow window = getWindow(page);
		[gLock lock];
		uint8_t *pageAddress = (uint8_t *)window.address;
		memcpy(&data[size - sizeLeft], &pageAddress[pageOffset], readSize);
		[gLock unlock];
		windowDestroy(&window);

		pa += readSize;
		sizeLeft -= readSize;
	}

	JBLogDebug("after physread of 0x%llX", physaddr);
	return 0;
}

int physwritebuf(uint64_t physaddr, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	JBLogDebug("before physwrite at 0x%llX (size: %zd)", physaddr, size);

	uint64_t pa = physaddr;
	const uint8_t *data = input;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t page = pa & ~P_PAGE_MASK;
		uint64_t pageOffset = pa & P_PAGE_MASK;
		uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		PPLWindow window = getWindow(page);
		[gLock lock];
		uint8_t *pageAddress = (uint8_t *)window.address;
		memcpy(&pageAddress[pageOffset], &data[size - sizeLeft], writeSize);
		[gLock unlock];
		windowDestroy(&window);

		pa += writeSize;
		sizeLeft -= writeSize;
	}

	JBLogDebug("after physwrite at 0x%llX", physaddr);
	return 0;
}

// Virtual read / write

int kreadbuf(uint64_t kaddr, void* output, size_t size)
{
	bzero(output, size);
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	JBLogDebug("before virtread of 0x%llX (size: %zd)", kaddr, size);

	uint64_t va = kaddr;
	uint8_t *data = output;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t page = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		bool failure = false;
		uint64_t pa = va_to_pa(gCpuTTEP, page, &failure);
		if (failure)
		{
			JBLogError("[kreadbuf] Lookup failure when trying to read %zu bytes at 0x%llX, aborting", size, kaddr);
			return -1;
		}

		PPLWindow window = getWindow(pa);
		[gLock lock];
		uint8_t *pageAddress = (uint8_t *)window.address;
		memcpy(&data[size - sizeLeft], &pageAddress[pageOffset], readSize);
		[gLock unlock];
		windowDestroy(&window);

		va += readSize;
		sizeLeft -= readSize;
	}

	JBLogDebug("after virtread of 0x%llX", kaddr);
  return 0;
}

int kwritebuf(uint64_t kaddr, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	JBLogDebug("before virtwrite at 0x%llX (size: %zd)", kaddr, size);

	uint64_t va = kaddr;
	const uint8_t *data = input;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t page = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		bool failure = false;
		uint64_t pa = va_to_pa(gCpuTTEP, page, &failure);
		if (failure)
		{
			JBLogError("[kwritebuf] Lookup failure when trying to write %zu bytes to 0x%llX, aborting", size, kaddr);
			return -1;
		}

		PPLWindow window = getWindow(pa);
		[gLock lock];
		uint8_t *pageAddress = (uint8_t *)window.address;
		memcpy(&pageAddress[pageOffset], &data[size - sizeLeft], writeSize);
		[gLock unlock];
		windowDestroy(&window);

		va += writeSize;
		sizeLeft -= writeSize;
	}

	JBLogDebug("after virtwrite at 0x%llX", kaddr);
	return 0;
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

void PPLRW_updatePlaceholderPage(uint64_t kaddr)
{
	uint64_t oldPage = gPlaceholderPage;
	uint64_t oldPTE = PLACEHOLDER_PAGE_PTE;
	gPlaceholderPage = kaddr;

	for (int i = 1; i < 2048; i++) {
		if (oldPage == 0 || gMagicPage[i] == oldPTE) {
			gMagicPage[i] = PLACEHOLDER_PAGE_PTE;
		}
	}
	tlbFlush();
}

void initPPLPrimitives(uint64_t magicPage)
{
	if (gPPLRWStatus == kPPLRWStatusNotInitialized)
	{
		uint64_t kernelslide = bootInfo_getUInt64(@"kernelslide");

		gCpuTTEP = bootInfo_getUInt64(@"physical_ttep");
		gPlaceholderPage = 0;
		gMagicPage = (uint64_t*)magicPage;
		gLock = [[NSLock alloc] init];

		memset(&gMagicMappingsRefCounts[0], 0, sizeof(gMagicMappingsRefCounts));
		gMagicMappingsRefCounts[0] = 0xFFFFFFFF;
		gMagicMappingsRefCounts[1] = 0xFFFFFFFF;

		// If no proper placeholder page exist yet, use TTEP as placeholder page for the time being
		uint64_t placeholderPageToUse = bootInfo_getUInt64(@"pplrw_placeholder_page") ?: gCpuTTEP; 
		PPLRW_updatePlaceholderPage(placeholderPageToUse); 
	
		gPPLRWStatus = kPPLRWStatusInitialized;

		JBLogDebug("Initialized PPL primitives with magic page: 0x%llX", magicPage);
	}
}
