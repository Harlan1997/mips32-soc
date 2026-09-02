    .set noreorder

    /* Check one C.* predicate through the real CPU FCSR/FPR path. */
    .macro  check_compare cond, expected
    lui     $t5, 0x0000
    ctc1    $t5, $31
    nop
    nop
    .word   (0x46020030 + \cond) /* C.cond.S $f0,$f2,cc=0 */
    nop
    nop
    nop
    cfc1    $t6, $31
    srl     $t6, $t6, 23
    nop
    nop
    nop
    andi    $t6, $t6, 1
    nop
    nop
    nop
    addiu   $t7, $zero, \expected
    bne     $t6, $t7, fail
    nop
    .endm

    .text
    .globl main
main:
    /* COP1 is usable only after the architectural CU1 enable is set. */
    mfc0    $t8, $12
    lui     $t9, 0x2000
    or      $t8, $t8, $t9
    mtc0    $t8, $12
    nop
    nop
    nop

    /* COP1 conditional moves use FCSR condition code 0 (FCSR[23]). */
    lui     $t0, 0x1111
    ori     $t0, $t0, 0x1111
    lui     $t1, 0x2222
    ori     $t1, $t1, 0x2222
    addu    $t2, $zero, $zero
    addu    $t3, $zero, $zero
    addu    $t4, $zero, $zero
    .word   0x01005001       /* movf $t2,$t0,cc=0: condition false */
    .word   0x01215801       /* movt $t3,$t1,cc=0: condition false */
    bne     $t2, $t0, fail
    nop
    bne     $t3, $zero, fail
    nop
    lui     $t5, 0x0080       /* FCSR[23] = 1 */
    ctc1    $t5, $31
    nop
    nop
    .word   0x01215801       /* movt $t3,$t1,cc=0: condition true */
    .word   0x01006001       /* movf $t4,$t0,cc=0: condition true */
    bne     $t3, $t1, fail
    nop
    bne     $t4, $zero, fail
    nop

    /* Non-zero FCC coverage: C.EQ.S writes FCC3 (FCSR[27]), and MOVT
     * consumes the same selector.  FCSR[24] remains reserved. */
    lui     $t5, 0x0000
    ctc1    $t5, $31
    nop
    nop
    .word   0x46020332       /* c.eq.s cc=3, $f0, $f2 */
    addu    $t3, $zero, $zero
    .word   0x012d5801       /* movt $t3,$t1,cc=3 (rt=cc<<2|tf) */
    bne     $t3, $t1, fail
    nop

    /* 1.0, 2.0, -2.0 and 4.0 as IEEE-754 bit patterns. */
    lui     $t0, 0x3f80
    ori     $t0, $t0, 0x0000
    lui     $t1, 0x4000
    ori     $t1, $t1, 0x0000
    lui     $t2, 0xc000
    ori     $t2, $t2, 0x0000
    lui     $t3, 0x4080
    ori     $t3, $t3, 0x0000
    mtc1    $t0, $f0
    mtc1    $t1, $f2
    mtc1    $t2, $f4
    mtc1    $t3, $f6

    /* MOV/ABS/NEG must preserve the architectural bit pattern for NaNs and
     * signed zero; host floating-point conversions are not a valid oracle. */
    lui     $t4, 0x8000
    mtc1    $t4, $f8
    nop
    nop
    nop
    mov.s   $f10, $f8
    nop
    nop
    nop
    mfc1    $t5, $f10
    bne     $t5, $t4, fail
    nop
    abs.s   $f10, $f8
    mfc1    $t5, $f10
    bne     $t5, $zero, fail
    nop
    neg.s   $f10, $f8
    mfc1    $t5, $f10
    bne     $t5, $zero, fail
    nop
    lui     $t4, 0x7fc1
    ori     $t4, $t4, 0x2345
    mtc1    $t4, $f8
    nop
    nop
    nop
    mov.s   $f10, $f8
    nop
    nop
    nop
    mfc1    $t5, $f10
    bne     $t5, $t4, fail
    nop
    abs.s   $f10, $f8
    mfc1    $t5, $f10
    bne     $t5, $t4, fail
    nop
    neg.s   $f10, $f8
    mfc1    $t5, $f10
    lui     $t6, 0xffc1
    ori     $t6, $t6, 0x2345
    bne     $t5, $t6, fail
    nop

    /* Full C.* result matrix for 1.0 < 2.0. */
    check_compare 0, 0
    check_compare 1, 0
    check_compare 2, 0
    check_compare 3, 0
    check_compare 4, 1
    check_compare 5, 1
    check_compare 6, 1
    check_compare 7, 1
    check_compare 8, 0
    check_compare 9, 0
    check_compare 10, 0
    check_compare 11, 0
    check_compare 12, 1
    check_compare 13, 1
    check_compare 14, 1
    check_compare 15, 1

    /* Equal finite operands. */
    mtc1    $t0, $f2
    check_compare 0, 0
    check_compare 1, 0
    check_compare 2, 1
    check_compare 3, 1
    check_compare 4, 0
    check_compare 5, 0
    check_compare 6, 1
    check_compare 7, 1
    check_compare 8, 0
    check_compare 9, 0
    check_compare 10, 1
    check_compare 11, 1
    check_compare 12, 0
    check_compare 13, 0
    check_compare 14, 1
    check_compare 15, 1

    /* Quiet NaN versus 1.0: only unordered-inclusive predicates are true. */
    lui     $t4, 0x7fc0
    ori     $t4, $t4, 0x0001
    mtc1    $t4, $f0
    check_compare 0, 0
    check_compare 1, 1
    check_compare 2, 0
    check_compare 3, 1
    check_compare 4, 0
    check_compare 5, 1
    check_compare 6, 0
    check_compare 7, 1
    check_compare 8, 0
    check_compare 9, 1
    check_compare 10, 0
    check_compare 11, 1
    check_compare 12, 0
    check_compare 13, 1
    check_compare 14, 0
    check_compare 15, 1

    /* Restore both operands for the arithmetic and memory checks below. */
    mtc1    $t0, $f0
    mtc1    $t1, $f2

    add.s   $f8, $f0, $f2       /* 3.0 */
    mfc1    $t4, $f8
    lui     $t5, 0x4040
    bne     $t4, $t5, fail
    nop

    sub.s   $f8, $f2, $f0       /* 1.0 */
    mfc1    $t4, $f8
    bne     $t4, $t0, fail
    nop

    mul.s   $f8, $f2, $f2       /* 4.0 */
    mfc1    $t4, $f8
    bne     $t4, $t3, fail
    nop

    div.s   $f8, $f2, $f0       /* 2.0 */
    mfc1    $t4, $f8
    bne     $t4, $t1, fail
    nop

    sqrt.s  $f8, $f6            /* 2.0 */
    mfc1    $t4, $f8
    bne     $t4, $t1, fail
    nop

    neg.s   $f8, $f2
    nop
    nop
    nop
    abs.s   $f8, $f8             /* 2.0 */
    mfc1    $t4, $f8
    bne     $t4, $t1, fail
    nop

    /* COP1 conditional moves: MOVZ/MOVN use the integer rt condition and
     * must leave the destination unchanged when the condition is false. */
    mtc1    $t0, $f8              /* destination starts at 1.0 */
    movz.s  $f8, $f2, $zero        /* zero -> move 2.0 */
    mfc1    $t5, $f8
    bne     $t5, $t1, fail
    nop
    mtc1    $t0, $f8              /* restore 1.0 */
    movz.s  $f8, $f2, $t1         /* non-zero -> no move */
    mfc1    $t5, $f8
    bne     $t5, $t0, fail
    nop
    movn.s  $f8, $f2, $t1         /* non-zero -> move 2.0 */
    mfc1    $t5, $f8
    bne     $t5, $t1, fail
    nop
    mtc1    $t0, $f8
    movn.s  $f8, $f2, $zero       /* zero -> no move */
    mfc1    $t5, $f8
    bne     $t5, $t0, fail
    nop

    /* MIPS32 COP1 W/S conversion and rounding slice. */
    addiu   $t0, $zero, 3
    mtc1    $t0, $f0
    cvt.s.w $f2, $f0             /* 3 -> 3.0 */
    mfc1    $t4, $f2
    lui     $t5, 0x4040
    bne     $t4, $t5, fail
    nop
    cvt.w.s $f4, $f2             /* 3.0 -> 3 */
    mfc1    $t4, $f4
    addiu   $t5, $zero, 3
    bne     $t4, $t5, fail
    nop

    /* Conversion overflow is Invalid, not a host-dependent $rtoi result. */
    ctc1    $zero, $31
    nop
    nop
    lui     $t0, 0x4f00          /* +2^31, outside signed W range */
    mtc1    $t0, $f0
    cvt.w.s $f4, $f0
    mfc1    $t4, $f4
    lui     $t5, 0x8000          /* MIPS indefinite integer result */
    bne     $t4, $t5, conversion_result_fail
    nop
    cfc1    $t6, $31
    srl     $t7, $t6, 2          /* FCSR Flags[4:0] */
    andi    $t7, $t7, 0x0010     /* Invalid flag */
    beq     $t7, $zero, conversion_flag_fail
    nop

    lui     $t0, 0x4060          /* 3.5 */
    ori     $t0, $t0, 0x0000
    mtc1    $t0, $f0
    round.w.s $f6, $f0           /* nearest, ties away from zero: 4 */
    trunc.w.s $f8, $f0           /* toward zero: 3 */
    ceil.w.s  $f10, $f0           /* toward +infinity: 4 */
    floor.w.s $f12, $f0           /* toward -infinity: 3 */
    mfc1    $t4, $f6
    addiu   $t5, $zero, 4
    bne     $t4, $t5, fail
    nop
    mfc1    $t4, $f8
    addiu   $t5, $zero, 3
    bne     $t4, $t5, fail
    nop
    mfc1    $t4, $f10
    addiu   $t5, $zero, 4
    bne     $t4, $t5, fail
    nop
    mfc1    $t4, $f12
    addiu   $t5, $zero, 3
    bne     $t4, $t5, fail
    nop

    /* Reciprocal operations use exact binary vectors for RTL/QEMU parity. */
    lui     $t0, 0x4080              /* 4.0 */
    ori     $t0, $t0, 0x0000
    mtc1    $t0, $f0
    .word   0x46000095               /* recip.s $f2,$f0: 1/4 = 0.25 */
    mfc1    $t4, $f2
    lui     $t5, 0x3e80
    bne     $t4, $t5, fail
    nop
    .word   0x46000096               /* rsqrt.s $f2,$f0: 1/sqrt(4) = 0.5 */
    mfc1    $t4, $f2
    lui     $t5, 0x3f00
    bne     $t4, $t5, fail
    nop

    /* Zero boundaries: reciprocal/rsqrt preserve the zero sign in Inf and
     * report Divide-by-zero through the sticky FCSR Flags field. */
    mtc1    $zero, $f0
    .word   0x46000095               /* recip.s +0 = +Inf */
    nop
    nop
    nop
    mfc1    $t4, $f2
    lui     $t5, 0x7f80
    bne     $t4, $t5, fail
    nop
    cfc1    $t6, $31
    srl     $t7, $t6, 2
    andi    $t7, $t7, 0x0008        /* Flags[3] = Divide-by-zero */
    beq     $t7, $zero, fail
    nop
    lui     $t0, 0x8000
    mtc1    $t0, $f0
    .word   0x46000096               /* rsqrt.s -0 = -Inf */
    nop
    nop
    nop
    mfc1    $t4, $f2
    lui     $t5, 0xff80
    bne     $t4, $t5, fail
    nop
    cfc1    $t6, $31
    srl     $t7, $t6, 2
    andi    $t7, $t7, 0x0008
    beq     $t7, $zero, fail
    nop

    /* Fused arithmetic uses fd as the accumulator: 2*3 +/- 1. */
    lui     $t0, 0x4000
    ori     $t0, $t0, 0
    mtc1    $t0, $f0
    lui     $t1, 0x4040
    ori     $t1, $t1, 0
    mtc1    $t1, $f4
    lui     $t2, 0x3f80
    ori     $t2, $t2, 0
    mtc1    $t2, $f2
    .word   0x4c4400a0               /* madd.s = 7.0 */
    mfc1    $t4, $f2
    lui     $t5, 0x40e0
    bne     $t4, $t5, fail
    nop
    mtc1    $t2, $f2
    .word   0x4c4400a8               /* msub.s = 5.0 */
    mfc1    $t4, $f2
    lui     $t5, 0x40a0
    bne     $t4, $t5, fail
    nop
    mtc1    $t2, $f2
    .word   0x4c4400b0               /* nmadd.s = -7.0 */
    mfc1    $t4, $f2
    lui     $t5, 0xc0e0
    bne     $t4, $t5, fail
    nop
    mtc1    $t2, $f2
    .word   0x4c4400b8               /* nmsub.s = -5.0 */
    mfc1    $t4, $f2
    lui     $t5, 0xc0a0
    bne     $t4, $t5, fail
    nop

    /* Restore arithmetic operands for the memory checks below. */
    lui     $t0, 0x3f80
    ori     $t0, $t0, 0x0000
    lui     $t1, 0x4000
    ori     $t1, $t1, 0x0000
    mtc1    $t0, $f0
    mtc1    $t1, $f2

    /* LWC1/SWC1 use the normal data path but target the FPR file. */
    /* Use the behavioral DDR test window, whose low physical address is
     * covered by the SoC data-memory model and does not overlap firmware. */
    lui     $t8, 0x0000
    ori     $t8, $t8, 0x8000
    sw      $t0, 0($t8)
    lwc1    $f10, 0($t8)
    mfc1    $t4, $f10
    bne     $t4, $t0, fail
    nop
    swc1    $f2, 4($t8)
    lw      $t4, 4($t8)
    bne     $t4, $t1, fail
    nop

    /* LDC1/SDC1 are two precise little-endian word beats into an even FPR
     * pair.  The high word is checked through the odd partner register. */
    ldc1    $f12, 0($t8)
    mfc1    $t4, $f12
    bne     $t4, $t0, fail
    nop
    sdc1    $f12, 8($t8)
    lw      $t4, 8($t8)
    bne     $t4, $t0, fail
    nop
    lw      $t4, 12($t8)
    bne     $t4, $t1, fail
    nop

    /* COP1X indexed memory uses GPR[rs]+GPR[rt] and FPR[rd].  Keep the
     * encodings explicit so this regression also checks the legacy MIPS32
     * R2 form independently of assembler pseudo-op availability. */
    addiu   $t9, $zero, 0
    nop
    nop
    nop
    .word   0x4f197000             /* lwxc1  $f14,$t9($t8) */
    mfc1    $t4, $f14
    bne     $t4, $t0, fail
    nop
    .word   0x4f198001             /* ldxc1  $f16,$t9($t8) */
    mfc1    $t4, $f16
    bne     $t4, $t0, fail
    nop
    .word   0x440c8800             /* mfc1 $t4,$f17 (odd partner) */
    bne     $t4, $t1, fail
    nop
    .word   0x4f191008             /* swxc1  $f2,$t9($t8) */
    lw      $t4, 0($t8)
    bne     $t4, $t1, fail
    nop
    .word   0x4f196009             /* sdxc1  $f12,$t9($t8) */
    lw      $t4, 0($t8)
    bne     $t4, $t0, fail
    nop
    lw      $t4, 4($t8)
    bne     $t4, $t1, fail
    nop

    cfc1    $t6, $31             /* FCSR is readable */
    ctc1    $t6, $31
    la      $a0, fpu_pass_msg
    jal     print_str
    nop
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xbeef
    lui     $t8, 0x4000
    ori     $t8, $t8, 0x0000
    addiu   $t9, $zero, 0x50
    sw      $t9, 0($t8)
    sw      $t6, 0($t7)
