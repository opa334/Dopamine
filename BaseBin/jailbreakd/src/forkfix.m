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

int64_t apply_fork_fixup(pid_t parentPid, pid_t childPid)
{
	int retval = 3;
	// Safety check to ensure we are actually coming from fork
	if (proc_get_ppid(childPid) == parentPid) {
		proc_set_debugged(childPid);

		bool childProcNeedsRelease = false;
		uint64_t childProc = proc_for_pid(childPid, &childProcNeedsRelease);
		uint64_t childTask = proc_get_task(childProc);
		uint64_t childVmMap = task_get_vm_map(childTask);

		bool parentProcNeedsRelease = false;
		uint64_t parentProc = proc_for_pid(parentPid, &parentProcNeedsRelease);
		uint64_t parentTask = proc_get_task(parentProc);
		uint64_t parentVmMap = task_get_vm_map(parentTask);

		uint64_t parentHeader = vm_map_get_header(parentVmMap);
		uint64_t parentEntry = vm_map_header_get_first_entry(parentHeader);
		uint32_t parentNumEntries = vm_header_get_nentries(parentHeader);

		uint64_t childHeader = vm_map_get_header(childVmMap);
		uint64_t childEntry = vm_map_header_get_first_entry(childHeader);
		uint32_t childNumEntries = vm_header_get_nentries(childHeader);

		uint32_t curChildIndex = 0;
		uint32_t curParentIndex = 0;
		while (curChildIndex < childNumEntries && childEntry != 0 && curParentIndex < parentNumEntries && parentEntry != 0) {
			uint64_t childStart = 0, childEnd = 0;
			vm_entry_get_range(childEntry, &childStart, &childEnd);
			uint64_t parentStart = 0, parentEnd = 0;
			vm_entry_get_range(parentEntry, &parentStart, &parentEnd);

			if (parentStart < childStart) {
				parentEntry = vm_map_entry_get_next_entry(parentEntry);
				curParentIndex++;
			}
			else if (parentStart > childStart) {
				childEntry = vm_map_entry_get_next_entry(childEntry);
				curChildIndex++;
			}
			else {
				vm_prot_t parentProt = 0, parentMaxProt = 0;
				vm_map_entry_get_prot(parentEntry, &parentProt, &parentMaxProt);
				vm_prot_t childProt = 0, childMaxProt = 0;
				vm_map_entry_get_prot(childEntry, &childProt, &childMaxProt);

				if (parentProt != childProt || parentMaxProt != childMaxProt) {
					vm_map_entry_set_prot(childEntry, parentProt, parentMaxProt);
				}

				parentEntry = vm_map_entry_get_next_entry(parentEntry);
				curParentIndex++;
				childEntry = vm_map_entry_get_next_entry(childEntry);
				curChildIndex++;
			}
		}

		if (childProcNeedsRelease) proc_rele(childProc);
		if (parentProcNeedsRelease) proc_rele(parentProc);
		retval = 0;
	}

	return retval;
}