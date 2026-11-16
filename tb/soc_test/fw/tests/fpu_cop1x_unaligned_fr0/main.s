    .set noreorder

    /* FR=0 is implementation-defined for LUXC1/SUXC1.  This bounded RTL
     * probe records the project's deterministic even/odd-pair behavior; it is
     * intentionally kept separate from the FR=1 RTL/QEMU differential. */
    .macro check_lux offset
    addiu   $t9, $zero, \offset
    .word   0x4f197005          /* luxc1 $f14,$t9($t8) */
    nop
    nop
    nop
    mfc1    $t6, $f14
    bne     $t6, $t0, fail
    nop
    .word   0x440e7800          /* mfc1 $t6,$f15 */
    bne     $t6, $t1, fail
    nop
    .endm

    .macro check_sux offset
    addiu   $t9, $zero, \offset
    .word   0x4f19100d          /* suxc1 $f2,$t9($t8) */
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
    addiu   $t1, $zero, 'V'
    sw      $t1, 0($t0)
    mfc0    $t6, $12
    lui     $t9, 0x2000           /* CU1=1, FR=0 */
    or      $t6, $t6, $t9
    mtc0    $t6, $12
    nop
    nop
    nop

    lui     $t8, 0xa000
    ori     $t8, $t8, 0x1000
    or      $t7, $t8, $zero
    lui     $t0, 0x1122
    ori     $t0, $t0, 0x3344
    lui     $t1, 0x5566
    ori     $t1, $t1, 0x7788
    lui     $t2, 0xaabb
    ori     $t2, $t2, 0xccdd
    lui     $t3, 0xeeff
    ori     $t3, $t3, 0x0011
    lui     $t4, 0xa5a5
    ori     $t4, $t4, 0xa5a5
    lui     $t5, 0x5a5a
    ori     $t5, $t5, 0x5a5a
    sw      $t4, -4($t7)
    sw      $t0, 0($t7)
    sw      $t1, 4($t7)
    sw      $t5, 8($t7)
    mtc1    $t2, $f2
    .word   0x448b1800            /* mtc1 $t3,$f3 */
    nop
    nop
    nop

    check_lux 0
    check_lux 1
    check_lux 2
    check_lux 3
    check_sux 0
    check_sux 1
    check_sux 2
    check_sux 3

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
    ori     $t6, $t6, 0x0003
    sw      $t6, 0($t7)
2:  b       2b
    nop
