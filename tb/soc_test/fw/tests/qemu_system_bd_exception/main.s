    .set    noreorder
    .section .text.init
    .globl  _start

_start:
    addiu   $t3, $zero, 0
    mtc0    $t3, $12
    ehb
    beq     $zero, $zero, 1f
    syscall
    nop
1:
    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t1)
2:
    j       2b
    nop

    .section .except_vector, "ax"
    .align  2
_except_handler:
    mfc0    $k0, $13
    mfc0    $k1, $14
    addiu   $k1, $k1, 8
    mtc0    $k1, $14
    eret
    nop
