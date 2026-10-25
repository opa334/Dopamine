#include <sandbox.h>
#include <mach/mach.h>

int roothider_inline_version = 0;

#ifdef __arm64e__
#define _TRAMPOLINE_BRANCH "braaz x16\n"
#else
#define _TRAMPOLINE_BRANCH "br x16\n"
#endif

// Match dyldhook: to is the dyld symbol, alias is the local callable name.
// Assembly labels stay local to this object, including reimpl.c's _cerror.
#define MAKE_TRAMPOLINE_ALIAS(to, alias) \
	__typeof__(&alias) roothider_inline_##alias; \
	__asm__(".text\n.p2align 2\n" \
	        "_" #alias ":\n" \
	        "adrp x16, _roothider_inline_" #alias "@PAGE\n" \
	        "ldr x16, [x16, _roothider_inline_" #alias "@PAGEOFF]\n" \
	        _TRAMPOLINE_BRANCH)

#define MAKE_TRAMPOLINE(to) MAKE_TRAMPOLINE_ALIAS(to, to)

// Match dyldhook: preserve arguments, retry EINTR, and return -1 on other BSD errors.
#define SYSCALL_PROLOGUE \
	"stp x0, x1, [sp, #-16]!\n" \
	"stp x2, x3, [sp, #-16]!\n" \
	"stp x4, x5, [sp, #-16]!\n" \
	"stp x6, x7, [sp, #-16]!\n"
#define SYSCALL_EPILOGUE \
	"ldp x6, x7, [sp], #16\n" \
	"ldp x4, x5, [sp], #16\n" \
	"ldp x2, x3, [sp], #16\n" \
	"ldp x0, x1, [sp], #16\n"

#define _ASM_STRINGIFY_IMPL(value) #value
#define _ASM_STRINGIFY(value) _ASM_STRINGIFY_IMPL(value)

