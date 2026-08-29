    .set    noreorder
    .section .text.init
    .globl  _start

_start:
    addiu   $t3, $zero, 0
    mtc0    $t3, $12
    ehb
    lui     $t6, 0x0000
    ori     $t6, $t6, 0x0030       # Cause.ExcCode == 12, shifted into bits 6:2
    addiu   $t8, $zero, 0x0020     # Cause.ExcCode == 8 (syscall)

    # ADD overflow: the wrapped result must not reach the destination.
    lui     $t0, 0x7fff
    ori     $t0, $t0, 0xffff
    lui     $t7, 0x1111
    ori     $t7, $t7, 0x1111
    addu    $t4, $t7, $zero
    add     $t4, $t0, $t0
    bne     $t4, $t7, 2f
    nop

    # SUB overflow: INT_MIN - 1 must not reach the destination.
    lui     $t1, 0x8000
    addiu   $t2, $zero, 1
    addu    $t4, $t7, $zero
    sub     $t4, $t1, $t2
    bne     $t4, $t7, 2f
    nop

    # ADDI overflow: MAX_INT + 1 must not reach the destination.
    addu    $t4, $t7, $zero
    addi    $t4, $t0, 1
    bne     $t4, $t7, 2f
    nop

    # ADDIU has identical arithmetic bits but never traps; its wrap is
    # checked architecturally and the following instruction must execute.
    addiu   $t4, $t0, 1
    lui     $t5, 0x8000
    bne     $t4, $t5, 2f
    nop

    lui     $t3, 0x1357
    ori     $t3, $t3, 0x2468
    syscall
    nop
    b       4f
    nop

2:
    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0x0000
    sw      $t2, 0($t1)
    b       3f
    nop

4:
    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t1)
3:
failure_loop:
    j       failure_loop
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    mfc0    $k0, $13
    mfc0    $k1, $14
    addiu   $k1, $k1, 4
    mtc0    $k1, $14
    andi    $k0, $k0, 0x007c
    nop
    beq     $k0, $t8, 1f
    nop
    beq     $k0, $t6, 1f
    nop
    b       2b
    nop
1:
    eret
    nop
