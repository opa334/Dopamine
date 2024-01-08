#include "primitives.h"
#include "kernel.h"
#include "pte.h"
#include "translation.h"
#include <mach/mach.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#define PERM_KRW_URW 0x7 // R/W for kernel and user
#define FAKE_PHYSPAGE_TO_MAP 0x13370000
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

	// Allocate a page
	vm_address_t start = (data.min_address & ~L2_BLOCK_MASK) + L2_BLOCK_SIZE;
	for (vm_address_t cur = start; cur < data.max_address; cur += L2_BLOCK_SIZE) {
		uint64_t lvl = PMAP_TT_L3_LEVEL;
		uint64_t tte_lvl2 = 0;
		vtophys_lvl(ttep, cur, &lvl, &tte_lvl2);
		
		if (!((tte_lvl2 != 0) && lvl > PMAP_TT_L1_LEVEL)) {
			free_lvl2 = cur;
			break;
		}
	}

	// Allocate page table
	if (vm_allocate(mach_task_self(), &free_lvl2, 0x4000, VM_FLAGS_FIXED) != KERN_SUCCESS) return 0;
	*(volatile uint64_t *)free_lvl2;

	// Get pointer to allocated page table
	uint64_t lvl = PMAP_TT_L3_LEVEL;
	uint64_t tte_lvl3 = 0, tte_lvl2;
	vtophys_lvl(ttep, free_lvl2, &lvl, &tte_lvl3);
	lvl = PMAP_TT_L2_LEVEL;
	vtophys_lvl(ttep, free_lvl2, &lvl, &tte_lvl2);
	uint64_t allocatedPT = (tte_lvl3 & ~PAGE_MASK);

	// Bump reference count of page table by one
	uint64_t pvh = pai_to_pvh(pa_index(allocatedPT));
	uint64_t ptdp = pvh_ptd(pvh);
	uint64_t pinfo = kread64(ptdp + 0x20); // TODO: Fake 16k devices (4 values)
	kwrite16(pinfo, kread16(pinfo)+1);

	// Deallocate page (page table will stay)
	vm_deallocate(mach_task_self(), free_lvl2, 0x4000);

	kwrite16(pinfo, kread16(pinfo)-1);

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

	kwrite64(ptdp + 0x10, pmap);
	kwrite64(ptdp + 0x18, va);  // TODO: Fake 16k devices (4 values)

	return tt_p;
}


void test_pte(void)
{
	/*printf("1\n");
	tt_entry_free_groom();
	tt_entry_free_groom();
	printf("2\n");
	_tt_entry_print();
	return;*/

	uint64_t pt = pmap_alloc_page_table(0, 0x6000000000);
	printf("Allocated page table: 0x%llx\n", pt);
	
	uint64_t ttep = kread64(pmap_self() + koffsetof(pmap, ttep));
	physwrite64(ttep + (6 * sizeof(uint64_t)), (pt | ARM_TTE_VALID | ARM_TTE_TYPE_TABLE));

	printf("Wrote allocated page table\n");
	sleep(5);
}

/*uint64_t pmap_alloc_page_for_kern(unsigned int options)
{
	return kcall(bootInfo_getSlidUInt64(@"pmap_alloc_page_for_kern"), 1, (const uint64_t[]){ options });
}

void pmap_mark_page_as_ppl_page(uint64_t pa)
{
	kcall(bootInfo_getSlidUInt64(@"pmap_mark_page_as_ppl_page"), 1, (const uint64_t[]){ pa });
}

void pmap_alloc_page_for_ppl(unsigned int options)
{
	//thread_t self = current_thread();

	//uint16_t thread_options = self->options;
	//self->options |= TH_OPT_VMPRIV;
	uint64_t pa = pmap_alloc_page_for_kern(options);
	//self->options = thread_options;

	if (pa != 0) {
		pmap_mark_page_as_ppl_page(pa);
	}
}

kern_return_t pmap_enter_options_addr(uint64_t pmap, uint64_t pa, uint64_t va) {
	while (1) {
		kern_return_t kr = (kern_return_t)kcall8(bootInfo_getSlidUInt64(@"pmap_enter_options_addr"), pmap, va, pa, VM_PROT_READ | VM_PROT_WRITE, 0, 0, 1, 1);
		if (kr != KERN_RESOURCE_SHORTAGE) {
			return kr;
		}
		else {
			// On resource shortage, alloc new page
			//pmap_alloc_page_for_ppl(0);
		}
	}
}

void pmap_remove(uint64_t pmap, uint64_t start, uint64_t end) {
	kcall8(bootInfo_getSlidUInt64(@"pmap_remove_options"), pmap, start, end, 0x100, 0, 0, 0, 0);
}*/

