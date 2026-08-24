    .set    noreorder
    .section .text.init
    .globl  _start

_start:
    addiu   $t3, $zero, 0
    mtc0    $t3, $12
    ehb
    lui     $t0, 0x1357
    ori     $t0, $t0, 0x2468
    syscall
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
    mfc0    $k1, $14
    addiu   $k1, $k1, 4
    mtc0    $k1, $14
    eret
    nop