1:  b       1b
    nop

fail:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xbad0
    ori     $t6, $t6, 0x0001
    la      $a0, fpu_fail_msg
    jal     print_str
    nop
    lui     $t8, 0x4000
    ori     $t8, $t8, 0x0000
    addiu   $t9, $zero, 0x46
    sw      $t9, 0($t8)
    sw      $t6, 0($t7)
2:  b       2b
    nop

conversion_fail:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xbad0
    ori     $t6, $t6, 0x0008
    la      $a0, fpu_conversion_fail_msg
    jal     print_str
    nop
    lui     $t8, 0x4000
    ori     $t8, $t8, 0x0000
    addiu   $t9, $zero, 0x43
    sw      $t9, 0($t8)
    sw      $t6, 0($t7)
3:  b       3b
    nop

conversion_result_fail:
    la      $a0, fpu_conversion_result_fail_msg
    jal     print_str
    nop
    move    $a0, $t4
    jal     print_hex
    nop
    b       conversion_fail
    nop

conversion_flag_fail:
    la      $a0, fpu_conversion_flag_fail_msg
    jal     print_str
    nop
    move    $a0, $t6
    jal     print_hex
    nop
    b       conversion_fail
    nop

    .section .rodata
    .align 2
fpu_pass_msg:
    .asciz "FPU PASS\n"
fpu_fail_msg:
    .asciz "FPU FAIL\n"
fpu_conversion_fail_msg:
    .asciz "FPU CONV FAIL\n"
fpu_conversion_result_fail_msg:
    .asciz "FPU CONV RESULT FAIL\n"
fpu_conversion_flag_fail_msg:
    .asciz "FPU CONV FLAG FAIL\n"
