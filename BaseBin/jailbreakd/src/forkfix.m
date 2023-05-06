#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/wait.h>
#import <mach/mach.h>
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
extern int pid_resume(int pid);

typedef struct {
	mach_vm_address_t address;
	mach_vm_size_t size;
	vm_prot_t prot;
	vm_prot_t max_prot;
} mem_region_info_t;
extern kern_return_t mach_vm_region_recurse(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, natural_t *nesting_depth, vm_region_recurse_info_t info, mach_msg_type_number_t *infoCnt);

int64_t apply_fork_fixup(pid_t parentPid, pid_t childPid, bool mightHaveDirtyPages)
{
	int retval = 3;
	NSString *parentPath = proc_get_path(parentPid);
	NSString *childPath = proc_get_path(childPid);
	// very basic check to make sure this is actually a fork flow
	if ([parentPath isEqualToString:childPath]) {
		proc_set_debugged(childPid);
		if (!mightHaveDirtyPages) {
			retval = 0;
		}
		else {
			bool child_proc_needs_release = false;
			uint64_t child_proc = proc_for_pid(childPid, &child_proc_needs_release);
			uint64_t child_task = proc_get_task(child_proc);
			uint64_t child_vm_map = task_get_vm_map(child_task);

			retval = 2;
			task_t parentTaskPort = -1;
			task_t childTaskPort = -1;
			kern_return_t parentKR = task_for_pid(mach_task_self(), parentPid, &parentTaskPort);
			if (parentKR == KERN_SUCCESS) {
				kern_return_t childKR = task_for_pid(mach_task_self(), childPid, &childTaskPort);
				if (childKR == KERN_SUCCESS) {
					retval = 0;
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

			if (child_proc_needs_release) proc_rele(child_proc);
		}
	}

	return retval;
}