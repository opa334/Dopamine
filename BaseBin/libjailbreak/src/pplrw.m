// Adapted from https://gist.github.com/LinusHenze/4fa58795914fb3c3438531fb3710f3da

#import "pplrw.h"
#import "pte.h"
#import "boot_info.h"
#import "util.h"
#import "kcall.h"
#import "libjailbreak.h"
#import <errno.h>

#import <Foundation/Foundation.h>
#define min(a,b) (((a)<(b))?(a):(b))

static uint64_t gCpuTTEP = 0, gPhysBase = 0, gPhysSize = 0, gVirtBase = 0;
PPLRWStatus gPPLRWStatus = kPPLRWStatusNotInitialized;

void tlbFlush(void)
{
	usleep(70);
	usleep(70);
	asm("dmb sy");
}

static uint64_t __attribute((naked)) __xpaci(uint64_t a)
{
	asm(".long 0xDAC143E0"); // XPACI X0
	asm("ret");
}

uint64_t unsign_kptr(uint64_t a)
{
	// If a looks like a non-pac'd pointer just return it
	if ((a & 0xFFFFFF0000000000) == 0xFFFFFF0000000000) {
		return a;
	}
	return __xpaci(a);
}

// Address translation

uint64_t phystokv(uint64_t pa)
{
	const uint64_t PTOV_TABLE_SIZE = 8;
	struct ptov_table_entry {
		uint64_t pa;
		uint64_t va;
		uint64_t len;
	} ptov_table[PTOV_TABLE_SIZE];
	kreadbuf(bootInfo_getSlidUInt64(@"ptov_table"), &ptov_table[0], sizeof(ptov_table));

	for (uint64_t i = 0; (i < PTOV_TABLE_SIZE) && (ptov_table[i].len != 0); i++) {
		if ((pa >= ptov_table[i].pa) && (pa < (ptov_table[i].pa + ptov_table[i].len))) {
			return pa - ptov_table[i].pa + ptov_table[i].va;
		}
	}

	return pa - gPhysBase + gVirtBase;
}

