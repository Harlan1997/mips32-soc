    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    /* Enable CU1 and only FCSR Inexact[7]. */
    lui     $t0, 0x3000
    mtc0    $t0, $12
    nop
    nop
    nop
    ori     $t0, $zero, 0x0080
    ctc1    $t0, $31
    nop
    nop

    /* 1.5 = 0x3ff8000000000000, held as f1:f0. */
    mtc1    $zero, $f0
    lui     $t0, 0x3ff8
    .word   0x44880800       /* mtc1 $t0,$f1: 1.5 high word */
    cvt.w.d $f4, $f0
    nop
    b       fail_main
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
    /* Cause[16:12] and Flags[6:2] must both contain Inexact index 0. */
    srl     $k1, $k0, 12
    andi    $k1, $k1, 0x1f
    addiu   $t0, $zero, 1
    bne     $k1, $t0, fail_cause
    nop
    srl     $k1, $k0, 2
    andi    $k1, $k1, 0x1f
    bne     $k1, $t0, fail_flags
    nop

    /* Precise FPE: neither word of the trapped pair may commit. */
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

fail_main:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0001
    b       fail_emit
    nop
fail_cause:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0002
    b       fail_emit
    nop
fail_flags:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0003
    b       fail_emit
    nop
fail_fpr:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0004
fail_emit:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    sw      $k1, 0($k0)
2:  b       2b
    nop
