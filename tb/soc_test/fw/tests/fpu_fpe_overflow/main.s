    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    lui     $t0, 0x3000
    mtc0    $t0, $12
    nop
    nop
    nop
    /* FCSR Enable[overflow] is bit 9. */
    ori     $t0, $zero, 0x0200
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0x7f7f          /* largest finite single: 0x7f7fffff */
    ori     $t0, $t0, 0xffff
    mtc1    $t0, $f0
    lui     $t0, 0x4000          /* 2.0 */
    mtc1    $t0, $f2
    .word   0x46020102           /* MUL.S $f4,$f0,$f2 */
    nop
    b       fail
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    mfc0    $k0, $13
    nop
    nop
    nop
    srl     $k0, $k0, 2
    andi    $k0, $k0, 0x1f
    addiu   $k1, $zero, 15
    bne     $k0, $k1, fail
    nop
    cfc1    $k0, $31
    nop
    nop
    srl     $k1, $k0, 12
    andi    $k1, $k1, 0x1f
    addiu   $t0, $zero, 4
    bne     $k1, $t0, fail
    nop
    srl     $k1, $k0, 2
    andi    $k1, $k1, 0x1f
    bne     $k1, $t0, fail
    nop
    mfc1    $k0, $f4
    nop
    nop
    bne     $k0, $zero, fail
    nop
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
1:  b       1b
    nop

fail:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0008
    sw      $k1, 0($k0)
2:  b       2b
    nop
