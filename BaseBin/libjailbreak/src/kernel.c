#include "kernel.h"
#include <stdbool.h>
#include "primitives.h"
#include "info.h"
#include "util.h"
#include "codesign.h"
#include <dispatch/dispatch.h>

uint64_t proc_find(pid_t pidToFind)
{
	__block uint64_t foundProc = 0;
	// This sucks a bit due to us not being able to take locks
	// If we don't find anything, just repeat 5 times
	// Attempts to avoids conditions where we got thrown off by modifications
	for (int i = 0; i < 5 && !foundProc; i++) {
		proc_iterate(^(uint64_t proc, bool *stop) {
			pid_t pid = kread32(proc + koffsetof(proc, pid));
			if (pid == pidToFind) {
				foundProc = proc;
				*stop = true;
			}
		});
	}
	return foundProc;
}

int proc_rele(uint64_t proc)
{
	// If proc_find doesn't increment the ref count, there is also no need to decrement it again
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

uint64_t proc_ucred(uint64_t proc)
{
	if (gSystemInfo.kernelStruct.proc_ro.exists) {
		uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
		return kread_ptr(proc_ro + koffsetof(proc_ro, ucred));
	}
	else {
		return kread_ptr(proc + koffsetof(proc, ucred));
	}
}

uint32_t proc_getcsflags(uint64_t proc)
{
	if (gSystemInfo.kernelStruct.proc_ro.exists) {
		uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
		return kread32(proc_ro + koffsetof(proc_ro, csflags));
	}
	else {
		return kread32(proc + koffsetof(proc, csflags));
	}
}

void proc_csflags_update(uint64_t proc, uint32_t flags)
{
	if (gSystemInfo.kernelStruct.proc_ro.exists) {
		uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
		kwrite32(proc_ro + koffsetof(proc_ro, csflags), flags);
	}
	else {
		kwrite32(proc + koffsetof(proc, csflags), flags);
	}
}

void proc_csflags_set(uint64_t proc, uint32_t flags)
{
	proc_csflags_update(proc, proc_getcsflags(proc) | (uint32_t)flags);
}

void proc_csflags_clear(uint64_t proc, uint32_t flags)
{
	proc_csflags_update(proc, proc_getcsflags(proc) & ~(uint32_t)flags);
}

uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name)
{
	uint64_t table = 0;
	// New format in iOS 16.1
	if (gSystemInfo.kernelStruct.ipc_space.table_uses_smd) {
		table = kread_smdptr(space + koffsetof(ipc_space, table));
	}
	else {
		table = kread_ptr(space + koffsetof(ipc_space, table));
	}

	return (table + (ksizeof(ipc_entry) * (name >> 8)));
}

uint64_t pa_index(uint64_t pa)
{
	return atop(pa - kread64(ksymbol(vm_first_phys)));
}

uint64_t pai_to_pvh(uint64_t pai)
{
	return kread64(ksymbol(pv_head_table)) + (pai * 8);
}

uint64_t pvh_ptd(uint64_t pvh)
{
	return ((kread64(pvh) & PVH_LIST_MASK) | PVH_HIGH_FLAGS);
}

void task_set_memory_ownership_transfer(uint64_t task, bool value)
{
	kwrite8(task, !!value);
}

int pmap_cs_allow_invalid(uint64_t pmap)
{
	kwrite8(pmap + koffsetof(pmap, wx_allowed), true);
	return 0;
}

int cs_allow_invalid(uint64_t proc, bool emulateFully)
{
	uint64_t task = proc_task(proc);
	uint64_t vm_map = kread_ptr(task + koffsetof(task, map));
	uint64_t pmap = kread_ptr(vm_map + koffsetof(vm_map, pmap));

	if (emulateFully) {
		// Fugu15 Rootful
		//proc_csflags_clear(proc, CS_EXEC_SET_ENFORCEMENT | CS_EXEC_SET_KILL | CS_EXEC_SET_HARD | CS_REQUIRE_LV | CS_ENFORCEMENT | CS_RESTRICT | CS_KILL | CS_HARD | CS_FORCED_LV);
		//proc_csflags_set(proc, CS_DEBUGGED | CS_INVALID_ALLOWED | CS_GET_TASK_ALLOW);

		// XNU
		proc_csflags_clear(proc, CS_KILL | CS_HARD);
		proc_csflags_set(proc, CS_DEBUGGED);

		task_set_memory_ownership_transfer(task, true);
		vm_map_flags flags = { 0 };
		kreadbuf(vm_map + koffsetof(vm_map, flags), &flags, sizeof(flags));
		flags.switch_protect = false;
		flags.cs_debugged = true;
		kwritebuf(vm_map + koffsetof(vm_map, flags), &flags, sizeof(flags));
	}

	// For pmap_cs (arm64e) devices, this is enough to get unsigned code to run
	pmap_cs_allow_invalid(pmap);
	return 0;
}
