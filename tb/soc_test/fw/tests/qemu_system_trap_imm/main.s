.set    noreorder
.section .text.init
.globl  _start

_start:
    mtc0    $zero, $12
    ehb
    addiu   $t0, $zero, 7
    tgei    $t0, 7
    nop
    tgeiu   $t0, 7
    nop
    tlti    $t0, 8
    nop
    tltiu   $t0, 8
    nop
    teqi    $t0, 7
    nop
    tnei    $t0, 8
    nop
    # Verify a trap immediately followed by a multi-cycle MDU op (msub) does
    # not speculatively commit HI/LO before the trap flushes the pipeline.
    mtlo    $zero
    mthi    $zero
    addiu   $t3, $zero, 3
    addiu   $t4, $zero, 5
    tltiu   $t0, 8
    msub    $t3, $t4
    mflo    $t5
    mfhi    $t6

    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t1)
1:
    j       1b
    nop

.section .except_vector, "ax"
.align  2
.globl  _except_handler
_except_handler:
    mfc0    $k0, $13
    andi    $k0, $k0, 0x007c
    addiu   $k1, $zero, 13
    sll     $k1, $k1, 2
    bne     $k0, $k1, 2f
    nop
    mfc0    $k1, $14
    addiu   $k1, $k1, 4
    mtc0    $k1, $14
    eret
    nop
2:
    j       2b
    nop
