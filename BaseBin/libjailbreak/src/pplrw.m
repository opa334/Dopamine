// Adapted from https://gist.github.com/LinusHenze/4fa58795914fb3c3438531fb3710f3da

#import "pplrw.h"
#import "pte.h"
#import "boot_info.h"
#import "util.h"
#import "kcall.h"
#import "libjailbreak.h"

#import <Foundation/Foundation.h>
#define min(a,b) (((a)<(b))?(a):(b))

static uint64_t gCpuTTEP = 0;
PPLRWStatus gPPLRWStatus = kPPLRWStatusNotInitialized;

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

void *pa_to_uaddr(uint64_t pa)
{
	return (void *)(pa + PPLRW_USER_MAPPING_OFFSET);	
}

uint64_t kaddr_to_pa(uint64_t va, bool *err)
{
	return va_to_pa(gCpuTTEP, va, err);
}

void *kaddr_to_uaddr(uint64_t va, bool *err)
{
	uint64_t pa = kaddr_to_pa(va, err);
	if (!pa) return 0;
	return pa_to_uaddr(pa);
}

// PPL primitives

// Physical read / write

int physreadbuf(uint64_t pa, void* output, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		bzero(output, size);
		return -1;
	}

	asm volatile("dmb sy");
	memcpy(output, pa_to_uaddr(pa), size);
	return 0;
}

int physwritebuf(uint64_t pa, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	memcpy(pa_to_uaddr(pa), input, size);
	asm volatile("dmb sy");
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
	asm volatile("dmb sy");

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
			return -1;
		}

		uint8_t *pageAddress = pa_to_uaddr(pa);
		memcpy(&data[size - sizeLeft], &pageAddress[pageOffset], readSize);

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
		uint64_t pa = kaddr_to_pa(page, &failure);
		if (failure)
		{
			JBLogError("[kwritebuf] Lookup failure when trying to write %zu bytes to 0x%llX, aborting", size, kaddr);
			return -1;
		}

		uint8_t *pageAddress = pa_to_uaddr(pa);
		memcpy(&pageAddress[pageOffset], &data[size - sizeLeft], writeSize);

		va += writeSize;
		sizeLeft -= writeSize;
	}

	asm volatile("dmb sy");
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

void initPPLPrimitives(void)
{
	if (gPPLRWStatus == kPPLRWStatusNotInitialized)
	{
		// Very anti-climatic now, just ensure TLBs are flushed and we should be good
		// (At least as long as something else has mapped the kernel phys space into this process)
		gCpuTTEP = bootInfo_getUInt64(@"physical_ttep");
		tlbFlush();
		JBLogDebug("Initialized PPL primitives");
		gPPLRWStatus = kPPLRWStatusInitialized;
	}
}
