#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <dlfcn.h>
#include <os/log.h>
#include <util.h>
#include "syscall.h"
#include "litehook.h"
#include <libjailbreak/jbclient_mach.h>

extern void __fork(void);

int childToParentPipe[2];
int parentToChildPipe[2];
static void open_pipes(void)
{
	if (pipe(parentToChildPipe) < 0 || pipe(childToParentPipe) < 0) {
		abort();
	}
}
static void close_pipes(void)
{
	if (ffsys_close(parentToChildPipe[0]) != 0 || ffsys_close(parentToChildPipe[1]) != 0 || ffsys_close(childToParentPipe[0]) != 0 || ffsys_close(childToParentPipe[1]) != 0) {
		abort();
	}
}

void child_fixup(void)
{
	// Tell parent we are waiting for fixup now
	char msg = ' ';
	ffsys_write(childToParentPipe[1], &msg, sizeof(msg));

	// Wait until parent completes fixup
	ffsys_read(parentToChildPipe[0], &msg, sizeof(msg));
}

void parent_fixup(pid_t childPid)
{
	// Wait until the child is ready and waiting
	char msg = ' ';
	read(childToParentPipe[0], &msg, sizeof(msg));

	// Child is waiting for wx_allowed + permission fixups now
	// Apply fixup
	int64_t fix_ret = jbclient_mach_fork_fix(childPid);
	if (fix_ret != 0) {
		kill(childPid, SIGKILL);
		abort();
	}

	// Tell child we are done, this will make it resume
	write(parentToChildPipe[1], &msg, sizeof(msg));
}

__attribute__((visibility ("default"))) pid_t forkfix___fork(void)
{
	open_pipes();

	pid_t pid = ffsys_fork();
	if (pid < 0) {
		close_pipes();
		return pid;
	}

	if (pid == 0) {
		child_fixup();
	}
	else {
		parent_fixup(pid);
	}

	close_pipes();
	return pid;
}

void apply_fork_hook(void)
{
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		litehook_hook_function((void *)__fork, (void *)forkfix___fork);
	});
}

__attribute__((constructor)) static void initializer(void)
{
	apply_fork_hook();
}
