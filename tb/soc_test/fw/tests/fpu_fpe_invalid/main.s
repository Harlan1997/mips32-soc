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
    /* FCSR Enable[invalid] is bit 11. */
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x0800
    ctc1    $t0, $31
    nop
    nop
    mtc1    $zero, $f0
    mtc1    $zero, $f2
    div.s   $f4, $f0, $f2
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
    addiu   $t0, $zero, 16
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
    ori     $k1, $k1, 0x0007
    sw      $k1, 0($k0)
2:  b       2b
    nop
