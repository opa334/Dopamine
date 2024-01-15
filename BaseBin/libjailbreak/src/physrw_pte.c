#include "primitives.h"
#include "translation.h"
#include "handoff.h"
#include "kernel.h"
#include "pte.h"
#include "info.h"
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>

// Last L2 block
#define MAGIC_PT_ADDRESS ((8 * L1_BLOCK_SIZE) - L2_BLOCK_SIZE)

uint8_t *gSwAsid = 0;
pthread_mutex_t gLock;
uint64_t *gMagicPT = (uint64_t *)MAGIC_PT_ADDRESS;

void acquire_window(uint64_t pa, void (^block)(void *ua))
{
	pthread_mutex_lock(&gLock);

	int toUse = 0;
	for (int i = 2; i < (PAGE_SIZE / sizeof(uint64_t)); i++) {
		if (!gMagicPT[i]) {
			toUse = i;
			break;
		}
	}

	if (toUse == 0) {
		// Reset all entries to 0
		for (int i = 2; i < (PAGE_SIZE / sizeof(uint64_t)); i++) {
			gMagicPT[i] = 0;
		}

		// Flush TLB
		uint8_t fakeSwAsid = UINT8_MAX;
		uint8_t origSwAsid = *gSwAsid;
		if (origSwAsid != fakeSwAsid) {
			*gSwAsid = fakeSwAsid;
			__asm("dmb sy");
			usleep(0); // Force context switch
			*gSwAsid = origSwAsid;
			__asm("dmb sy");
		}

		toUse = 2;
	}

	gMagicPT[toUse] = pa | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
	__asm("dmb sy");
	block((void *)(MAGIC_PT_ADDRESS + (toUse * PAGE_SIZE)));

	pthread_mutex_unlock(&gLock);
}

int physrw_pte_physreadbuf(uint64_t pa, void* output, size_t size)
{
	__block int r = 0;
	enumerate_pages(pa, size, PAGE_SIZE, ^bool(uint64_t curPA, size_t curSize) {
		acquire_window(curPA & ~PAGE_MASK, ^(void *ua) {
			void *curUA = ((uint8_t*)ua) + (curPA & PAGE_MASK);
			memcpy(&output[curPA - pa], curUA, curSize);
		});
		return true;
	});
	return r;
}

int physrw_pte_physwritebuf(uint64_t pa, const void* input, size_t size)
{
	__block int r = 0;
	enumerate_pages(pa, size, PAGE_SIZE, ^bool(uint64_t curPA, size_t curSize) {
		acquire_window(curPA & ~PAGE_MASK, ^(void *ua) {
			void *curUA = ((uint8_t*)ua) + (curPA & PAGE_MASK);
			memcpy(curUA, &input[curPA - pa], curSize);
		});
		return true;
	});
	return r;
}

int libjailbreak_physrw_pte_init(void)
{
	uint64_t pmap = pmap_self();

	uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

	// Allocate magic page table to our process at last possible location
	uint64_t leafLevel;
	do {
		leafLevel = PMAP_TT_L3_LEVEL;
		uint64_t pt = 0;
		vtophys_lvl(ttep, MAGIC_PT_ADDRESS, &leafLevel, &pt);
		if (leafLevel != PMAP_TT_L3_LEVEL) {
			uint64_t pt_va = MAGIC_PT_ADDRESS;
			switch (leafLevel) {
				case PMAP_TT_L1_LEVEL: {
					pt_va &= ~L1_BLOCK_MASK;
					break;
				}
				case PMAP_TT_L2_LEVEL: {
					pt_va &= ~L2_BLOCK_MASK;
					break;
				}
			}
			uint64_t newTable = pmap_alloc_page_table(pmap, pt_va);
			physwrite64(pt, newTable | ARM_TTE_VALID | ARM_TTE_TYPE_TABLE);
		}
	} while (leafLevel < PMAP_TT_L3_LEVEL);

	// Map in the magic page table at MAGIC_PT_ADDRESS

	leafLevel = PMAP_TT_L2_LEVEL;
	uint64_t magicPT = vtophys_lvl(ttep, MAGIC_PT_ADDRESS, &leafLevel, NULL);
	if (!magicPT) return -1;
	physwrite64(magicPT, magicPT | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);

	// Map in the pmap at MAGIC_PT_ADDRESS+PAGE_SIZE
	physwrite64(magicPT+8, vtophys(ttep, ((pmap + koffsetof(pmap, sw_asid)) & ~PAGE_MASK)) | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);
	gSwAsid = (uint8_t *)(MAGIC_PT_ADDRESS + PAGE_SIZE + ((pmap + koffsetof(pmap, sw_asid)) & ~PAGE_MASK));
	if (pthread_mutex_init(&gLock, NULL) != 0) return -2;

	gPrimitives.physreadbuf = physrw_pte_physreadbuf;
	gPrimitives.physwritebuf = physrw_pte_physwritebuf;
	gPrimitives.kreadbuf = NULL;
	gPrimitives.kwritebuf = NULL;

	for (int i = 0; i < 10; i++) {
		// Without this some random data aborts happen
		usleep(80);
		__asm("dmb sy");
	}

	return 0;
}