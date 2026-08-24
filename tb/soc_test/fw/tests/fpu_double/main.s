    .set noreorder
    .text
    .globl main
main:
    lui     $t0, 0x4000
    addiu   $t1, $zero, 'D'
    sw      $t1, 0($t0)
    mfc0    $t8, $12
    lui     $t9, 0x2000
    or      $t8, $t8, $t9
    mtc0    $t8, $12
    nop
    nop
    nop

    /* f0/f1 = 1.5, f2/f3 = 2.25, f4/f5 = -2.25. */
    mtc1    $zero, $f0
    lui     $t0, 0x3ff8
    ori     $t0, $t0, 0
    .word   0x44880800       /* mtc1 $t0,$f1 */
    mtc1    $zero, $f2
    lui     $t0, 0x4002
    ori     $t0, $t0, 0
    .word   0x44881800       /* mtc1 $t0,$f3 */
    mtc1    $zero, $f4
    lui     $t0, 0xc002
    ori     $t0, $t0, 0
    .word   0x44882800       /* mtc1 $t0,$f5 */

    /* Check high words for representative ADD/SUB/MUL/DIV results. */
    add.d   $f8, $f0, $f2
    mfc1    $t2, $f8
    bne     $t2, $zero, fail
    nop
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0x400e
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop

    /* D-format conditional moves use even FPR pairs and the integer rt
     * condition.  Check both write and no-write cases through the high word. */
    addiu   $t5, $zero, 0
    movz.d  $f12, $f0, $t5
    .word   0x440b6800       /* mfc1 $t3,$f13 */
    lui     $t4, 0x3ff8
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop
    addiu   $t5, $zero, 1
    mtc1    $zero, $f12
    lui     $t0, 0xc002
    ori     $t0, $t0, 0
    .word   0x44886800       /* mtc1 $t0,$f13 */
    movz.d  $f12, $f0, $t5
    .word   0x440b6800       /* mfc1 $t3,$f13 */
    bne     $t3, $t0, fail
    nop
    movn.d  $f12, $f0, $t5
    .word   0x440b6800       /* mfc1 $t3,$f13 */
    lui     $t4, 0x3ff8
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop

    sub.d   $f8, $f2, $f0
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0x3fe8
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop

    mul.d   $f8, $f0, $f2
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0x400b
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop

    div.d   $f8, $f2, $f0
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0x3ff8
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop

    abs.d   $f8, $f4
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0x4002
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop
    neg.d   $f8, $f2
    .word   0x440b4800       /* mfc1 $t3,$f9 */
    lui     $t4, 0xc002
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail
    nop
    mov.d   $f10, $f8
    .word   0x440b5800       /* mfc1 $t3,$f11 */
    bne     $t3, $t4, fail
    nop

    /* Double/single/word conversion slice. */
    cvt.s.d $f6, $f0          /* 1.5D -> 1.5S */
    mfc1    $t2, $f6
    lui     $t4, 0x3fc0
    ori     $t4, $t4, 0
    bne     $t2, $t4, fail_conv
    nop
    cvt.d.s $f8, $f6          /* 1.5S -> 1.5D */
    .word   0x440b4800        /* mfc1 $t3,$f9 */
    lui     $t4, 0x3ff8
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    addiu   $t0, $zero, 3
    mtc1    $t0, $f12
    cvt.d.w $f14, $f12         /* 3W -> 3.0D */
    .word   0x440b7800        /* mfc1 $t3,$f15 */
    lui     $t4, 0x4008
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    cvt.w.d $f16, $f2          /* 2.25D -> 2W */
    mfc1    $t2, $f16
    addiu   $t4, $zero, 2
    bne     $t2, $t4, fail_conv
    nop

    /* Fused arithmetic uses fd as the accumulator: 2*3 +/- 1. */
    mtc1    $zero, $f0
    lui     $t0, 0x4000
    ori     $t0, $t0, 0
    .word   0x44880800               /* mtc1 $t0,$f1: 2.0D */
    mtc1    $zero, $f4
    lui     $t0, 0x4008
    ori     $t0, $t0, 0
    .word   0x44882800               /* mtc1 $t0,$f5: 3.0D */
    mtc1    $zero, $f2
    lui     $t0, 0x3ff0
    ori     $t0, $t0, 0
    .word   0x44881800               /* mtc1 $t0,$f3: 1.0D */
    .word   0x4c4400a1               /* madd.d = 7.0D */
    .word   0x440b1800
    lui     $t4, 0x401c
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    mtc1    $zero, $f2
    lui     $t0, 0x3ff0
    ori     $t0, $t0, 0
    .word   0x44881800
    .word   0x4c4400a9               /* msub.d = 5.0D */
    .word   0x440b1800
    lui     $t4, 0x4014
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    mtc1    $zero, $f2
    lui     $t0, 0x3ff0
    ori     $t0, $t0, 0
    .word   0x44881800
    .word   0x4c4400b1               /* nmadd.d = -7.0D */
    .word   0x440b1800
    lui     $t4, 0xc01c
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    mtc1    $zero, $f2
    lui     $t0, 0x3ff0
    ori     $t0, $t0, 0
    .word   0x44881800
    .word   0x4c4400b9               /* nmsub.d = -5.0D */
    .word   0x440b1800
    lui     $t4, 0xc014
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop

    /* Reciprocal operations on an even register pair. */
    mtc1    $zero, $f0
    lui     $t0, 0x4010              /* 4.0D high word */
    ori     $t0, $t0, 0
    .word   0x44880800               /* mtc1 $t0,$f1 */
    .word   0x46200095               /* recip.d $f2,$f0: 0.25D */
    .word   0x440b1800               /* mfc1 $t3,$f3 */
    lui     $t4, 0x3fd0
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop
    .word   0x46200096               /* rsqrt.d $f2,$f0: 0.5D */
    .word   0x440b1800               /* mfc1 $t3,$f3 */
    lui     $t4, 0x3fe0
    ori     $t4, $t4, 0
    bne     $t3, $t4, fail_conv
    nop

    /* 3.5D: nearest/toward-zero/+inf/-inf = 4/3/4/3. */
    mtc1    $zero, $f18
    lui     $t0, 0x400c
    ori     $t0, $t0, 0
    .word   0x44889800        /* mtc1 $t0,$f19 high word */
    round.w.d $f20, $f18
    trunc.w.d $f22, $f18
    ceil.w.d  $f24, $f18
    floor.w.d $f26, $f18
    mfc1    $t2, $f20
    addiu   $t4, $zero, 4
    bne     $t2, $t4, fail_conv
    nop
    mfc1    $t2, $f22
    addiu   $t4, $zero, 3
    bne     $t2, $t4, fail_conv
    nop
    mfc1    $t2, $f24
    addiu   $t4, $zero, 4
    bne     $t2, $t4, fail_conv
    nop
    mfc1    $t2, $f26
    addiu   $t4, $zero, 3
    bne     $t2, $t4, fail_conv
    nop

    /* FCSR sticky flags: 1.5/0.0 sets Divide-by-zero (bit 5),
     * and 0.0/0.0 sets Invalid (bit 6). */
    mtc1    $zero, $f12
    .word   0x44806800        /* mtc1 $zero,$f13 */
    div.d   $f8, $f0, $f12
    cfc1    $t6, $31
    andi    $t5, $t6, 0x20
    beq     $t5, $zero, fail
    nop
    div.d   $f8, $f12, $f12
    cfc1    $t6, $31
    andi    $t5, $t6, 0x40
    beq     $t5, $zero, fail
    nop

    cfc1    $t6, $31
    ctc1    $t6, $31
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xbeef
    sw      $t6, 0($t7)
1:  b       1b
    nop
fail_conv:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdeaf
    ori     $t6, $t6, 2
    sw      $t6, 0($t7)
3:  b       3b
    nop
fail:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xbad0
    ori     $t6, $t6, 2
    sw      $t6, 0($t7)
2:  b       2b
    nop
