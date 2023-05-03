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

int childToParentPipe[2];
int parentToChildPipe[2];

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
	// ASM is a bitch though and I couldn't figure out how to do this
	extern pid_t _current_pid;
	_current_pid = 0;

	ffsys_close(parentToChildPipe[1]);
	ffsys_close(childToParentPipe[0]);

	// Tell parent we are waiting for fixup now
	char msg = ' ';
	ffsys_write(childToParentPipe[1], &msg, sizeof(msg));

	// Wait until parent completes fixup
	ffsys_read(parentToChildPipe[0], &msg, sizeof(msg));

	ffsys_close(parentToChildPipe[0]);
	ffsys_close(childToParentPipe[1]);
}

void parent_fixup(pid_t childPid, bool mightHaveDirtyPages)
{
	close(parentToChildPipe[0]);
	close(childToParentPipe[1]);

	// Wait until the child is ready and waiting
	char msg = ' ';
	read(childToParentPipe[0], &msg, sizeof(msg));

	// Child is waiting for wx_allowed + permission fixups now
	// Apply fixup
	int64_t fix_ret = jbdswForkFix(childPid, mightHaveDirtyPages);
	if (fix_ret != 0) {
		kill(childPid, SIGKILL);
		abort();
	}

	// Tell child we are done, this will make it resume
	write(parentToChildPipe[1], &msg, sizeof(msg));

	close(parentToChildPipe[1]);
	close(childToParentPipe[0]);
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

	if (pipe(parentToChildPipe) < 0 || pipe(childToParentPipe) < 0) {
		return -1;
	}

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