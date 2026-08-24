    .set noreorder
    .section .text.init
    .globl _start

_start:
    lui     $sp, 0x0001
    lui     $t3, 0x4000
    ori     $t3, $t3, 0x4004
    addiu   $t4, $zero, 0x00a5
    sw      $t4, 0($t3)
    jal     load_from_helper
    nop
    # The consumer is intentionally the first useful instruction after the
    # call delay slot.  This is the contract that previously failed in C
    # helper/MMIO code paths.
    addiu   $t0, $zero, 0x00a5
    xor     $t5, $v0, $t0
    bne     $t5, $zero, fail
    nop

    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t1)
1:
    b       1b
    nop

fail:
    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xdead
    sw      $t2, 0($t1)
2:
    b       2b
    nop

load_from_helper:
    lui     $t0, 0x4000
    ori     $t0, $t0, 0x4004
    lw      $v0, 0($t0)
    jr      $ra
    nop
