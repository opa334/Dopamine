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
	ffsys_kill(ffsys_getpid(), SIGSTOP);
}

void parent_fixup(pid_t childPid, bool mightHaveDirtyPages)
{
	/*int status = 0;
	pid_t result = waitpid(childPid, &status, WUNTRACED);
	if (!WIFSTOPPED(status)) return;*/ // if child is not stopped, something went wrong, abort

	// child is waiting for wx_allowed + permission fixups now

	// set it
	int64_t (*jbdswForkFix)(pid_t childPid, bool mightHaveDirtyPages) = dlsym(dlopen("/usr/lib/systemhook.dylib", RTLD_NOW), "jbdswForkFix");
	int64_t fix_ret = jbdswForkFix(childPid, mightHaveDirtyPages);

	// resume child
	kill(childPid, SIGCONT);
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