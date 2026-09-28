    .set noreorder
    .section .text.init
    .globl _start

/* JAL, exactly one delay-slot instruction, then target. */
_start:
    addiu   $t0, $zero, 0
    addiu   $t1, $zero, 0
    jal     direct_jal_target
    addiu   $t0, $t0, 1          /* exactly one delay-slot execution */
    addiu   $t0, $t0, 0x40       /* fall-through poison */
    b       direct_jal_fail
    nop

direct_jal_target:
    addiu   $t1, $t1, 1          /* target executes once */
    addiu   $t2, $zero, 1
    bne     $t0, $t2, direct_jal_fail
    nop
    bne     $t1, $t2, direct_jal_fail
    nop

    lui     $t3, 0xa000
    ori     $t3, $t3, 0xfffc
    lui     $t4, 0xdead
    ori     $t4, $t4, 0xbeef
    sw      $t4, 0($t3)
1:
    b       1b
    nop

direct_jal_fail:
    lui     $t3, 0xa000
    ori     $t3, $t3, 0xfffc
    lui     $t4, 0xdead
    ori     $t4, $t4, 0xdead
    sw      $t4, 0($t3)
2:
    b       2b
    nop
