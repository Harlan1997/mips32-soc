    .set noreorder
    .set noat

    .macro check_addsub_round mnemonic, mode, expected_hi, expected_lo, expected_fcsr, failcode
    addiu   $t0, $zero, \mode
    ctc1    $t0, $31
    nop
    nop
    \mnemonic $f4, $f0, $f2
    nop
    nop
    nop
    mfc1    $t1, $f4
    lui     $t2, \expected_hi
    ori     $t2, $t2, \expected_lo
    addiu   $t7, $zero, \failcode
    bne     $t1, $t2, fail_addsub
    nop
    cfc1    $t1, $31
    andi    $t1, $t1, 0x7c
    addiu   $t2, $zero, \expected_fcsr
    bne     $t1, $t2, fail_addsub
    nop
    .endm

    .macro check_madd_round mode, expected_hi, expected_lo, expected_fcsr, failcode
    addiu   $t3, $zero, 1
    mtc1    $t3, $f2
    addiu   $t0, $zero, \mode
    ctc1    $t0, $31
    nop
    nop
    .word   0x4c4400a0       /* MADD.S $f2,$f0,$f4,$f2 */
    nop
    nop
    nop
    mfc1    $t1, $f2
    lui     $t2, \expected_hi
    ori     $t2, $t2, \expected_lo
    addiu   $t7, $zero, \failcode
    bne     $t1, $t2, fail_addsub
    nop
    cfc1    $t1, $31
    andi    $t1, $t1, 0x7c
    addiu   $t2, $zero, \expected_fcsr
    bne     $t1, $t2, fail_addsub
    nop
    .endm

    /* Unary reciprocal operations use the fixed encodings supported by the
     * firmware assembler.  The real CPU path must observe the same directed
     * single-destination rounding and sticky Inexact flag as the primitive
     * FPU gate. */
    .macro check_unary_round encoding, mode, expected_hi, expected_lo, expected_fcsr, failcode
    addiu   $t0, $zero, \mode
    ctc1    $t0, $31
    nop
    nop
    .word   \encoding
    nop
    nop
    nop
    mfc1    $t1, $f2
    lui     $t2, \expected_hi
    ori     $t2, $t2, \expected_lo
    addiu   $t7, $zero, \failcode
    bne     $t1, $t2, fail_addsub
    nop
    cfc1    $t1, $31
    andi    $t1, $t1, 0x7c
    addiu   $t2, $zero, \expected_fcsr
    bne     $t1, $t2, fail_addsub
    nop
    .endm

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
    j       single_addsub_rounding
    nop
    .section .text, "ax"