#define DEF_SYSCALL(name, num) \
	__typeof__(name) name __asm__("_roothider_syscall_" #name); \
	__asm__(".text\n.p2align 2\n" \
	        ".globl _roothider_syscall_" #name "\n" \
	        ".private_extern _roothider_syscall_" #name "\n" \
	        "_roothider_syscall_" #name ":\n1:\n" \
	        SYSCALL_PROLOGUE \
	        "mov x16, #" _ASM_STRINGIFY(num) "\n" \
	        "svc #0x80\n" \
	        "mov x16, x0\n" \
	        SYSCALL_EPILOGUE \
	        "b.cc 2f\n" \
	        "cmp x16, #4\n" \
	        "b.eq 1b\n" \
	        "mov x16, #-1\n" \
	        "2: mov x0, x16\nret\n")

#define DEF_MACHTRAP(name, num) \
	__typeof__(name) name __asm__("_roothider_machtrap_" #name); \
	__asm__(".text\n.p2align 2\n" \
	        ".globl _roothider_machtrap_" #name "\n" \
	        ".private_extern _roothider_machtrap_" #name "\n" \
	        "_roothider_machtrap_" #name ":\n" \
	        "mov x16, #-" _ASM_STRINGIFY(num) "\n" \
	        "svc #0x80\nret\n")


static void cerror(void);
mach_msg_return_t mach_msg2_internal(void*,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t);

// SYMBOL(to, min, max), ALIAS(to, alias, min, max); max = 0 means unlimited.
#define DYLD_TRAMPOLINE_SYMBOLS(SYMBOL, ALIAS) \
	SYMBOL(cerror, 15, 0) \
	SYMBOL(mach_msg, 15, 15) \
	ALIAS(_kernelrpc_mach_vm_allocate_trap, vm_allocate, 15, 0) \
	ALIAS(_kernelrpc_mach_vm_deallocate_trap, vm_deallocate, 15, 0) \
	SYMBOL(task_self_trap, 15, 0) \
	SYMBOL(mach_msg_destroy, 15, 0) \
	SYMBOL(mach_msg_overwrite, 16, 0) \
	SYMBOL(mach_msg2_internal, 16, 0) \
	SYMBOL(mig_get_reply_port, 15, 0) \
	SYMBOL(mach_port_deallocate, 15, 0)


// Data Symbols
mach_port_t* roothider_inline_mach_task_self_pointer;
#define mach_task_self_      (*roothider_inline_mach_task_self_pointer)


#define DEFINE_INLINE_SYMBOL(to, min, max) MAKE_TRAMPOLINE(to);
#define DEFINE_INLINE_SYMBOL_ALIAS(to, alias, min, max) MAKE_TRAMPOLINE_ALIAS(to, alias);
DYLD_TRAMPOLINE_SYMBOLS(DEFINE_INLINE_SYMBOL, DEFINE_INLINE_SYMBOL_ALIAS)
#undef DEFINE_INLINE_SYMBOL
#undef DEFINE_INLINE_SYMBOL_ALIAS

// The caller resolves each name and fills its storage; no initialization here.
void roothider_inline_init_dyld_symbols(void(*visit)(void* context, const char* symbol, void** storage), void *context)
{
	visit(context, "_mach_task_self_", (void**)&roothider_inline_mach_task_self_pointer);

#define VISIT_INLINE_SYMBOL_ALIAS(to, alias, min, max) \
	if (roothider_inline_version >= (min) && (!(max) || roothider_inline_version <= (max))) { \
		visit(context, "_" #to, (void**)&roothider_inline_##alias); \
	}
#define VISIT_INLINE_SYMBOL(to, min, max) VISIT_INLINE_SYMBOL_ALIAS(to, to, min, max)
	DYLD_TRAMPOLINE_SYMBOLS(VISIT_INLINE_SYMBOL, VISIT_INLINE_SYMBOL_ALIAS)

#undef VISIT_INLINE_SYMBOL
#undef VISIT_INLINE_SYMBOL_ALIAS
}

// ---- Inline mach traps / syscalls ----
DEF_SYSCALL(__sandbox_ms, 381);

// ---- Memory functions ----
static void inline_bzero(void *dst, unsigned long n) {
	char *d = dst;
	while (n--) *d++ = 0;
}
static void *inline_memcpy(void *dst, const void *src, unsigned long n) {
	char *d = dst; const char *s = src;
	while (n--) *d++ = *s++;
	return dst;
}

// ---- String functions ----
static int inline_strcmp(const char *a, const char *b) {
	while (*a && *a == *b) { a++; b++; }
	return *(unsigned char *)a - *(unsigned char *)b;
}
static unsigned long inline_strlen(const char *s) {
	unsigned long n = 0;
	while (*s++) n++;
	return n;
}
static unsigned long inline_strlcpy(char *dst, const char *src, unsigned long size) {
	unsigned long len = inline_strlen(src);
	if (size > 0) {
		unsigned long n = len < size - 1 ? len : size - 1;
		inline_memcpy(dst, src, n);
		dst[n] = '\0';
	}
	return len;
}

// ---- Trampoline redirects ----
#define strcmp               inline_strcmp
#define strlen               inline_strlen
#define strlcpy              inline_strlcpy

// ============================================================
// IOS=15: reimpl.c + task.c
// ============================================================
#define IOS 15
#define NDR_record                NDR_record_ios15
#define NDR_record_t              NDR_record_t_ios15
#define msyscall_errno            msyscall_errno_ios15
#define sandbox_extension_consume sandbox_extension_consume_ios15
typedef struct NDR_record_t_ios15 NDR_record_t_ios15;
#include "../dyldhook/src/reimpl.c"
#undef NDR_record
#define NDR_record             (*(NDR_record_t*)&NDR_record_ios15)
#define task_get_special_port  task_get_special_port_ios15
#define mach_ports_lookup      mach_ports_lookup_ios15
#include "../dyldhook/src/generated/ios15/task.c"
#undef __MachMsgErrorWithoutTimeout
#undef __DeclareSendRpc
#undef __BeforeSendRpc
#undef __AfterSendRpc
#undef sandbox_extension_consume
#undef task_get_special_port
#undef mach_ports_lookup
#undef msgh_request_port
#undef msgh_reply_port
#undef msyscall_errno
#undef NDR_record
#undef NDR_record_t
#undef IOS

// ============================================================
// IOS=16: reimpl.c + mach_msg2 wrapper + task.c
// ============================================================
#define IOS 16
#define NDR_record                NDR_record_ios16
#define NDR_record_t              NDR_record_t_ios16
#define msyscall_errno            msyscall_errno_ios16
#define sandbox_extension_consume sandbox_extension_consume_ios16
#define mach_msg_option64_t       mach_msg_option64_t_ios16
#define mach_msg_vector_t         mach_msg_vector_t_ios16
#define mach_msg2                 mach_msg2_ios16
#undef mach_msg
#define mach_msg                  mach_msg_ios16
typedef struct NDR_record_t_ios16 NDR_record_t_ios16;
#include "../dyldhook/src/reimpl.c"
// mach_msg2 wrapper (bridges enum/typedef gap for task.c)
#undef mach_msg
#undef mach_msg2
#undef mach_msg_vector_t
#undef mach_msg_option64_t
static inline mach_msg_return_t inline_mach_msg2_ios16(void *data, uint64_t option64, mach_msg_header_t header, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_t rcv_name, uint64_t timeout, uint32_t priority) {
	return mach_msg2_ios16(data, (mach_msg_option64_t_ios16)option64, header, send_size, rcv_size, rcv_name, timeout, priority);
}
// task.c ios16-17: mach_msg via mach_msg2
#undef NDR_record
#define NDR_record             (*(NDR_record_t*)&NDR_record_ios16)
#define mach_msg_option64_t    uint64_t
#define mach_msg2              inline_mach_msg2_ios16
#define mig_mach_msg           mig_mach_msg_ios16
#define task_get_special_port  task_get_special_port_ios16
#define mach_ports_lookup      mach_ports_lookup_ios16
#include "../dyldhook/src/generated/ios16-17/task.c"
#undef __MachMsgErrorWithoutTimeout
#undef __DeclareSendRpc
#undef __BeforeSendRpc
#undef __AfterSendRpc
#undef MACH64_SEND_KOBJECT_CALL
#undef sandbox_extension_consume
#undef task_get_special_port
#undef mach_ports_lookup
#undef msgh_request_port
#undef msgh_reply_port
#undef msyscall_errno
#undef NDR_record
#undef NDR_record_t
#undef mig_mach_msg
#undef mach_msg
#undef mach_msg2
#undef mach_msg_option64_t
#undef IOS

// ============================================================
// IOS=18: reimpl.c + mach_msg2 wrapper + task.c
// ============================================================
#undef __options_decl
#define __options_decl(name, type, ...) typedef type name;
#define IOS 18
#define NDR_record                NDR_record_ios18
#define NDR_record_t              NDR_record_t_ios18
#define msyscall_errno            msyscall_errno_ios18
#define sandbox_extension_consume sandbox_extension_consume_ios18
#define mach_msg_option64_t       mach_msg_option64_t_ios18
#define mach_msg_vector_t         mach_msg_vector_t_ios18
#define mach_msg2                 mach_msg2_ios18
#define mach_msg                  mach_msg_ios18
#define mach_ports_lookup         mach_ports_lookup_ios18
#define _kernelrpc_mach_ports_lookup3 _kernelrpc_mach_ports_lookup3_ios18
typedef struct NDR_record_t_ios18 NDR_record_t_ios18;
#include "../dyldhook/src/reimpl.c"
// mach_msg2 wrapper
#undef _kernelrpc_mach_ports_lookup3
#undef mach_ports_lookup
#undef mach_msg
#undef mach_msg2
#undef mach_msg_vector_t
#undef mach_msg_option64_t
static inline mach_msg_return_t inline_mach_msg2_ios18(void *data, uint64_t option64, mach_msg_header_t header, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_t rcv_name, uint64_t timeout, uint32_t priority) {
	return mach_msg2_ios18(data, (mach_msg_option64_t_ios18)option64, header, send_size, rcv_size, rcv_name, timeout, priority);
}
// task.c ios18+: mach_msg via mach_msg2
#undef NDR_record
#define NDR_record             (*(NDR_record_t*)&NDR_record_ios18)
#define mach_msg_option64_t    uint64_t
#define mach_msg2              inline_mach_msg2_ios18
#define mig_mach_msg           mig_mach_msg_ios18
#define task_get_special_port  task_get_special_port_ios18
#define _kernelrpc_mach_ports_lookup3 _kernelrpc_mach_ports_lookup3_ios18
#include "../dyldhook/src/generated/ios18+/task.c"
#undef __MachMsgErrorWithoutTimeout
#undef __DeclareSendRpc
#undef __BeforeSendRpc
#undef __AfterSendRpc
#undef MACH64_SEND_KOBJECT_CALL
#undef _kernelrpc_mach_ports_lookup3
#undef sandbox_extension_consume
#undef task_get_special_port
#undef mach_ports_lookup
#undef msgh_request_port
#undef msgh_reply_port
#undef msyscall_errno
#undef NDR_record
#undef NDR_record_t
#undef mig_mach_msg
#undef mach_msg
#undef mach_msg2
#undef mach_msg_option64_t
#undef IOS

// ============================================================
// Runtime dispatch wrappers
// ============================================================
static kern_return_t reimpl_task_get_special_port(task_inspect_t task, int which_port, mach_port_t *special_port) {
	if (roothider_inline_version >= 18)
		return task_get_special_port_ios18(task, which_port, special_port);
	if (roothider_inline_version >= 16)
		return task_get_special_port_ios16(task, which_port, special_port);
	return task_get_special_port_ios15(task, which_port, special_port);
}

static kern_return_t reimpl_mach_ports_lookup(task_t task, mach_port_array_t *ports, mach_msg_type_number_t *count) {
	if (roothider_inline_version >= 18)
		return mach_ports_lookup_ios18(task, ports, count);
	if (roothider_inline_version >= 16)
		return mach_ports_lookup_ios16(task, ports, count);
	return mach_ports_lookup_ios15(task, ports, count);
}

static mach_msg_return_t reimpl_mach_msg(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify) {
	if (roothider_inline_version >= 18)
		return mach_msg_ios18(msg, option, send_size, rcv_size, rcv_name, timeout, notify);
	if (roothider_inline_version >= 16)
		return mach_msg_ios16(msg, option, send_size, rcv_size, rcv_name, timeout, notify);
	return mach_msg(msg, option, send_size, rcv_size, rcv_name, timeout, notify);
}

// ============================================================
// Redirects for jbclient_mach.c
// ============================================================
#define bzero(d, n)                     inline_bzero(d, n)
#define memcpy(d, s, n)                 inline_memcpy(d, s, n)
#define mach_msg                        reimpl_mach_msg
#define mach_ports_lookup               reimpl_mach_ports_lookup
#define task_get_special_port           reimpl_task_get_special_port
#define jbclient_mach_send_msg          inline_jbclient_mach_send_msg
#define jbclient_mach_fork_fix          inline_jbclient_mach_fork_fix
#define jbclient_mach_trust_file        inline_jbclient_mach_trust_file
#define jbclient_mach_hookd_send_msg    inline_jbclient_mach_hookd_send_msg
#define jbclient_mach_process_checkin   inline_jbclient_mach_process_checkin
#define jbclient_mach_get_launchd_port  inline_jbclient_mach_get_launchd_port

#include "../libjailbreak/src/jbclient_mach.c"
