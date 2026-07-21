#ifndef STOCK_FIXES_H
#define STOCK_FIXES_H

#include <mach/mach.h>

extern kern_return_t (*___kernelrpc_mach_ports_lookup3)(task_t target_task, mach_port_t *port1, mach_port_t *port2, mach_port_t *port3);

kern_return_t mach_ports_lookup_fixed_reimp(task_t target_task, mach_port_array_t *init_port_set, mach_msg_type_number_t *init_port_setCnt);
kern_return_t mach_ports_lookup_fixed(task_t target_task, mach_port_array_t *init_port_set, mach_msg_type_number_t *init_port_setCnt);

#define mach_ports_lookup mach_ports_lookup_fixed

#endif