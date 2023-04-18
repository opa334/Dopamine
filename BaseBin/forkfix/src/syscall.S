.text

.align 4

.global _ffsys_fork
_ffsys_fork:
	pacibsp
	stp x29, x30, [SP, #-0x10]!
	mov x29, sp
	mov x16, #2
	svc 0x80
	b.cs _ffsys_fork_err
	cbz x1, _ffsys_fork_end
	mov w0, #0
	adrp x9, __current_pid@PAGE
	add x9, x9, __current_pid@PAGEOFF
	mov w0, #0
	str w0, [x9]
	b _ffsys_fork_end

_ffsys_fork_err:
	bl _cerror
	mov w0, #-1

_ffsys_fork_end:
	mov sp, x29
	ldp x29, x30, [SP],#0x10
	retab

.global _ffsys_vm_protect
_ffsys_vm_protect:
	mov x16, #-14
	svc 0x80
	ret

.global _ffsys_kill
_ffsys_kill:
	mov x16, #37
	svc 0x80
	ret

.global _ffsys_getpid
_ffsys_getpid:
	mov x16, #20
	svc 0x80
	ret
