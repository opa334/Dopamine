#include "kernel.h"
#include <stdbool.h>
#include "primitives.h"
#include "info.h"
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

uint64_t proc_task(uint64_t proc)
{
	if (koffsetof(proc, task)) {
		// iOS <= 15: proc has task attribute
		return kread_ptr(proc + koffsetof(proc, task));
	}
	else {
		// iOS >= 16: task is always at "proc + sizeof(proc)"
		return proc + ksizeof(proc);
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

uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name)
{
	uint64_t table = kread_ptr(space + koffsetof(ipc_space, table));

	// New packed format in iOS 16
	if (gSystemInfo.kernelStruct.ipc_space.table_is_packed) {
		if ((table & 0x4000000000) == 0) {
			if (table) {
				table = (table & 0xFFFFFFBFFFFFC000) | 0x4000000000;
			}
		}
		else {
			table = table & 0xFFFFFFFFFFFFFFE0;
		}
	}
	
	return (table + (ksizeof(ipc_entry) * (name >> 8)));
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
