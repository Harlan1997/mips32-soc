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

    /* Minimum positive double subnormal times 0.5. */
    ori     $t0, $zero, 1
    mtc1    $t0, $f0
    .word   0x44800800       /* mtc1 $zero,$f1: zero high word */
    lui     $t0, 0x3fe0
    .word   0x44881800       /* mtc1 $t0,$f3: 0.5 high word */
    mtc1    $zero, $f2

    /* Enable only Underflow[8] after the operands are fully assembled. */
    ori     $t0, $zero, 0x0100
    ctc1    $t0, $31
    nop
    nop
    mul.d   $f4, $f0, $f2
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
    bne     $k0, $k1, fail_cause
    nop
    cfc1    $k0, $31
    nop
    nop
    /* Underflow index 1. */
    srl     $k1, $k0, 12
    andi    $k1, $k1, 0x1f
    addiu   $t0, $zero, 3
    bne     $k1, $t0, fail_cause
    nop
    srl     $k1, $k0, 2
    andi    $k1, $k1, 0x1f
    bne     $k1, $t0, fail_flags
    nop
    mfc1    $k0, $f4
    nop
    nop
    bne     $k0, $zero, fail_fpr
    nop
    .word   0x44092800       /* mfc1 $t1,$f5 */
    nop
    nop
    bne     $t1, $zero, fail_fpr
    nop
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
1:  b       1b
    nop

fail_cause:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 1
    b       fail_emit
    nop
fail_flags:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 2
    b       fail_emit
    nop
fail_fpr:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 3
fail:
fail_emit:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    sw      $k1, 0($k0)
2:  b       2b
    nop
