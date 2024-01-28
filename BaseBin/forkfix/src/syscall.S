.text

.align 4

.global _ffsys_fork
_ffsys_fork:
#ifdef __arm64e__
	pacibsp
#endif
	stp x29, x30, [SP, #-0x10]!
	mov x29, sp
	mov x16, #2
	svc 0x80
	b.cs _ffsys_fork_err
	cbz x1, _ffsys_fork_end
	mov w0, #0
	adrp x9, __current_pid@GOTPAGE
	ldr x9, [x9, __current_pid@GOTPAGEOFF]
	str w0, [x9]
	b _ffsys_fork_end

_ffsys_fork_err:
	bl _cerror
	mov w0, #-1

_ffsys_fork_end:
	mov sp, x29
	ldp x29, x30, [SP],#0x10
#ifdef __arm64e__
	retab
#else
    ret
#endif

.global _ffsys_vm_protect
_ffsys_vm_protect:
	mov x16, #-14
	svc 0x80
	ret

.global _ffsys_getpid
_ffsys_getpid:
	mov x16, #20
	svc 0x80
	ret

.global _ffsys_pid_suspend
_ffsys_pid_suspend:
	mov x16, #433
	svc 0x80
	ret

.global _ffsys_read
_ffsys_read:
	mov x16, #3
	svc 0x80
	ret

.global _ffsys_write
_ffsys_write:
	mov x16, #4
	svc 0x80
	ret

.global _ffsys_close
_ffsys_close:
	mov x16, #6
	svc 0x80
	ret
