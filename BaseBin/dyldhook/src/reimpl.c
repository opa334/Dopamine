#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <sandbox.h>
#include <limits.h>
#include <mach/mach.h>

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

// mig_get_reply_port has to be reimplemented because the implementation inside dyld accesses TPIDRRO_EL0 (which is NULL when the dyldhook code runs)
// We make the reimplementation store it in a global instead, which is enough since we will only be calling it from one thread anyways
// gMigReplyPort will be invalid after the process forks, so we need to make sure to only use that during the process initialization
// That's why after TPIDRRO_EL0 has been initialized, we will simply use dyld's mig_get_reply_port again, since TPIDRRO_EL0 should be initialized the next time it's called

uint64_t __attribute((noinline, naked)) get_tpidrro_el0(void)
{
	__asm("mrs x0, TPIDRRO_EL0");
	__asm("ret");
}

mach_port_t gMigReplyPort = 0;
mach_port_t dyld_mig_get_reply_port(void);

#if IOS == 15
extern mach_port_t mach_reply_port(void);

mach_port_t mig_get_reply_port(void) {
	if (get_tpidrro_el0() == 0) {
		if (!gMigReplyPort) {
			gMigReplyPort = mach_reply_port();
		}
		return gMigReplyPort;
	}

	return dyld_mig_get_reply_port();
}
#else // iOS 16+

struct mach_port_options gMigOptions = {
	.flags = 0x1000,
};

mach_port_t mig_get_reply_port(void) {
	if (get_tpidrro_el0() == 0) {
		if (!gMigReplyPort) {
			struct mach_port_options options = gMigOptions;
			mach_port_construct(task_self_trap(), &options, 0, &gMigReplyPort);
		}
		return gMigReplyPort;
	}

	return dyld_mig_get_reply_port();
}

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

#ifdef XNU_KERNEL_PRIVATE
	/*
	 * If kmsg has auxiliary data, append it immediate after the message
	 * and trailer.
	 *
	 * Must be used in conjunction with MACH64_MSG_VECTOR
	 */
	MACH64_RCV_LINEAR_VECTOR               = 0x1000000000000000ull,
	/* Receive into highest addr of buffer */
	MACH64_RCV_STACK                       = 0x2000000000000000ull,
	/*
	 * This internal-only flag is intended for use by a single thread per-port/set!
	 * If more than one thread attempts to MACH64_PEEK_MSG on a port or set, one of
	 * the threads may miss messages (in fact, it may never wake up).
	 */
	MACH64_PEEK_MSG                        = 0x4000000000000000ull,
	/*
	 * This is a mach_msg2() send/receive operation.
	 */
	MACH64_MACH_MSG2                       = 0x8000000000000000ull
#endif
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