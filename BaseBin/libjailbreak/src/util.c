#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include <spawn.h>
extern char **environ;

void proc_iterate(void (^itBlock)(uint64_t, bool*))
{
	uint64_t proc = ksymbol(allproc);
	while((proc = kread_ptr(proc + koffsetof(proc, list_next))))
	{
		bool stop = false;
		itBlock(proc, &stop);
		if(stop) return;
	}
}

uint64_t proc_self(void)
{
	static uint64_t gSelfProc = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bool needsRelease = false;
		gSelfProc = proc_find(getpid());
		// decrement ref count again, we assume proc_self will exist for the whole lifetime of this process
		proc_rele(gSelfProc);
	});
	return gSelfProc;
}

uint64_t task_self(void)
{
	static uint64_t gSelfTask = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfTask = proc_task(proc_self());
	});
	return gSelfTask;
}

uint64_t vm_map_self(void)
{
	static uint64_t gSelfMap = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfMap = kread_ptr(task_self() + koffsetof(task, map));
	});
	return gSelfMap;
}

uint64_t pmap_self(void)
{
	static uint64_t gSelfPmap = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfPmap = kread_ptr(vm_map_self() + koffsetof(vm_map, pmap));
	});
	return gSelfPmap;
}

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port)
{
	uint64_t itk_space = kread_ptr(task + koffsetof(task, itk_space));
	return ipc_entry_lookup(itk_space, port);
}

uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port)
{
	return kread_ptr(task_get_ipc_port_table_entry(task, port) + koffsetof(ipc_entry, object));
}

uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port)
{
	return kread_ptr(task_get_ipc_port_object(task, port) + koffsetof(ipc_port, kobject));
}

int exec_cmd(const char *binary, ...)
{
	int argc = 0;
	va_list args;
    va_start(args, binary);
	while (va_arg(args, const char *)) argc++;
	va_end(args);

	va_start(args, binary);
	const char *argv[argc+1];
	for (int i = 0; i < argc; i++) {
		argv[i] = va_arg(args, const char *);
	}
	argv[argc] = NULL;

	pid_t spawnedPid = 0;
	int spawnError = posix_spawn(&spawnedPid, binary, NULL, NULL, (char *const *)argv, environ);
	if (spawnError != 0) return spawnError;

	int status = 0;
	do {
		if (waitpid(spawnedPid, &status, 0) == -1) {
			return -1;
		}
	} while (!WIFEXITED(status) && !WIFSIGNALED(status));

	return status;
}