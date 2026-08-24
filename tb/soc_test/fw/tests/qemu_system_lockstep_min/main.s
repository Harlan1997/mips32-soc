    .set noreorder
    .section .text.init
    .globl _start

_start:
    lui     $t0, 0x1234
    ori     $t0, $t0, 0x5678
    addiu   $t1, $zero, 0x0040
    sw      $t0, 0($t1)
    lw      $t2, 0($t1)
    lui     $t3, 0xa000
    ori     $t3, $t3, 0xfffc
    lui     $t4, 0xdead
    ori     $t4, $t4, 0xbeef
    sw      $t4, 0($t3)

1:
    j       1b
    nop
