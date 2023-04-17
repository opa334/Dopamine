#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/wait.h>
#import <mach/mach.h>
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>

typedef struct {
	mach_vm_address_t address;
	mach_vm_size_t size;
	vm_prot_t prot;
	vm_prot_t max_prot;
} mem_region_info_t;
extern kern_return_t mach_vm_region_recurse(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, natural_t *nesting_depth, vm_region_recurse_info_t info, mach_msg_type_number_t *infoCnt);

mem_region_info_t *dump_regions(task_t task, int *region_count_out)
{
	mem_region_info_t *regions = (mem_region_info_t *)malloc(sizeof(mem_region_info_t));
	int region_count = 0;
	int max_regions = 1;

	mach_vm_address_t start = 0x0;
	int depth = 64;
	while (1) {
		if (region_count >= max_regions) {
			max_regions *= 2;
			regions = (mem_region_info_t *)realloc(regions, max_regions * sizeof(mem_region_info_t));
		}

		mach_vm_address_t address = start;
		mach_vm_size_t size = 0;
		uint32_t depth0 = depth;
		vm_region_submap_info_data_64_t info;
		mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
		kern_return_t kr = mach_vm_region_recurse(task, &address, &size, &depth0, (vm_region_recurse_info_t)&info, &count);
		if (kr != KERN_SUCCESS) {
			break;
		}

		// Store the memory region information in the array
		regions[region_count].address = address;
		regions[region_count].size = size;
		regions[region_count].prot = info.protection;
		regions[region_count].max_prot = info.max_protection;
		region_count++;

		start = address + size;
	}

	if (region_count_out) *region_count_out = region_count;
	return regions;
}

int64_t apply_fork_fixup(pid_t parentPid, pid_t childPid)
{
	NSString *parentPath = proc_get_path(parentPid);
	NSString *childPath = proc_get_path(childPid);
	// very basic check to make sure this is actually a fork flow
	if ([parentPath isEqualToString:childPath]) {
		proc_set_debugged(childPid);

		uint64_t child_proc = proc_for_pid(childPid);
		uint64_t child_task = proc_get_task(child_proc);
		uint64_t child_vm_map = task_get_vm_map(child_task);

		int r = 5;
		task_t parentTaskPort = -1;
		task_t childTaskPort = -1;
		kern_return_t parentKR = task_for_pid(mach_task_self(), parentPid, &parentTaskPort);
		if (parentKR == KERN_SUCCESS) {
			kern_return_t childKR = task_for_pid(mach_task_self(), childPid, &childTaskPort);
			if (childKR == KERN_SUCCESS) {
				r = 0;
				int parentRegionCount = 0;
				mem_region_info_t *parentRegions = dump_regions(parentTaskPort, &parentRegionCount);

				int childRegionCount = 0;
				mem_region_info_t *childRegions = dump_regions(childTaskPort, &childRegionCount);

				for (int i = 0; i < parentRegionCount; i++) {
					mach_vm_address_t parentAddress = parentRegions[i].address;
					mach_vm_size_t parentSize = parentRegions[i].size;
					for (int k = 0; k < childRegionCount; k++) {
						mach_vm_address_t childAddress = childRegions[k].address;
						mach_vm_size_t childSize = childRegions[k].size;
						if (parentAddress == childAddress && parentSize == childSize) {
							vm_prot_t parentProt = parentRegions[i].prot;
							vm_prot_t parentMaxProt = parentRegions[i].max_prot;
							vm_prot_t childProt = childRegions[k].prot;
							vm_prot_t childMaxProt = childRegions[k].max_prot;

							if (childProt != parentProt || childMaxProt != parentMaxProt) {
								uint64_t kchildEntry = vm_map_find_entry(child_vm_map, childAddress);
								if (kchildEntry) {
									vm_map_entry_set_prot(kchildEntry, parentProt, parentMaxProt);
								}
							}
							break;
						}
					}
				}
				mach_port_deallocate(mach_task_self(), childTaskPort);
			}
			mach_port_deallocate(mach_task_self(), parentTaskPort);
		}
		return r;
	}
	else {
		return 10;
	}
}