uint64_t vtophys(uint64_t ttep, uint64_t va)
{
	errno = 0;
	const uint64_t ROOT_LEVEL = PMAP_TT_L1_LEVEL;
	const uint64_t LEAF_LEVEL = PMAP_TT_L3_LEVEL;

	uint64_t pa = 0;

	for (uint64_t cur_level = ROOT_LEVEL; cur_level <= LEAF_LEVEL; cur_level++) {
		uint64_t offmask, shift, index_mask, valid_mask, type_mask, type_block;
		switch (cur_level) {
			case PMAP_TT_L0_LEVEL: {
				offmask = ARM_16K_TT_L0_OFFMASK;
				shift = ARM_16K_TT_L0_SHIFT;
				index_mask = ARM_16K_TT_L0_INDEX_MASK;
				valid_mask = ARM_TTE_VALID;
				type_mask = ARM_TTE_TYPE_MASK;
				type_block = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L1_LEVEL: {
				offmask = ARM_16K_TT_L1_OFFMASK;
				shift = ARM_16K_TT_L1_SHIFT;
				index_mask = ARM_16K_TT_L1_INDEX_MASK;
				valid_mask = ARM_TTE_VALID;
				type_mask = ARM_TTE_TYPE_MASK;
				type_block = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L2_LEVEL: {
				offmask = ARM_16K_TT_L2_OFFMASK;
				shift = ARM_16K_TT_L2_SHIFT;
				index_mask = ARM_16K_TT_L2_INDEX_MASK;
				valid_mask = ARM_TTE_VALID;
				type_mask = ARM_TTE_TYPE_MASK;
				type_block = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L3_LEVEL: {
				offmask = ARM_16K_TT_L3_OFFMASK;
				shift = ARM_16K_TT_L3_SHIFT;
				index_mask = ARM_16K_TT_L3_INDEX_MASK;
				valid_mask = ARM_PTE_TYPE_VALID;
				type_mask = ARM_PTE_TYPE_MASK;
				type_block = ARM_TTE_TYPE_L3BLOCK;
				break;
			}
			default: {
				errno = 1041;
				return 0;
			}
		}

		uint64_t tte_index = (va & index_mask) >> shift;
		uint64_t tte_pa = ttep + (tte_index * sizeof(uint64_t));
		uint64_t tte = physread64(tte_pa);

		if ((tte & valid_mask) != valid_mask) {
			errno = 1042;
			return 0;
		}

		if ((tte & type_mask) == type_block) {
			pa = ((tte & ARM_TTE_PA_MASK & ~offmask) | (va & offmask));
			break;
		}

		ttep = tte & ARM_TTE_TABLE_MASK;
	}

	return pa;
}

uint64_t kvtophys(uint64_t va)
{
	return vtophys(gCpuTTEP, va);
}

void *phystouaddr(uint64_t pa)
{
	errno = 0;
	bool doBoundaryCheck = (gPhysBase != 0 && gPhysSize != 0);
	if (doBoundaryCheck) {
		if (pa < gPhysBase || pa >= (gPhysBase + gPhysSize)) {
			errno = 1030;
			return 0;
		}
	}

	return (void *)(pa + PPLRW_USER_MAPPING_OFFSET);
}

void *kvtouaddr(uint64_t va)
{
	uint64_t pa = kvtophys(va);
	if (!pa) return 0;
	return phystouaddr(pa);
}

// PPL primitives

// Physical read / write

int physreadbuf(uint64_t pa, void* output, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		bzero(output, size);
		return -1;
	}

	void *uaddr = phystouaddr(pa);
	if (!uaddr && errno != 0) {
		memset(output, 0x0, size);
		return errno;
	}

	asm volatile("dmb sy");
	memcpy(output, uaddr, size);
	return 0;
}

int physwritebuf(uint64_t pa, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	void *uaddr = phystouaddr(pa);
	if (!uaddr && errno != 0) {
		return errno;
	}

	memcpy(uaddr, input, size);
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

	uint64_t va = kaddr;
	uint8_t *data = output;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t virtPage = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		uint64_t physPage = kvtophys(virtPage);
		if (physPage == 0 && errno != 0)
		{
			JBLogError("[kreadbuf] Lookup failure when trying to read %zu bytes at 0x%llX, aborting", size, kaddr);
			return errno;
		}

		int pr = physreadbuf(physPage + pageOffset, &data[size - sizeLeft], readSize);
		if (pr != 0) {
			JBLogError("[kreadbuf] Physical read at %llx failed: %d", physPage + pageOffset, pr);
			return pr;
		}

		va += readSize;
		sizeLeft -= readSize;
	}

	return 0;
}

int kwritebuf(uint64_t kaddr, const void* input, size_t size)
{
	if(gPPLRWStatus == kPPLRWStatusNotInitialized) {
		return -1;
	}

	uint64_t va = kaddr;
	const uint8_t *data = input;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t virtPage = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		uint64_t physPage = kvtophys(virtPage);
		if (physPage == 0 && errno != 0)
		{
			JBLogError("[kwritebuf] Lookup failure when trying to read %zu bytes at 0x%llX, aborting", size, kaddr);
			return errno;
		}

		int pr = physwritebuf(physPage + pageOffset, &data[size - sizeLeft], writeSize);
		if (pr != 0) {
			JBLogError("[kwritebuf] Physical write at %llx failed: %d", physPage + pageOffset, pr);
			return pr;
		}

		va += writeSize;
		sizeLeft -= writeSize;
	}

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
	return unsign_kptr(physread64(pa));
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
	return unsign_kptr(kread64(va));
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
		// Needed for address translation
		gCpuTTEP = bootInfo_getUInt64(@"physical_ttep");

		tlbFlush();
		gPhysBase = kread64(bootInfo_getSlidUInt64(@"gPhysBase"));
		gPhysSize = kread64(bootInfo_getSlidUInt64(@"gPhysSize"));
		gVirtBase = kread64(bootInfo_getSlidUInt64(@"gVirtBase"));

		JBLogDebug("Initialized PPL Primitives");
		gPPLRWStatus = kPPLRWStatusInitialized;
	}
}
