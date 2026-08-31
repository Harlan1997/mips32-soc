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

    /* Fixed ROUND.W.S is ties-away-from-zero, regardless of FCSR.RM. */
    lui     $t0, 0x4020       /* +2.5 -> +3, unlike CVT.W.S nearest-even */
    mtc1    $t0, $f0
    round.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 3
    bne     $t1, $t2, fail6
    nop

    lui     $t0, 0xbfc0       /* -1.5 -> -2 */
    mtc1    $t0, $f0
    round.w.s $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -2
    bne     $t1, $t2, fail7
    nop

    /* Keep the fixed exception vector at 0x180 clear of the larger double
     * corpus; continue the test from the normal text section. */
    j       double_rounding
    nop
    .section .text, "ax"
double_rounding:
    /* Double precision uses the same FCSR.RM contract.  f0/f1 are the
     * little-endian low/high words of each value. */
    mtc1    $zero, $f0
    lui     $t0, 0x3ff8       /* +1.5D */
    .word   0x44880800        /* mtc1 $t0,$f1 */
    ctc1    $zero, $31
    nop
    nop
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 2
    bne     $t1, $t2, fail8
    nop

    lui     $t0, 0x4004       /* +2.5D, nearest-even -> 2 */
    .word   0x44880800
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    bne     $t1, $t2, fail9
    nop

    addiu   $t0, $zero, 1     /* toward zero: -1.75D -> -1 */
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0xbffc
    .word   0x44880800
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -1
    bne     $t1, $t2, fail10
    nop

    addiu   $t0, $zero, 2     /* toward +inf: +1.25D -> 2 */
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0x3ff4
    .word   0x44880800
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 2
    bne     $t1, $t2, fail11
    nop

    addiu   $t0, $zero, 3     /* toward -inf: -1.25D -> -2 */
    ctc1    $t0, $31
    nop
    nop
    lui     $t0, 0xbff4
    .word   0x44880800
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -2
    bne     $t1, $t2, fail12
    nop

    /* Fixed ROUND.W.D remains ties-away regardless of RM. */
    lui     $t0, 0x4004       /* +2.5D -> +3 */
    .word   0x44880800
    round.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, 3
    bne     $t1, $t2, fail13
    nop

    lui     $t0, 0xbff8       /* -1.5D -> -2 */
    .word   0x44880800
    round.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    addiu   $t2, $zero, -2
    bne     $t1, $t2, fail14
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
fail7:
    addiu   $t1, $zero, 7
    b       fail_emit
    nop
fail8:
    addiu   $t1, $zero, 8
    b       fail_emit
    nop
fail9:
    addiu   $t1, $zero, 9
    b       fail_emit
    nop
fail10:
    addiu   $t1, $zero, 10
    b       fail_emit
    nop
fail11:
    addiu   $t1, $zero, 11
    b       fail_emit
    nop
fail12:
    addiu   $t1, $zero, 12
    b       fail_emit
    nop
fail13:
    addiu   $t1, $zero, 13
    b       fail_emit
    nop
fail14:
    addiu   $t1, $zero, 14
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
