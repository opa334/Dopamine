#include "primitives.h"
#include "translation.h"
#include "kernel.h"
#include "util.h"
#include "pte.h"
#include "info.h"
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>

// Last L2 block
#define MAGIC_PT_ADDRESS ((8 * L1_BLOCK_SIZE) - L2_BLOCK_SIZE)

uint8_t *gSwAsid = 0;
static pthread_mutex_t gLock;
uint64_t *gMagicPT = (uint64_t *)MAGIC_PT_ADDRESS;

void flush_tlb(void)
{
	uint8_t fakeSwAsid = UINT8_MAX;
	uint8_t origSwAsid = *gSwAsid;
	if (origSwAsid != fakeSwAsid) {
		*gSwAsid = fakeSwAsid;
		__asm("dmb sy");
		usleep(0); // Force context switch
		*gSwAsid = origSwAsid;
		__asm("dmb sy");
	}
}

void acquire_window(uint64_t pa, void (^block)(void *ua))
{
	pthread_mutex_lock(&gLock);

	int toUse = 0;

	// Find existing
	for (int i = 2; i < (PAGE_SIZE / sizeof(uint64_t)); i++) {
		if ((gMagicPT[i] & ARM_TTE_PA_MASK) == pa) {
			toUse = i;
			break;
		}
	}

	// If not found, find empty
	if (toUse == 0) {
		for (int i = 2; i < (PAGE_SIZE / sizeof(uint64_t)); i++) {
			if (!gMagicPT[i]) {
				toUse = i;
				break;
			}
		}
	}

	// If not found, clear page table
	if (toUse == 0) {
		// Reset all entries to 0
		for (int i = 2; i < (PAGE_SIZE / sizeof(uint64_t)); i++) {
			gMagicPT[i] = 0;
		}
		flush_tlb();
		toUse = 2;
	}

	gMagicPT[toUse] = pa | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
	usleep(0);
	__asm("dmb sy");
	usleep(0);

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
			__asm("dmb sy");
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
			__asm("dmb sy");
		});
		return true;
	});
	return r;
}

int physrw_pte_handoff(pid_t pid)
{
	if (!pid) return -1;

	uint64_t proc = proc_find(pid);
	if (!proc) return -2;

	thread_caffeinate_start();

	int ret = 0;
	do {
		uint64_t task = proc_task(proc);
		if (!task) { ret = -3; break; };

		uint64_t vmMap = kread_ptr(task + koffsetof(task, map));
		if (!vmMap) { ret = -4; break; };

		uint64_t pmap = kread_ptr(vmMap + koffsetof(vm_map, pmap));
		if (!pmap) { ret = -5; break; };

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
		if (!magicPT) { ret = -6; break; }
		physwrite64(magicPT, magicPT | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);

		// Map in the pmap at MAGIC_PT_ADDRESS+PAGE_SIZE
		uint64_t sw_asid = pmap + koffsetof(pmap, sw_asid);
		uint64_t sw_asid_page = sw_asid & ~PAGE_MASK;
		uint64_t sw_asid_page_pa = kvtophys(sw_asid_page);
		uint64_t sw_asid_pageoff = sw_asid & PAGE_MASK;
		gSwAsid = (uint8_t *)(MAGIC_PT_ADDRESS + PAGE_SIZE + sw_asid_pageoff);
		physwrite64(magicPT+8, sw_asid_page_pa | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);

		if (pthread_mutex_init(&gLock, NULL) != 0) { ret = -7; break; }

		flush_tlb();
	} while (0);

	thread_caffeinate_stop();
	proc_rele(proc);
	return ret;
}

int libjailbreak_physrw_pte_init(bool receivedHandoff)
{
	if (!receivedHandoff) {
		physrw_pte_handoff(getpid());
	}
	gPrimitives.physreadbuf = physrw_pte_physreadbuf;
	gPrimitives.physwritebuf = physrw_pte_physwritebuf;
	gPrimitives.kreadbuf = NULL;
	gPrimitives.kwritebuf = NULL;

	return 0;
}
