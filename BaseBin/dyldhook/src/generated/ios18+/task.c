#include <mach/mach.h>

#define __DeclareSendRpc(...)
#define __BeforeSendRpc(...)
#define __AfterSendRpc(...)
#define __MachMsgErrorWithoutTimeout(...)

typedef uint64_t mach_msg_option64_t;

mach_msg_return_t
mach_msg2(
	void *data,
	mach_msg_option64_t option64,
	mach_msg_header_t header,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_t rcv_name,
	uint64_t timeout,
	uint32_t priority);

#define MACH64_SEND_KOBJECT_CALL 0x0000000200000000ull

#undef mach_msg
#define mach_msg mig_mach_msg
static inline mach_msg_return_t
mig_mach_msg(
	mach_msg_header_t *msg,
	mach_msg_option_t option,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_name_t rcv_name,
	mach_msg_timeout_t timeout,
	mach_port_name_t notify)
{
	(void)notify;
	return mach_msg2(msg, option | MACH64_SEND_KOBJECT_CALL,
		*msg, send_size, rcv_size, rcv_name, timeout, 0);
}

#define msgh_request_port    msgh_remote_port
#define msgh_reply_port        msgh_local_port

/* Routine task_get_special_port */
kern_return_t task_get_special_port
(
	task_inspect_t task,
	int which_port,
	mach_port_t *special_port
)
{

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		NDR_record_t NDR;
		int which_port;
	} Request __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t special_port;
		/* end of the kernel processed data */
		mach_msg_trailer_t trailer;
	} Reply __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t special_port;
		/* end of the kernel processed data */
	} __Reply __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif
	/*
	 * typedef struct {
	 * 	mach_msg_header_t Head;
	 * 	NDR_record_t NDR;
	 * 	kern_return_t RetCode;
	 * } mig_reply_error_t;
	 */

	union {
		Request In;
		Reply Out;
	} Mess;

	Request *InP = &Mess.In;
	Reply *Out0P = &Mess.Out;

	mach_msg_return_t msg_result;

#ifdef	__MIG_check__Reply__task_get_special_port_t__defined
	kern_return_t check_result;
#endif	/* __MIG_check__Reply__task_get_special_port_t__defined */

	__DeclareSendRpc(3409, "task_get_special_port")

	InP->NDR = NDR_record;

	InP->which_port = which_port;

	InP->Head.msgh_reply_port = mig_get_reply_port();
	InP->Head.msgh_bits = MACH_MSGH_BITS(19, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	InP->Head.msgh_size = (mach_msg_size_t)sizeof(Request);
	InP->Head.msgh_request_port = task;
	InP->Head.msgh_id = 3409;
	InP->Head.msgh_reserved = 0;
	
/* BEGIN VOUCHER CODE */

#ifdef USING_VOUCHERS
	if (voucher_mach_msg_set != NULL) {
		voucher_mach_msg_set(&InP->Head);
	}
#endif // USING_VOUCHERS
	
/* END VOUCHER CODE */

	__BeforeSendRpc(3409, "task_get_special_port")
	msg_result = mach_msg(&InP->Head, MACH_SEND_MSG|MACH_RCV_MSG|MACH_MSG_OPTION_NONE, (mach_msg_size_t)sizeof(Request), (mach_msg_size_t)sizeof(Reply), InP->Head.msgh_reply_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	__AfterSendRpc(3409, "task_get_special_port")
	if (msg_result != MACH_MSG_SUCCESS) {
		__MachMsgErrorWithoutTimeout(msg_result);
	}
	if (msg_result != MACH_MSG_SUCCESS) {
		{ return msg_result; }
	}


#if	defined(__MIG_check__Reply__task_get_special_port_t__defined)
	check_result = __MIG_check__Reply__task_get_special_port_t((__Reply__task_get_special_port_t *)Out0P);
	if (check_result != MACH_MSG_SUCCESS) {
		mach_msg_destroy(&Out0P->Head);
		{ return check_result; }
	}
#endif	/* defined(__MIG_check__Reply__task_get_special_port_t__defined) */

	*special_port = Out0P->special_port.name;
	return KERN_SUCCESS;
}

/* Routine _kernelrpc_mach_ports_lookup3 */
kern_return_t _kernelrpc_mach_ports_lookup3
(
	task_t target_task,
	mach_port_t *port1,
	mach_port_t *port2,
	mach_port_t *port3
)
{

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
	} Request __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t port1;
		mach_msg_port_descriptor_t port2;
		mach_msg_port_descriptor_t port3;
		/* end of the kernel processed data */
		mach_msg_trailer_t trailer;
	} Reply __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
	typedef struct {
		mach_msg_header_t Head;
		/* start of the kernel processed data */
		mach_msg_body_t msgh_body;
		mach_msg_port_descriptor_t port1;
		mach_msg_port_descriptor_t port2;
		mach_msg_port_descriptor_t port3;
		/* end of the kernel processed data */
	} __Reply __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif
	/*
	 * typedef struct {
	 * 	mach_msg_header_t Head;
	 * 	NDR_record_t NDR;
	 * 	kern_return_t RetCode;
	 * } mig_reply_error_t;
	 */

	union {
		Request In;
		Reply Out;
	} Mess;

	Request *InP = &Mess.In;
	Reply *Out0P = &Mess.Out;

	mach_msg_return_t msg_result;

#ifdef	__MIG_check__Reply___kernelrpc_mach_ports_lookup3_t__defined
	kern_return_t check_result;
#endif	/* __MIG_check__Reply___kernelrpc_mach_ports_lookup3_t__defined */

	__DeclareSendRpc(3404, "_kernelrpc_mach_ports_lookup3")

	InP->Head.msgh_reply_port = mig_get_reply_port();
	InP->Head.msgh_bits =
		MACH_MSGH_BITS(19, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	/* msgh_size passed as argument */
	InP->Head.msgh_request_port = target_task;
	InP->Head.msgh_id = 3404;
	InP->Head.msgh_reserved = 0;
	
/* BEGIN VOUCHER CODE */

#ifdef USING_VOUCHERS
	if (voucher_mach_msg_set != NULL) {
		voucher_mach_msg_set(&InP->Head);
	}
#endif // USING_VOUCHERS
	
/* END VOUCHER CODE */

	__BeforeSendRpc(3404, "_kernelrpc_mach_ports_lookup3")
	msg_result = mach_msg(&InP->Head, MACH_SEND_MSG|MACH_RCV_MSG|MACH_MSG_OPTION_NONE, (mach_msg_size_t)sizeof(Request), (mach_msg_size_t)sizeof(Reply), InP->Head.msgh_reply_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	__AfterSendRpc(3404, "_kernelrpc_mach_ports_lookup3")
	if (msg_result != MACH_MSG_SUCCESS) {
		__MachMsgErrorWithoutTimeout(msg_result);
	}
	if (msg_result != MACH_MSG_SUCCESS) {
		{ return msg_result; }
	}


#if	defined(__MIG_check__Reply___kernelrpc_mach_ports_lookup3_t__defined)
	check_result = __MIG_check__Reply___kernelrpc_mach_ports_lookup3_t((__Reply___kernelrpc_mach_ports_lookup3_t *)Out0P);
	if (check_result != MACH_MSG_SUCCESS) {
		mach_msg_destroy(&Out0P->Head);
		{ return check_result; }
	}
#endif	/* defined(__MIG_check__Reply___kernelrpc_mach_ports_lookup3_t__defined) */

	*port1 = Out0P->port1.name;
	*port2 = Out0P->port2.name;
	*port3 = Out0P->port3.name;
	return KERN_SUCCESS;
}