int pmap_map_in(uint64_t pmap, uint64_t ua, uint64_t pa, uint64_t size)
{
	/*uint64_t mappingUaddr = ua & ~L2_BLOCK_MASK;
	uint64_t mappingPA = pa & ~L2_BLOCK_MASK;

	uint64_t endPA = pa + size;
	uint64_t mappingEndPA = endPA & ~L2_BLOCK_MASK;

	uint64_t l2Count = ((mappingEndPA - mappingPA) / L2_BLOCK_SIZE) + 1;

	for (uint64_t i = 0; i < l2Count; i++) {
		uint64_t curMappingUaddr = mappingUaddr + (i * L2_BLOCK_SIZE);
		kern_return_t kr = pmap_enter_options_addr(pmap, FAKE_PHYSPAGE_TO_MAP, curMappingUaddr);
		if (kr != KERN_SUCCESS) {
			pmap_remove(pmap, mappingUaddr, curMappingUaddr);
			return -7;
		}
	}

	// Temporarily change pmap type to nested
	pmap_set_type(pmap, 3);
	// Remove mapping (table will not be removed because we changed the pmap type)
	pmap_remove(pmap, mappingUaddr, mappingUaddr + (l2Count * L2_BLOCK_SIZE));
	// Change type back
	pmap_set_type(pmap, 0);

	for (uint64_t i = 0; i < l2Count; i++) {
		uint64_t curMappingUaddr = mappingUaddr + (i * L2_BLOCK_SIZE);
		uint64_t curMappingPA = mappingPA + (i * L2_BLOCK_SIZE);

		// Create full table for this mapping
		uint64_t tableToWrite[2048];
		for (int k = 0; k < 2048; k++) {
			uint64_t curMappingPage = curMappingPA + (k * 0x4000);
			if (curMappingPage >= pa || curMappingPage < (pa + size)) {
				tableToWrite[k] = curMappingPage | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
			}
			else {
				tableToWrite[k] = 0;
			}
		}

		// Replace table with the entries we generated
		uint64_t table2Entry = pmap_lv2(pmap, curMappingUaddr);
		if ((table2Entry & 0x3) == 0x3) {
			uint64_t table3 = table2Entry & 0xFFFFFFFFC000ULL;
			physwritebuf(table3, tableToWrite, 0x4000);
		}
		else {
			return -6;
		}
	}*/

	return 0;
}

int handoffPPLPrimitives(pid_t pid)
{
	/*if (!pid) return -1;

	int ret = 0;

	bool proc_needs_release = false;
	uint64_t proc = proc_for_pid(pid, &proc_needs_release);
	if (proc) {
		uint64_t task = proc_get_task(proc);
		if (task) {
			uint64_t vmMap = task_get_vm_map(task);
			if (vmMap) {
				uint64_t pmap = vm_map_get_pmap(vmMap);
				if (pmap) {
					uint64_t existingLevel1Entry = kread64(pmap_get_ttep(pmap) + (8 * PPLRW_USER_MAPPING_TTEP_IDX));
					// If there is an existing level 1 entry, we assume the process already has PPLRW primitives
					// Normally there cannot be mappings above 0x3D6000000, so this assumption should always be true
					// If we would try to handoff PPLRW twice, the second time would cause a panic because the mapping already exists
					// So this check protects the device from kernel panics, by not adding the mapping if the process already has it
					if (existingLevel1Entry == 0)
					{
						// Map the entire kernel physical address space into the userland process, starting at PPLRW_USER_MAPPING_OFFSET
						uint64_t physBase = kread64(bootInfo_getSlidUInt64(@"gPhysBase"));
						uint64_t physSize = kread64(bootInfo_getSlidUInt64(@"gPhysSize"));
						ret = pmap_map_in(pmap, physBase+PPLRW_USER_MAPPING_OFFSET, physBase, physSize);
					}
				}
				else { ret = -5; }
			}
			else { ret = -4; }
		}
		else { ret = -3; }
		if (proc_needs_release) proc_rele(proc);
	}
	else { ret = -2; }

	return ret;*/
	return -1;
}