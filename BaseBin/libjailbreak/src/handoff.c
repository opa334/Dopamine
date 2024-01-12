#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "pte.h"
#include "translation.h"
#include "physrw.h"
#include <mach/mach.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#define PERM_KRW_URW 0x7 // R/W for kernel and user
#define FAKE_PHYSPAGE_TO_MAP 0x13370000
#define L1_BLOCK_SIZE 0x1000000000
#define L1_BLOCK_MASK (L1_BLOCK_SIZE-1)
#define L2_BLOCK_SIZE 0x2000000
#define L2_BLOCK_PAGECOUNT (L2_BLOCK_SIZE / PAGE_SIZE)
#define L2_BLOCK_MASK (L2_BLOCK_SIZE-1)

#define atop(x) ((vm_address_t)(x) >> PAGE_SHIFT)

uint64_t pa_index(uint64_t pa)
{
	return atop(pa - kread64(ksymbol(vm_first_phys)));
}

uint64_t pai_to_pvh(uint64_t pai)
{
	return kread64(ksymbol(pv_head_table)) + (pai * 8);
}

#define PVH_TYPE_MASK (0x3UL)
#define PVH_LIST_MASK (~PVH_TYPE_MASK)
#define PVH_FLAG_CPU (1ULL << 62)
#define PVH_LOCK_BIT 61
#define PVH_FLAG_LOCK (1ULL << PVH_LOCK_BIT)
#define PVH_FLAG_EXEC (1ULL << 60)
#define PVH_FLAG_LOCKDOWN_KC (1ULL << 59)
#define PVH_FLAG_HASHED (1ULL << 58)
#define PVH_FLAG_LOCKDOWN_CS (1ULL << 57)
#define PVH_FLAG_LOCKDOWN_RO (1ULL << 56)
#define PVH_FLAG_FLUSH_NEEDED (1ULL << 54)
#define PVH_FLAG_LOCKDOWN_MASK (PVH_FLAG_LOCKDOWN_KC | PVH_FLAG_LOCKDOWN_CS | PVH_FLAG_LOCKDOWN_RO)
#define PVH_HIGH_FLAGS (PVH_FLAG_CPU | PVH_FLAG_LOCK | PVH_FLAG_EXEC | PVH_FLAG_LOCKDOWN_MASK | \
    PVH_FLAG_HASHED | PVH_FLAG_FLUSH_NEEDED)

#define PVH_TYPE_NULL 0x0UL
#define PVH_TYPE_PVEP 0x1UL
#define PVH_TYPE_PTEP 0x2UL
#define PVH_TYPE_PTDP 0x3UL

uint64_t pvh_ptd(uint64_t pvh)
{
	return ((kread64(pvh) & PVH_LIST_MASK) | PVH_HIGH_FLAGS);
}

uint64_t _alloc_page_table(void)
{
	uint64_t pmap = pmap_self();
	uint64_t ttep = kread_ptr(pmap + koffsetof(pmap, ttep));

	vm_address_t free_lvl2 = 0;
	task_vm_info_data_t data = {};
	task_info_t info = (task_info_t)(&data);
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	task_info(mach_task_self(), TASK_VM_INFO, info, &count);

	// Find an unused L3 entry inside an L2 page table of our process
	vm_address_t start = (data.min_address & ~L2_BLOCK_MASK) + L2_BLOCK_SIZE;
	for (vm_address_t cur = start; cur < data.max_address; cur += L2_BLOCK_SIZE) {
		uint64_t lvl = PMAP_TT_L2_LEVEL;
		uint64_t tte_lvl2 = 0;
		uint64_t level3 = vtophys_lvl(ttep, cur, &lvl, &tte_lvl2);
		if (level3 == 0 && lvl == PMAP_TT_L2_LEVEL) {
			free_lvl2 = cur;
			break;
		}
	}

	// Allocate and fault in a page at the unused L3 entry, this will allocate a page table and write it there
	if (vm_allocate(mach_task_self(), &free_lvl2, 0x4000, VM_FLAGS_FIXED) != KERN_SUCCESS) return 0;
	*(volatile uint64_t *)free_lvl2;

	// Find the newly allocated page table
	uint64_t lvl = PMAP_TT_L2_LEVEL;
	uint64_t tte_lvl2 = 0;
	uint64_t allocatedPT = vtophys_lvl(ttep, free_lvl2, &lvl, &tte_lvl2);

	// Bump reference count of our allocated page table by one
	uint64_t pvh = pai_to_pvh(pa_index(allocatedPT));
	uint64_t ptdp = pvh_ptd(pvh);
	uint64_t pinfo = kread64(ptdp + 0x20); // TODO: Fake 16k devices (4 values)
	kwrite16(pinfo, kread16(pinfo)+1);

	// Deallocate page (our allocated page table will stay, because we bumped it's reference count)
	vm_deallocate(mach_task_self(), free_lvl2, 0x4000);

	// Decrement reference count of our allocated page table again
	kwrite16(pinfo, kread16(pinfo)-1);

	// Remove our allocated page table from it's original location
	physwrite64(tte_lvl2, 0);

	return allocatedPT;
}

uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va)
{
	if (!pmap) {
		pmap = pmap_self();
	}

	uint64_t tt_p = _alloc_page_table();

	uint64_t pvh = pai_to_pvh(pa_index(tt_p));
	uint64_t ptdp = pvh_ptd(pvh);

	// At this point the allocated page table is associated
	// to the pmap of this process alongside the address it was allocated on
	// We now need to replace the association with the context in which it will be used
	kwrite64(ptdp + 0x10, pmap);
	kwrite64(ptdp + 0x18, va);  // TODO: Fake 16k devices (4 values)

	return tt_p;
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
				uint64_t newTable = pmap_alloc_page_table(0, pt_va);
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

int handoffPPLPrimitives(pid_t pid)
{
	if (!pid) return -1;

	int ret = 0;

	uint64_t proc = proc_find(pid);
	if (proc) {
		uint64_t task = proc_task(proc);
		if (task) {
			uint64_t vmMap = kread_ptr(task + koffsetof(task, map));
			if (vmMap) {
				uint64_t pmap = kread_ptr(task + koffsetof(vm_map, pmap));
				if (pmap) {
					// Map the entire kernel physical address space into the userland process, starting at PPLRW_USER_MAPPING_OFFSET
					ret = pmap_map_in(pmap, kconstant(physBase)+PPLRW_USER_MAPPING_OFFSET, kconstant(physBase), kconstant(physSize));
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