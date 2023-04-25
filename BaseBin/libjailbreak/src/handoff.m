#import "kcall.h"
#import "pplrw.h"
#import "pte.h"
#import "boot_info.h"
#import "util.h"

#define PERM_KRW_URW 0x7 // R/W for kernel and user
#define FAKE_PHYSPAGE_TO_MAP 0x13370000
#define PPL_MAP_ADDR         0x2000000 // This is essentially guaranteed to be unused, minimum address is usually 0x100000000

kern_return_t pmap_enter_options_addr(uint64_t pmap, uint64_t pa, uint64_t va) {
    while (1) {
        kern_return_t kr = (kern_return_t) kcall8(bootInfo_getSlidUInt64(@"pmap_enter_options_addr"), pmap, va, pa, VM_PROT_READ | VM_PROT_WRITE, 0, 0, 1, 1);
        if (kr != KERN_RESOURCE_SHORTAGE) {
            return kr;
        }
    }
}

void pmap_remove(uint64_t pmap, uint64_t start, uint64_t end) {
    kcall8(bootInfo_getSlidUInt64(@"pmap_remove_options"), pmap, start, end, 0x100, 0, 0, 0, 0);
}

int handoffPPLPrimitives(pid_t pid, uint64_t *magicPageOut)
{
	if (!pid || !magicPageOut) return -1;

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
					kern_return_t kr = pmap_enter_options_addr(pmap, FAKE_PHYSPAGE_TO_MAP, PPL_MAP_ADDR);
					if (kr == KERN_SUCCESS) {
						// Temporarily change pmap type to nested
						pmap_set_type(pmap, 3);

						// Remove mapping (table will not be removed because we changed the pmap type)
						pmap_remove(pmap, PPL_MAP_ADDR, PPL_MAP_ADDR + 0x4000);

						// Change type back
						pmap_set_type(pmap, 0);

						// Change the mapping to map the underlying page table
						uint64_t table2Entry = pmap_lv2(pmap, PPL_MAP_ADDR);
						if ((table2Entry & 0x3) == 0x3) {
							uint64_t table3 = table2Entry & 0xFFFFFFFFC000ULL;
							uint64_t pte = table3 | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY;
							physwrite64(table3, pte);

							*magicPageOut = PPL_MAP_ADDR;
						}
						else { ret = -7; }
					}
					else { ret = -6; }
				}
				else { ret = -5; }
			}
			else { ret = -4; }
		}
		else { ret = -3; }
		if (proc_needs_release) proc_rele(proc);
	}
	else { ret = -2; }

	return ret;
}