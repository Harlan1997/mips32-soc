    .set    noreorder
    .section .text.init
    .globl  _start

_start:
    mtc0    $zero, $12
    ehb
    break   0x123
    nop

    /* The handler is expected to skip BREAK and return here. */
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
    addiu   $k1, $zero, 9
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
