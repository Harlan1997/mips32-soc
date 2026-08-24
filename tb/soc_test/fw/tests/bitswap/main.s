    .set noreorder
    .section .text.init
    .globl _start
_start:
    lui     $t0, 0x1234
    ori     $t0, $t0, 0x5678
    .word   0x7c084820          /* bitswap $t1,$t0 */
    lui     $t2, 0x482c
    ori     $t2, $t2, 0x6a1e
    bne     $t1, $t2, fail
    nop

    lui     $t0, 0x8001
    ori     $t0, $t0, 0x00ff
    .word   0x7c084820
    lui     $t2, 0x0180
    ori     $t2, $t2, 0x00ff
    bne     $t1, $t2, fail
    nop

    lui     $t6, 0xa000
    ori     $t6, $t6, 0xfffc
    lui     $t7, 0xdead
    ori     $t7, $t7, 0xbeef
    sw      $t7, 0($t6)
1:  b       1b
    nop
fail:
    lui     $t6, 0xa000
    ori     $t6, $t6, 0xfffc
    lui     $t7, 0xdead
    ori     $t7, $t7, 0xdead
    sw      $t7, 0($t6)
2:  b       2b
    nop
