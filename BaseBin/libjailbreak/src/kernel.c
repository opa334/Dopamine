#include "kernel.h"
#include <stdbool.h>
#include "primitives.h"
#include <dispatch/dispatch.h>

struct system_info gSystemInfo = { 0 };

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

uint64_t proc_find(pid_t pidToFind)
{
	__block uint64_t foundProc = 0;
	proc_iterate(^(uint64_t proc, bool *stop) {
		pid_t pid = kread32(proc + koffsetof(proc, pid));
		if (pid == pidToFind) {
			foundProc = proc;
			*stop = true;
		}
	});
	return foundProc;
}

int proc_rele(uint64_t proc)
{
	return -1;
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
		gSelfTask = kread_ptr(proc_self() + koffsetof(proc, task));
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