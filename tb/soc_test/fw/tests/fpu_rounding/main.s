    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    /* Enable CP0 and the opt-in COP1 unit. */
    lui     $t0, 0x3000
    mtc0    $t0, $12
    nop
    nop
    nop

    /* RM=nearest-even: 1.5 -> 2 and 2.5 -> 2 (tie is even). */
    mtc1    $zero, $f0
    lui     $t0, 0x3fc0
    mtc1    $t0, $f0
    mtc1    $zero, $f2
    ctc1    $zero, $31
    nop
    nop
    cvt.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 2
    bne     $t1, $t2, fail1
    nop

    lui     $t0, 0x4020
    mtc1    $t0, $f0
    cvt.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    bne     $t1, $t2, fail2
    nop

    /* RM=toward-zero: -1.75 -> -1. */
    addiu   $t0, $zero, 1
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0xbfe0
    mtc1    $t0, $f0
    cvt.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -1
    bne     $t1, $t2, fail3
    nop

    /* RM=toward +infinity: +1.25 -> 2. */
    addiu   $t0, $zero, 2
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0x3fa0
    mtc1    $t0, $f0
    cvt.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 2
    bne     $t1, $t2, fail4
    nop

    /* RM=toward -infinity: -1.25 -> -2. */
    addiu   $t0, $zero, 3
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0xbfa0
    mtc1    $t0, $f0
    cvt.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -2
    bne     $t1, $t2, fail5
    nop

    /* Fixed ROUND.W.S remains nearest-even regardless of FCSR.RM=RM. */
    lui     $t0, 0x3fc0
    mtc1    $t0, $f0
    round.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 2
    bne     $t1, $t2, fail6
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
1:  b       1b
    nop

    .section .text, "ax"
fail1:
    addiu   $t1, $zero, 1
    b       fail_emit
    nop
fail2:
    addiu   $t1, $zero, 2
    b       fail_emit
    nop
fail3:
    addiu   $t1, $zero, 3
    b       fail_emit
    nop
fail4:
    addiu   $t1, $zero, 4
    b       fail_emit
    nop
fail5:
    addiu   $t1, $zero, 5
    b       fail_emit
    nop
fail6:
    addiu   $t1, $zero, 6
    b       fail_emit
    nop
fail:
    addiu   $t1, $zero, 7
fail_emit:
    lui     $t2, 0xa000
    ori     $t2, $t2, 0xfffc
    lui     $t0, 0xdeaf
    or      $t1, $t1, $t0
    sw      $t1, 0($t2)
2:  b       2b
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    b       fail
    nop
