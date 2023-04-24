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
#include <libproc.h>

struct proc_taskinfo {
	uint64_t                pti_virtual_size;       /* virtual memory size (bytes) */
	uint64_t                pti_resident_size;      /* resident memory size (bytes) */
	uint64_t                pti_total_user;         /* total time */
	uint64_t                pti_total_system;
	uint64_t                pti_threads_user;       /* existing threads only */
	uint64_t                pti_threads_system;
	int32_t                 pti_policy;             /* default policy for new threads */
	int32_t                 pti_faults;             /* number of page faults */
	int32_t                 pti_pageins;            /* number of actual pageins */
	int32_t                 pti_cow_faults;         /* number of copy-on-write faults */
	int32_t                 pti_messages_sent;      /* number of messages sent */
	int32_t                 pti_messages_received;  /* number of messages received */
	int32_t                 pti_syscalls_mach;      /* number of mach system calls */
	int32_t                 pti_syscalls_unix;      /* number of unix system calls */
	int32_t                 pti_csw;                /* number of context switches */
	int32_t                 pti_threadnum;          /* number of threads in the task */
	int32_t                 pti_numrunning;         /* number of running threads */
	int32_t                 pti_priority;           /* task priority*/
};
#define PROC_PIDTASKINFO		4
#define PROC_PIDTASKINFO_SIZE		(sizeof(struct proc_taskinfo))

extern int pid_resume(int pid);

int64_t (*jbdswForkFix)(pid_t childPid, bool mightHaveDirtyPages);

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

void loadPrivateSymbols(void) {
	MSImageRef libSystemCHandle = MSGetImageByName("/usr/lib/system/libsystem_c.dylib");

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

	void *systemhookHandle = dlopen("/usr/lib/systemhook.dylib", RTLD_NOW);
	jbdswForkFix = dlsym(systemhookHandle, "jbdswForkFix");
}

typedef struct {
	mach_vm_address_t address;
	mach_vm_size_t size;
	vm_prot_t prot;
	vm_prot_t maxprot;
} mem_region_info_t;

int region_count = 0;
mem_region_info_t *regions = NULL;

void child_fixup(void)
{
	// late fixup, normally done in ASM
	// ASM is a bitch though and I couldn't out how to do this
	extern pid_t _current_pid;
	_current_pid = 0;

	// SIGSTOP and wait for the parent process to run fixups
	ffsys_pid_suspend(ffsys_getpid());
}

void parent_fixup(pid_t childPid, bool mightHaveDirtyPages)
{
	// Wait until the child is suspended
	struct proc_taskinfo taskinfo;
	int ret;
	do {
		ret = proc_pidinfo(childPid, PROC_PIDTASKINFO, 0, &taskinfo, sizeof(taskinfo));
		if (ret <= 0) {
			perror("proc_pidinfo");
			exit(EXIT_FAILURE);
		}
	} while (taskinfo.pti_numrunning != 0);
	// Child is waiting for wx_allowed + permission fixups now

	// Apply fixup
	int64_t fix_ret = jbdswForkFix(childPid, mightHaveDirtyPages);

	// Resume child
	pid_resume(childPid);
}

__attribute__((visibility ("default"))) pid_t forkfix___fork(void)
{
	pid_t pid = ffsys_fork();
	if (pid < 0) return pid;

	if (pid == 0)
	{
		child_fixup();
	}

	return pid;
}

__attribute__((visibility ("default"))) pid_t forkfix_fork(int is_vfork, bool mightHaveDirtyPages)
{
	int ret;

	if (_libSystem_atfork_prepare_V2) {
		_libSystem_atfork_prepare_V2(is_vfork);
	}
	else {
		_libSystem_atfork_prepare();
	}

	ret = forkfix___fork();
	if (ret == -1) { // error
		if (_libSystem_atfork_parent_V2) {
			_libSystem_atfork_parent_V2(is_vfork);
		}
		else {
			_libSystem_atfork_parent();
		}
		return ret;
	}

	if (ret == 0) {
		// child
		if (_libSystem_atfork_child_V2) {
			_libSystem_atfork_child_V2(is_vfork);
		}
		else {
			_libSystem_atfork_child();
		}
		return 0;
	}

	// parent
	if (_libSystem_atfork_parent_V2) {
		_libSystem_atfork_parent_V2(is_vfork);
	}
	else {
		_libSystem_atfork_parent();
	}

	parent_fixup(ret, mightHaveDirtyPages);
	return ret;
}

__attribute__((constructor)) static void initializer(void)
{
	loadPrivateSymbols();
}