    .set noreorder

    /* MIPS32 LUXC1/SUXC1 ignore EffectiveAddress[2:0].  Exercise every
     * low-bit value while checking that only the aligned doubleword changes. */
    .macro check_fr1_lux offset
    addiu   $t9, $zero, \offset
    .word   0x4f194005          /* luxc1 $f8,$t9($t8) */
    nop
    nop
    nop
    mfc1    $t6, $f8
    bne     $t6, $t0, fail
    nop
    .word   0x446e4000          /* mfhc1 $t6,$f8 */
    bne     $t6, $t1, fail
    nop
    .endm

    .macro check_fr1_sux offset
    addiu   $t9, $zero, \offset
    .word   0x4f19500d          /* suxc1 $f10,$t9($t8) */
    nop
    nop
    nop
    lw      $t6, 0($t7)
    bne     $t6, $t2, fail
    nop
    lw      $t6, 4($t7)
    bne     $t6, $t3, fail
    nop
    lw      $t6, -4($t7)
    bne     $t6, $t4, fail
    nop
    lw      $t6, 8($t7)
    bne     $t6, $t5, fail
    nop
    .endm

    .text
    .globl main
main:
    lui     $t0, 0x4000
    addiu   $t1, $zero, 'U'
    sw      $t1, 0($t0)

    /* CU1=1, FR=0. */
    mfc0    $t6, $12
    lui     $t9, 0x2000
    or      $t6, $t6, $t9
    mtc0    $t6, $12
    nop
    nop
    nop

    lui     $t8, 0xa000
    ori     $t8, $t8, 0x1000
    or      $t7, $t8, $zero
    lui     $t0, 0x1122           /* expected low word */
    ori     $t0, $t0, 0x3344
    lui     $t1, 0x5566           /* expected high word */
    ori     $t1, $t1, 0x7788
    lui     $t2, 0xaabb           /* SUXC1 low word */
    ori     $t2, $t2, 0xccdd
    lui     $t3, 0xeeff           /* SUXC1 high word */
    ori     $t3, $t3, 0x0011
    lui     $t4, 0xa5a5           /* word before aligned doubleword */
    ori     $t4, $t4, 0xa5a5
    lui     $t5, 0x5a5a           /* word after aligned doubleword */
    ori     $t5, $t5, 0x5a5a

    sw      $t4, -4($t7)
    sw      $t0, 0($t7)
    sw      $t1, 4($t7)
    sw      $t5, 8($t7)
    /* LUXC1/SUXC1 are architecturally predictable in FR=1. */
    sw      $t4, -4($t7)
    sw      $t0, 0($t7)
    sw      $t1, 4($t7)
    sw      $t5, 8($t7)
    mfc0    $t6, $12
    lui     $t9, 0x2400           /* retain CU1 and set FR */
    or      $t6, $t6, $t9
    mtc0    $t6, $12
    nop
    nop
    nop

    /* FR=1 stores the high word in the same FPR, via MTHC1. */
    .word   0x448a5000            /* mtc1 $t2,$f10 */
    .word   0x44eb5000            /* mthc1 $t3,$f10 */
    nop
    nop
    nop
    check_fr1_lux 0
    check_fr1_lux 1
    check_fr1_lux 2
    check_fr1_lux 3
    check_fr1_sux 0
    check_fr1_sux 1
    check_fr1_sux 2
    check_fr1_sux 3

    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xbeef
    sw      $t6, 0($t7)
1:  b       1b
    nop

fail:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdeaf
    ori     $t6, $t6, 0x0002
    sw      $t6, 0($t7)
2:  b       2b
    nop
