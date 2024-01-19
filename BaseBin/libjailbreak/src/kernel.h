#ifndef KERNEL_H
#define KERNEL_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <mach/mach.h>
#include "pvh.h"

#define P_SUGID 0x00000100
#define atop(x) ((vm_address_t)(x) >> PAGE_SHIFT)

uint64_t proc_find(pid_t pidToFind);
uint64_t proc_task(uint64_t proc);
uint64_t proc_ucred(uint64_t proc);
int proc_rele(uint64_t proc);
uint32_t proc_getcsflags(uint64_t proc);
void proc_csflags_update(uint64_t proc, uint32_t flags);
void proc_csflags_set(uint64_t proc, uint32_t flags);
void proc_csflags_clear(uint64_t proc, uint32_t flags);
uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name);
uint64_t pa_index(uint64_t pa);
uint64_t pai_to_pvh(uint64_t pai);
uint64_t pvh_ptd(uint64_t pvh);

#endif