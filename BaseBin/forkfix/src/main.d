#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <mach/mach.h>
extern kern_return_t mach_vm_region_recurse(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, natural_t *nesting_depth, vm_region_recurse_info_t info, mach_msg_type_number_t *infoCnt);
#include "syscall.h"
#include <signal.h>
#include "substrate.h"

#include <dlfcn.h>

void printPerms(int perms)
{
	if (perms & VM_PROT_READ) {
		printf("r");
	}
	else {
		printf("-");
	}

	if (perms & VM_PROT_WRITE) {
		printf("w");
	}
	else {
		printf("-");
	}

	if (perms & VM_PROT_EXECUTE) {
		printf("x");
	}
	else {
		printf("-");
	}
}

static void **_libSystem_atfork_prepare_ptr = 0;
static void **_libSystem_atfork_parent_ptr = 0;
static void **_libSystem_atfork_child_ptr = 0;
static void (*_libSystem_atfork_prepare)(void) = 0;
static void (*_libSystem_atfork_parent)(void) = 0;
static void (*_libSystem_atfork_child)(void) = 0;

static void **_libSystem_atfork_prepare_V2_ptr = 0;
static void **_libSystem_atfork_parent_V2_ptr = 0;
static void **_libSystem_atfork_child_V2_ptr = 0;
static void (*_libSystem_atfork_prepare_V2)(int) = 0;
static void (*_libSystem_atfork_parent_V2)(int) = 0;
static void (*_libSystem_atfork_child_V2)(int) = 0;

pid_t *__current_pid;

void loadPrivateSymbols(void) {
	MSImageRef libSystemCHandle = MSGetImageByName("/usr/lib/system/libsystem_c.dylib");
	void *libSystemKernelDLHandle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_NOW);

	_libSystem_atfork_prepare_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_prepare");
	_libSystem_atfork_parent_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_parent");
	_libSystem_atfork_child_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_child");

	_libSystem_atfork_prepare_V2_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_prepare_v2");
	_libSystem_atfork_parent_V2_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_parent_v2");
	_libSystem_atfork_child_V2_ptr = MSFindSymbol(libSystemCHandle, "__libSystem_atfork_child_v2");

	if (_libSystem_atfork_prepare_ptr) _libSystem_atfork_prepare = (void (*)(void))*_libSystem_atfork_prepare_ptr;
	if (_libSystem_atfork_parent_ptr) _libSystem_atfork_parent = (void (*)(void))*_libSystem_atfork_parent_ptr;
	if (_libSystem_atfork_child_ptr) _libSystem_atfork_child = (void (*)(void))*_libSystem_atfork_child_ptr;
	if (_libSystem_atfork_prepare_V2_ptr) _libSystem_atfork_prepare_V2 = (void (*)(int))*_libSystem_atfork_prepare_V2_ptr;
	if (_libSystem_atfork_parent_V2_ptr) _libSystem_atfork_parent_V2 = (void (*)(int))*_libSystem_atfork_parent_V2_ptr;
	if (_libSystem_atfork_child_V2_ptr) _libSystem_atfork_child_V2 = (void (*)(int))*_libSystem_atfork_child_V2_ptr;

	__current_pid = dlsym(libSystemKernelDLHandle, "_current_pid");
}

typedef struct {
	mach_vm_address_t address;
	mach_vm_size_t size;
	vm_prot_t prot;
	vm_prot_t maxprot;
} mem_region_info_t;

int region_count = 0;
mem_region_info_t *regions = NULL;

mem_region_info_t *dump_regions(int *region_count_out)
{
	mem_region_info_t *regions = (mem_region_info_t *)malloc(sizeof(mem_region_info_t));
	int region_count = 0;
	int max_regions = 1;

	mach_port_t task = mach_task_self();
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
		regions[region_count].maxprot = info.max_protection;
		region_count++;

		start = address + size;
	}

	if (region_count_out) *region_count_out = region_count;
	return regions;
}

void restore_permissions_safe(mem_region_info_t *regions, int region_count)
{
	for (int i = 0; i < region_count; i++) {
		if (ffsys_vm_protect(mach_task_self_, regions[i].address, regions[i].size, true, regions[i].maxprot) != KERN_SUCCESS) {
			ffsys_vm_protect(mach_task_self_, regions[i].address, regions[i].size, true, regions[i].maxprot | VM_PROT_COPY);
		}
		ffsys_vm_protect(mach_task_self_, regions[i].address, regions[i].size, false, regions[i].prot);
	}
}

