#ifndef KERNEL_H
#define KERNEL_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <mach/mach.h>

uint64_t proc_find(pid_t pidToFind);
uint64_t proc_task(uint64_t proc);
int proc_rele(uint64_t proc);
uint64_t proc_self(void);
uint64_t task_self(void);
uint64_t vm_map_self(void);
uint64_t pmap_self(void);
uint64_t ipc_entry_lookup(uint64_t space, mach_port_name_t name);
uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port);

#endif