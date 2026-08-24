    .set noreorder
    .section .text.init
    .globl _start

/*
 * MIPS32 R2 branch-likely contract.  Each not-taken likely branch must skip
 * its delay-slot instruction; each taken branch must execute exactly one.
 * The test uses distinct registers so a stale delay-slot execution cannot be
 * hidden by a later write.
 */
_start:
    addiu $t0, $zero, 0
    addiu $t1, $zero, 0

    /* BEQL not taken: slot must be annulled. */
    addiu $t2, $zero, 1
    addiu $t3, $zero, 2
    .word 0x514b0001       /* beql $t2,$t3, +1 */
    addiu $t0, $t0, 1     /* annulled */
    addiu $t1, $t1, 1     /* target */

    /* BNEL taken: slot must execute. */
    addiu $t2, $zero, 1
    addiu $t3, $zero, 2
    .word 0x554b0001       /* bnel $t2,$t3, +1 */
    addiu $t0, $t0, 2     /* delay slot */
    addiu $t1, $t1, 2     /* target */

    /* BLEZL not taken: slot must be annulled. */
    addiu $t2, $zero, 1
    .word 0x59400001       /* blezl $t2, +1 */
    addiu $t0, $t0, 4     /* annulled */
    addiu $t1, $t1, 4     /* target */

    /* BGTZL taken: slot must execute. */
    .word 0x5d400001       /* bgtzl $t2, +1 */
    addiu $t0, $t0, 8     /* delay slot */
    addiu $t1, $t1, 8     /* target */

    /* BLTZL not taken and BGEZL taken. */
    .word 0x05420001       /* bltzl $t2, +1 */
    addiu $t0, $t0, 16    /* annulled */
    addiu $t1, $t1, 16   /* target */
    .word 0x05630001       /* bgezl $t3, +1 */
    addiu $t0, $t0, 32    /* delay slot */
    addiu $t1, $t1, 32    /* target */

    /* BLTZALL not taken: neither the slot nor the link write may happen. */
    addiu $ra, $zero, 0x1234
    addiu $t2, $zero, 1
    .word 0x05520001       /* bltzall $t2, +1 */
    addiu $t0, $t0, 64    /* annulled */
    addiu $t1, $t1, 64    /* target */
    addiu $t6, $zero, 0x1234
    bne   $ra, $t6, fail
    nop

    /* BGEZALL taken: link is the branch PC plus eight. */
    addiu $t3, $zero, 1
    .word 0x05730001       /* bgezall $t3, +1 */
    addiu $t0, $t0, 128   /* delay slot */
1:
    addu  $t6, $ra, $zero
    la    $t7, 1b
    bne   $t6, $t7, fail
    nop

    /* Expected: t0 = 2+8+32+128 = 170; t1 = 63+64 = 127. */
    addiu $t4, $zero, 42
    addiu $t4, $t4, 128
    addiu $t5, $zero, 127
    bne   $t0, $t4, fail
    nop
    bne   $t1, $t5, fail
    nop

    lui   $t6, 0xa000
    ori   $t6, $t6, 0xfffc
    lui   $t7, 0xdead
    ori   $t7, $t7, 0xbeef
    sw    $t7, 0($t6)
1:
    b     1b
    nop

fail:
    lui   $t6, 0xa000
    ori   $t6, $t6, 0xfffc
    lui   $t7, 0xdead
    ori   $t7, $t7, 0xdead
    sw    $t7, 0($t6)
2:
    b     2b
    nop
