#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <sandbox.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/mach_param.h>

struct NDR_record_t
{
	uint8_t mig_vers;
	uint8_t if_vers;
	uint8_t reserved1;
	uint8_t mig_encoding;
	uint8_t int_rep;
	uint8_t char_rep;
    uint8_t float_rep;
    uint8_t reserved2;
};

NDR_record_t NDR_record = {
	.mig_vers = 0,
	.if_vers = 0,
	.reserved1 = 0,
	.mig_encoding = 0,
	.int_rep = 1,
	.char_rep = 0,
	.float_rep = 0,
	.reserved2 = 0,
};

#include "dyld.h"

__attribute__((naked)) uint64_t msyscall_errno(uint64_t syscall, ...)
{
    asm(
        "mov x16, x0\n"
        "ldp x0, x1, [sp]\n"
        "ldp x2, x3, [sp, 0x10]\n"
        "ldp x4, x5, [sp, 0x20]\n"
        "ldp x6, x7, [sp, 0x30]\n"
        "svc 0x80\n"
        "b.cs 20f\n"
        "ret\n"
        "20:\n"
        "b _cerror\n"
        );
}

int64_t sandbox_extension_consume(const char *extension_token)
{
	int64_t r = 0xAAAAAAAAAAAAAAAA;
	if (!strcmp(extension_token, "invalid")) return 0;

	struct sandbox_policy_layout data = {
		.profile = (void *)extension_token,
		.len = strlen(extension_token) + 1,
		.container = &r,
	};

	if (__sandbox_ms("Sandbox", 6, &data) != 0) {
		return -1;
	}
	else {
		return r;
	}
}

#if IOS >= 16

// iOS 16+ dyld's do no longer have mach_msg, reimplement it
// We also need to reimplement mach_msg2, since task.c needs it

__options_decl(mach_msg_option64_t, uint64_t, {
	MACH64_MSG_OPTION_NONE                 = 0x0ull,
	/* share lower 32 bits with mach_msg_option_t */
	MACH64_SEND_MSG                        = MACH_SEND_MSG,
	MACH64_RCV_MSG                         = MACH_RCV_MSG,

	MACH64_RCV_LARGE                       = MACH_RCV_LARGE,
	MACH64_RCV_LARGE_IDENTITY              = MACH_RCV_LARGE_IDENTITY,

	MACH64_SEND_TIMEOUT                    = MACH_SEND_TIMEOUT,
	MACH64_SEND_OVERRIDE                   = MACH_SEND_OVERRIDE,
	MACH64_SEND_INTERRUPT                  = MACH_SEND_INTERRUPT,
	MACH64_SEND_NOTIFY                     = MACH_SEND_NOTIFY,
#if KERNEL
	MACH64_SEND_ALWAYS                     = MACH_SEND_ALWAYS,
	MACH64_SEND_IMPORTANCE                 = MACH_SEND_IMPORTANCE,
	MACH64_SEND_KERNEL                     = MACH_SEND_KERNEL,
#endif
	MACH64_SEND_FILTER_NONFATAL            = MACH_SEND_FILTER_NONFATAL,
	MACH64_SEND_TRAILER                    = MACH_SEND_TRAILER,
	MACH64_SEND_NOIMPORTANCE               = MACH_SEND_NOIMPORTANCE,
	MACH64_SEND_NODENAP                    = MACH_SEND_NODENAP,
	MACH64_SEND_SYNC_OVERRIDE              = MACH_SEND_SYNC_OVERRIDE,
	MACH64_SEND_PROPAGATE_QOS              = MACH_SEND_PROPAGATE_QOS,

	MACH64_SEND_SYNC_BOOTSTRAP_CHECKIN     = MACH_SEND_SYNC_BOOTSTRAP_CHECKIN,

	MACH64_RCV_TIMEOUT                     = MACH_RCV_TIMEOUT,

	MACH64_RCV_INTERRUPT                   = MACH_RCV_INTERRUPT,
	MACH64_RCV_VOUCHER                     = MACH_RCV_VOUCHER,

	MACH64_RCV_GUARDED_DESC                = MACH_RCV_GUARDED_DESC,
	MACH64_RCV_SYNC_WAIT                   = MACH_RCV_SYNC_WAIT,
	MACH64_RCV_SYNC_PEEK                   = MACH_RCV_SYNC_PEEK,

	MACH64_MSG_STRICT_REPLY                = MACH_MSG_STRICT_REPLY,
	/* following options are 64 only */

	/* Send and receive message as vectors */
	MACH64_MSG_VECTOR                      = 0x0000000100000000ull,
	/* The message is a kobject call */
	MACH64_SEND_KOBJECT_CALL               = 0x0000000200000000ull,
	/* The message is sent to a message queue */
	MACH64_SEND_MQ_CALL                    = 0x0000000400000000ull,
	/* This message destination is unknown. Used by old simulators only. */
	MACH64_SEND_ANY                        = 0x0000000800000000ull,
	/* This message is a DriverKit call */
	MACH64_SEND_DK_CALL                    = 0x0000001000000000ull,
});

