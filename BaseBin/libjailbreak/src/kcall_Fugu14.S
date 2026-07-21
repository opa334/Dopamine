.global _pac_loop
_pac_loop:
    mov x0, #1
    adrp x1, _gUserReturnDidHappen@PAGE
    str x0, [x1, _gUserReturnDidHappen@PAGEOFF]
    b _pac_loop