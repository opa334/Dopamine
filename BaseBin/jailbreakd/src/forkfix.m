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

int64_t apply_fork_fixup(pid_t parentPid, pid_t childPid, bool mightHaveDirtyPages)
{
	NSString *parentPath = proc_get_path(parentPid);
	NSString *childPath = proc_get_path(childPid);
	// very basic check to make sure this is actually a fork flow
	if ([parentPath isEqualToString:childPath]) {
		NSLog(@"running fork debug fixup for %@", childPath);
		proc_set_debugged(childPid);
		if (!mightHaveDirtyPages) return 0;
		NSLog(@"running fork page fixup for %@", childPath);

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
				mach_vm_address_t start_p = 0x0;
				mach_vm_address_t start_c = 0x0;
				int depth = 64;
				while (1) {
					mach_vm_address_t address_p = start_p;
					mach_vm_size_t size_p = 0;
					uint32_t depth0_p = depth;
					vm_region_submap_info_data_64_t info_p;
					mach_msg_type_number_t count_p = VM_REGION_SUBMAP_INFO_COUNT_64;
					kern_return_t kr_p = mach_vm_region_recurse(parentTaskPort, &address_p, &size_p, &depth0_p, (vm_region_recurse_info_t)&info_p, &count_p);

					mach_vm_address_t address_c = start_c;
					mach_vm_size_t size_c = 0;
					uint32_t depth0_c = depth;
					vm_region_submap_info_data_64_t info_c;
					mach_msg_type_number_t count_c = VM_REGION_SUBMAP_INFO_COUNT_64;
					kern_return_t kr_c = mach_vm_region_recurse(childTaskPort, &address_c, &size_c, &depth0_c, (vm_region_recurse_info_t)&info_c, &count_c);

					if (kr_p != KERN_SUCCESS || kr_c != KERN_SUCCESS) {
						break;
					}

					if (address_p < address_c) {
						start_p = address_p + size_p;
						continue;
					}
					else if (address_p > address_c) {
						start_c = address_c + size_c;
						continue;
					}
					else if (info_p.protection != info_c.protection || info_p.max_protection != info_c.max_protection) {
						uint64_t kchildEntry = vm_map_find_entry(child_vm_map, address_c);
						if (kchildEntry) {
							vm_map_entry_set_prot(kchildEntry, info_p.protection, info_p.max_protection);
						}
					}

					start_p = address_p + size_p;
					start_c = address_c + size_c;
				}
				mach_port_deallocate(mach_task_self(), childTaskPort);
			}
			mach_port_deallocate(mach_task_self(), parentTaskPort);
		}
		NSLog(@"fork fixup done for %@", childPath);
		return r;
	}
	else {
		return 10;
	}
}