mach_msg_return_t
mach_msg2_internal(
	void *data,
	mach_msg_option64_t option64,
	uint64_t msgh_bits_and_send_size,
	uint64_t msgh_remote_and_local_port,
	uint64_t msgh_voucher_and_id,
	uint64_t desc_count_and_rcv_name,
	uint64_t rcv_size_and_priority,
	uint64_t timeout);

typedef struct {
	/* a mach_msg_header_t* or mach_msg_aux_header_t* */
	mach_vm_address_t               msgv_data;
	/* if msgv_rcv_addr is non-zero, use it as rcv address instead */
	mach_vm_address_t               msgv_rcv_addr;
	mach_msg_size_t                 msgv_send_size;
	mach_msg_size_t                 msgv_rcv_size;
} mach_msg_vector_t;

mach_msg_return_t mach_msg2(
	void *data,
	mach_msg_option64_t option64,
	mach_msg_header_t header,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_t rcv_name,
	uint64_t timeout,
	uint32_t priority)
{
	mach_msg_base_t *base;
	mach_msg_size_t descriptors;

	if (option64 & MACH64_MSG_VECTOR) {
		base = (mach_msg_base_t *)((mach_msg_vector_t *)data)->msgv_data;
	} else {
		base = (mach_msg_base_t *)data;
	}

	if ((option64 & MACH64_SEND_MSG) &&
	    (base->header.msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
		descriptors = base->body.msgh_descriptor_count;
	} else {
		descriptors = 0;
	}

#define MACH_MSG2_SHIFT_ARGS(lo, hi) ((uint64_t)hi << 32 | (uint32_t)lo)
	return mach_msg2_internal(data, option64,
	           MACH_MSG2_SHIFT_ARGS(header.msgh_bits, send_size),
	           MACH_MSG2_SHIFT_ARGS(header.msgh_remote_port, header.msgh_local_port),
	           MACH_MSG2_SHIFT_ARGS(header.msgh_voucher_port, header.msgh_id),
	           MACH_MSG2_SHIFT_ARGS(descriptors, rcv_name),
	           MACH_MSG2_SHIFT_ARGS(rcv_size, priority), timeout);
#undef MACH_MSG2_SHIFT_ARGS
}

kern_return_t mach_msg(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify)
{
	return mach_msg_overwrite(msg, option, send_size, rcv_size, rcv_name, timeout, notify, NULL, 0);
}

#endif

#if IOS >= 18

kern_return_t _kernelrpc_mach_ports_lookup3(task_t target_task, mach_port_t *port1, mach_port_t *port2, mach_port_t *port3);

kern_return_t
mach_ports_lookup(
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

	kr = _kernelrpc_mach_ports_lookup3(target_task, &array[0], &array[1], &array[2]);
	if (kr != KERN_SUCCESS) {
		vm_deallocate(mach_task_self(), addr, size);
		return kr;
	}

	*init_port_set = array;
	*init_port_setCnt = TASK_PORT_REGISTER_MAX;
	return KERN_SUCCESS;
}

#endif