void child_fixup(void)
{
	// SIGSTOP and wait for the parent process to enable wx_allowed
	ffsys_kill(ffsys_getpid(), SIGSTOP);

	/*if (regions) {
		// wx_allowed should be applied now, now restore the mappings from before the fork
		restore_permissions_safe(regions, region_count);
	}*/
}

void parent_fixup(pid_t childPid)
{
	int status = 0;
	pid_t result = waitpid(childPid, &status, WUNTRACED);
	if (!WIFSTOPPED(status)) return; // something went wrong, abort

	// child is waiting for wx_allowed now

	// set it
	int64_t (*jbdswDebugForked)(pid_t childPid) = dlsym(dlopen("/usr/lib/systemhook.dylib", RTLD_NOW), "jbdswDebugForked");
	int64_t debug_ret = jbdswDebugForked(childPid);

	// resume child
	kill(childPid, SIGCONT);
}

__attribute__((visibility ("default"))) pid_t forkfix___fork(void)
{
	pid_t pid = ffsys_fork();
	if (pid < 0) return pid;

	if (pid == 0)
	{
		*__current_pid = 0; // this fixup is missing inside forkfix_fork, so we do it here

		child_fixup();
	}

	return pid;
}

__attribute__((visibility ("default"))) pid_t forkfix_fork(void)
{
	// before fork'ing, collect all existant mappings in this process and their permissions
	//regions = dump_regions(&region_count);

	loadPrivateSymbols();

	int ret;

	if (_libSystem_atfork_prepare_V2) {
		_libSystem_atfork_prepare_V2(0);
	}
	else {
		_libSystem_atfork_prepare();
	}

	ret = forkfix___fork();
	if (ret == -1) { // error
		if (_libSystem_atfork_parent_V2) {
			_libSystem_atfork_parent_V2(0);
		}
		else {
			_libSystem_atfork_parent();
		}
		free(regions);
		regions = NULL;
		region_count = 0;
		return ret;
	}

	if (ret == 0) {
		// child
		if (_libSystem_atfork_child_V2) {
			_libSystem_atfork_child_V2(0);
		}
		else {
			_libSystem_atfork_child();
		}

		//void (*jbdswDebugMe)(void) = dlsym(dlopen("/usr/lib/systemhook.dylib", RTLD_NOW), "jbdswDebugMe");
		//jbdswDebugMe();

		/*for (int i = 0; i < region_count; i++) {
			printf("child region 0x%llX - 0x%llX (", regions[i].address, regions[i].address + regions[i].size);
			printPerms(regions[i].prot);
			printf(", ");
			printPerms(regions[i].maxprot);
			printf(")\n");

			
			kern_return_t kr1 = ffsys_vm_protect(mach_task_self_, regions[i].address, 1, false, regions[i].prot);
			printf("kr1 %d, %s\n", kr1, mach_error_string(kr1));
			if (kr1 != KERN_SUCCESS) {
				kern_return_t kr2 = ffsys_vm_protect(mach_task_self_, regions[i].address, 1, false, regions[i].prot | VM_PROT_COPY);
				printf("kr2 %d, %s\n", kr2, mach_error_string(kr2));
				if (kr2 != KERN_SUCCESS) {
					kern_return_t kr3 = ffsys_vm_protect(mach_task_self_, regions[i].address, regions[i].size, true, regions[i].maxprot | VM_PROT_COPY);
					printf("kr3 %d, %s\n", kr3, mach_error_string(kr3));
				}
				ffsys_vm_protect(mach_task_self_, regions[i].address, regions[i].size, false, regions[i].prot);
			}
		}*/

		free(regions);
		regions = NULL;
		region_count = 0;
		return 0;
	}

	// parent
	if (_libSystem_atfork_parent_V2) {
		_libSystem_atfork_parent_V2(0);
	}
	else {
		_libSystem_atfork_parent();
	}

	parent_fixup(ret);

	free(regions);
	regions = NULL;
	region_count = 0;
	return ret;
}

