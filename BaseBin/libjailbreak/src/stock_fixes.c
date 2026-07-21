#include <mach/mach.h>

#include <stdlib.h>
#include <dlfcn.h>
#include <mach/mach_param.h>
#include <dispatch/dispatch.h>

// The stock implementation of mach_ports_lookup is BROKEN on iOS 18.0+
// It wrongly calls vm_allocate on the remote task instead of mach_task_self
kern_return_t (*___kernelrpc_mach_ports_lookup3)(task_t target_task, mach_port_t *port1, mach_port_t *port2, mach_port_t *port3) = NULL;

kern_return_t
mach_ports_lookup_fixed_reimp(
	task_t                  target_task,
	mach_port_array_t      *init_port_set,
	mach_msg_type_number_t *init_port_setCnt)
{
	vm_size_t size = TASK_PORT_REGISTER_MAX * sizeof(mach_port_t);
	mach_port_array_t array;
	vm_address_t addr = 0;
	kern_return_t kr;

	kr = vm_allocate(mach_task_self(), &addr, size, VM_FLAGS_ANYWHERE);
	array = (mach_port_array_t)addr;
	if (kr != KERN_SUCCESS) {
		return kr;
	}

	kr = ___kernelrpc_mach_ports_lookup3(target_task,
		&array[0], &array[1], &array[2]);
	if (kr != KERN_SUCCESS) {
		vm_deallocate(mach_task_self(), addr, size);
		return kr;
	}

	*init_port_set = array;
	*init_port_setCnt = TASK_PORT_REGISTER_MAX;
	return KERN_SUCCESS;
}

kern_return_t
mach_ports_lookup_fixed(
	task_t                  target_task,
	mach_port_array_t      *init_port_set,
	mach_msg_type_number_t *init_port_setCnt)
{
	static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
		___kernelrpc_mach_ports_lookup3 = dlsym(RTLD_DEFAULT, "_kernelrpc_mach_ports_lookup3");
    });

	if (___kernelrpc_mach_ports_lookup3) {
		// In iOS 18 they reimplemented mach_ports_lookup in userspace by wrapping around _kernelrpc_mach_ports_lookup3
		// This is where they introduced the bug, so if this symbol does not exist, we can simply call the original
		return mach_ports_lookup_fixed_reimp(target_task, init_port_set, init_port_setCnt);
	}
	else {
		return mach_ports_lookup(target_task, init_port_set, init_port_setCnt);
	}
}