single_addsub_rounding:
    /* Exact binary32 rounding must retain min-subnormal operands next to 1.0. */
    lui     $t0, 0x3f80
    mtc1    $t0, $f0
    addiu   $t0, $zero, 1
    mtc1    $t0, $f2
    nop
    nop
    nop
    check_addsub_round add.s, 0, 0x3f80, 0x0000, 0x04, 15
    check_addsub_round add.s, 1, 0x3f80, 0x0000, 0x04, 16
    check_addsub_round add.s, 2, 0x3f80, 0x0001, 0x04, 17
    check_addsub_round add.s, 3, 0x3f80, 0x0000, 0x04, 18

    check_addsub_round sub.s, 0, 0x3f80, 0x0000, 0x04, 19
    check_addsub_round sub.s, 1, 0x3f7f, 0xffff, 0x04, 20
    check_addsub_round sub.s, 2, 0x3f80, 0x0000, 0x04, 21
    check_addsub_round sub.s, 3, 0x3f7f, 0xffff, 0x04, 22

    /* Negative subtraction checks sign-aware directed rounding and RHS flip. */
    lui     $t0, 0xbf80
    mtc1    $t0, $f0
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x0001
    mtc1    $t0, $f2
    nop
    nop
    nop
    check_addsub_round sub.s, 0, 0xbf80, 0x0000, 0x04, 23
    check_addsub_round sub.s, 1, 0xbf7f, 0xffff, 0x04, 24
    check_addsub_round sub.s, 2, 0xbf7f, 0xffff, 0x04, 25
    check_addsub_round sub.s, 3, 0xbf80, 0x0000, 0x04, 26

    /* Overflow remains visible when directed rounding returns max-finite. */
    lui     $t0, 0x7f7f
    ori     $t0, $t0, 0xffff
    mtc1    $t0, $f0
    mtc1    $t0, $f2
    nop
    nop
    nop
    check_addsub_round add.s, 0, 0x7f80, 0x0000, 0x14, 27
    check_addsub_round add.s, 1, 0x7f7f, 0xffff, 0x14, 28
    check_addsub_round add.s, 2, 0x7f80, 0x0000, 0x14, 29
    check_addsub_round add.s, 3, 0x7f7f, 0xffff, 0x14, 30

    lui     $t0, 0xff7f
    ori     $t0, $t0, 0xffff
    mtc1    $t0, $f0
    mtc1    $t0, $f2
    nop
    nop
    nop
    check_addsub_round add.s, 0, 0xff80, 0x0000, 0x14, 31
    check_addsub_round add.s, 1, 0xff7f, 0xffff, 0x14, 32
    check_addsub_round add.s, 2, 0xff7f, 0xffff, 0x14, 33
    check_addsub_round add.s, 3, 0xff80, 0x0000, 0x14, 34

    /* MADD.S must preserve the minimum-subnormal accumulator at 1.0. */
    lui     $t0, 0x3f80
    mtc1    $t0, $f0
    mtc1    $t0, $f4
    addiu   $t0, $zero, 1
    mtc1    $t0, $f2
    nop
    nop
    nop
    check_madd_round 0, 0x3f80, 0x0000, 0x04, 35
    check_madd_round 1, 0x3f80, 0x0000, 0x04, 36
    check_madd_round 2, 0x3f80, 0x0001, 0x04, 37
    check_madd_round 3, 0x3f80, 0x0000, 0x04, 38

    /* RECIP.S: 1/3 lies between adjacent binary32 values. */
    lui     $t0, 0x4040              /* 3.0 */
    mtc1    $t0, $f0
    nop
    nop
    nop
    check_unary_round 0x46000095, 0, 0x3eaa, 0xaaab, 0x04, 39
    check_unary_round 0x46000095, 1, 0x3eaa, 0xaaaa, 0x04, 40
    check_unary_round 0x46000095, 2, 0x3eaa, 0xaaab, 0x04, 41
    check_unary_round 0x46000095, 3, 0x3eaa, 0xaaaa, 0x04, 42

    /* Signed RECIP.S: -1/3 exercises the reverse adjacent-ULP direction. */
    lui     $t0, 0xc040              /* -3.0 */
    mtc1    $t0, $f0
    nop
    nop
    nop
    check_unary_round 0x46000095, 0, 0xbeaa, 0xaaab, 0x04, 47
    check_unary_round 0x46000095, 1, 0xbeaa, 0xaaaa, 0x04, 48
    check_unary_round 0x46000095, 2, 0xbeaa, 0xaaaa, 0x04, 49
    check_unary_round 0x46000095, 3, 0xbeaa, 0xaaab, 0x04, 50

    /* RSQRT.S: 1/sqrt(2) has the same directed-rounding boundary. */
    lui     $t0, 0x4000              /* 2.0 */
    mtc1    $t0, $f0
    nop
    nop
    nop
    check_unary_round 0x46000096, 0, 0x3f35, 0x04f3, 0x04, 43
    check_unary_round 0x46000096, 1, 0x3f35, 0x04f3, 0x04, 44
    check_unary_round 0x46000096, 2, 0x3f35, 0x04f4, 0x04, 45
    check_unary_round 0x46000096, 3, 0x3f35, 0x04f3, 0x04, 46

    j       double_rounding
    nop
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

    /* Conversion range is checked after rounding.  +2^31-0.5 rounds to
     * 2^31 under nearest-even and is therefore Invalid, while toward-zero
     * remains the representable INT_MAX value. */
    lui     $t0, 0xffe0
    ori     $t0, $t0, 0x0000
    .word   0x44880000       /* low word -> f0 */
    lui     $t0, 0x41df
    ori     $t0, $t0, 0xffff
    .word   0x44880800       /* high word -> f1 */
    ctc1    $zero, $31
    nop
    nop
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    lui     $t2, 0x8000
    bne     $t1, $t2, fail15
    nop
    cfc1    $t1, $31
    andi    $t1, $t1, 0x7c
    addiu   $t2, $zero, 0x40
    bne     $t1, $t2, fail16
    nop

    addiu   $t0, $zero, 1     /* RM=toward zero */
    ctc1    $t0, $31
    nop
    nop
    cvt.w.d $f4, $f0
    mfc1    $t1, $f4
    nop
    nop
    lui     $t2, 0x7fff
    ori     $t2, $t2, 0xffff
    bne     $t1, $t2, fail17
    nop
    cfc1    $t1, $31
    andi    $t1, $t1, 0x7c
    addiu   $t2, $zero, 0x04
    bne     $t1, $t2, fail18
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
fail15:
    addiu   $t1, $zero, 15
    b       fail_emit
    nop
fail16:
    addiu   $t1, $zero, 16
    b       fail_emit
    nop
fail17:
    addiu   $t1, $zero, 17
    b       fail_emit
    nop
fail18:
    addiu   $t1, $zero, 18
    b       fail_emit
    nop
fail47:
    addiu   $t1, $zero, 47
    b       fail_emit
    nop
fail48:
    addiu   $t1, $zero, 48
    b       fail_emit
    nop
fail49:
    addiu   $t1, $zero, 49
    b       fail_emit
    nop
fail50:
    addiu   $t1, $zero, 50
    b       fail_emit
    nop
fail_addsub:
    addu    $t1, $t7, $zero
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
