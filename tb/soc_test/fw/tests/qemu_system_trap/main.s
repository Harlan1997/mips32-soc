    .set    noreorder
    .section .text.init
    .globl  _start

_start:
    mtc0    $zero, $12
    ehb
    addiu   $t0, $zero, 7
    addiu   $t1, $zero, 7
    tge     $t0, $t1
    nop
    addiu   $t1, $zero, 8
    tlt     $t0, $t1
    nop
    addiu   $t0, $zero, -1
    addiu   $t1, $zero, 1
    tltu    $t0, $t1
    nop
    teq     $t0, $t1
    nop
    tne     $t0, $t1
    nop

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
