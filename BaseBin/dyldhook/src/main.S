#define MAKE_TRAMPOLINE_ALIAS(to, alias) .global _##alias %% .global _MACHOMERGER_TRAMPOLINE_##to## %% _##alias: %% _MACHOMERGER_TRAMPOLINE_##to##: %% b .
#define MAKE_TRAMPOLINE(to) MAKE_TRAMPOLINE_ALIAS(to, to)

#define SYSCALL_PROLOGUE stp x0, x1, [sp, -16]! %% stp x2, x3, [sp, -16]! %% stp x4, x5, [sp, -16]! %% stp x6, x7, [sp, -16]!
#define SYSCALL_EPILOGUE ldp x6, x7, [sp], 16 %% ldp x4, x5, [sp], 16 %% ldp x2, x3, [sp], 16 %% ldp x0, x1, [sp], 16

#define DEF_SYSCALL(name, num)  .global _##name %% _##name: %% SYSCALL_PROLOGUE %% mov x16, num %% svc #0x80 %% mov x16, x0 %% SYSCALL_EPILOGUE %% bcc name##_end %% cmp x16, #4 %% beq _##name %% mov x16, #-1 %% name##_end: %% mov x0, x16 %% ret
#define DEF_MACHTRAP(name, num) .global _##name %% _##name: %% mov x16, -num %% svc #0x80 %% ret
#define DEF_ALIAS(to, from) .global _##to %% _##to: %% b _##from

.text
.align 4

.global _MACHOMERGER_START_HOOK
_MACHOMERGER_START_HOOK:
    // Copy-Paste from dyld
    mov    x0, sp
    mov    x19, sp
    and    sp, x0, #~15 // force 16-byte alignment of stack
    mov    fp, #0

    // Call init
    bl _dyldhook_init

    // Restore stack
    mov sp, x19

    // Jump to real start
    b _MACHOMERGER_REAL_START

#if IOS==15 && __arm64e__

.global _MACHOMERGER_ORIG__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE
.global _MACHOMERGER_HOOKTRAMPOLINE__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE
_MACHOMERGER_ORIG__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE:
    nop // Will be replaced with the original first instruction by machomerger
    // FALLTHROUGH
_MACHOMERGER_HOOKTRAMPOLINE__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE:
    b . // Will be patched by machomerger

#endif

.global _MACHOMERGER_ORIG__ZN5dyld44APIs11dlopen_fromEPKciPv
.global _MACHOMERGER_HOOKTRAMPOLINE__ZN5dyld44APIs11dlopen_fromEPKciPv
_MACHOMERGER_ORIG__ZN5dyld44APIs11dlopen_fromEPKciPv:
    nop // Will be replaced with the original first instruction by machomerger
    // FALLTHROUGH
_MACHOMERGER_HOOKTRAMPOLINE__ZN5dyld44APIs11dlopen_fromEPKciPv:
    b .

MAKE_TRAMPOLINE(MACHOMERGER_REAL_START)
MAKE_TRAMPOLINE(cerror)
MAKE_TRAMPOLINE_ALIAS(__getpid, getpid)
MAKE_TRAMPOLINE_ALIAS(__bzero, bzero)
MAKE_TRAMPOLINE(mach_msg_destroy)
MAKE_TRAMPOLINE(mach_reply_port)
MAKE_TRAMPOLINE(mach_port_construct)
MAKE_TRAMPOLINE(mach_port_deallocate)
MAKE_TRAMPOLINE(memset)
MAKE_TRAMPOLINE(task_self_trap)
MAKE_TRAMPOLINE(__stack_chk_fail)
MAKE_TRAMPOLINE_ALIAS(_kernelrpc_mach_vm_allocate_trap, vm_allocate)
MAKE_TRAMPOLINE_ALIAS(_kernelrpc_mach_vm_deallocate_trap, vm_deallocate)
MAKE_TRAMPOLINE(vm_protect)
MAKE_TRAMPOLINE(memcpy)
MAKE_TRAMPOLINE(strcmp)
MAKE_TRAMPOLINE(strncmp)
MAKE_TRAMPOLINE(strlen)
MAKE_TRAMPOLINE(strstr)
MAKE_TRAMPOLINE(strcpy)
MAKE_TRAMPOLINE(strcat)
MAKE_TRAMPOLINE(close)
MAKE_TRAMPOLINE(open)
MAKE_TRAMPOLINE(fcntl)
MAKE_TRAMPOLINE(mmap)
MAKE_TRAMPOLINE(_simple_getenv)
MAKE_TRAMPOLINE_ALIAS(mig_get_reply_port, dyld_mig_get_reply_port)

#if IOS>=16
MAKE_TRAMPOLINE(mach_msg_overwrite)
MAKE_TRAMPOLINE(mach_msg2_internal)
#else
MAKE_TRAMPOLINE(mach_msg)
#endif

DEF_SYSCALL(read, 3)
DEF_SYSCALL(access, 33)
DEF_SYSCALL(lseek, 199)
DEF_SYSCALL(__sandbox_ms, 381)
DEF_SYSCALL(fileport_makeport, 430)

.data
.global ___stack_chk_guard
___stack_chk_guard:
    .quad 0x1337