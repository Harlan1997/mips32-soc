    .set    noreorder
    .section .text.init
    .globl  _start

/* Minimal architectural workload for the opt-in L1 nonblocking DDR path. */
_start:
    lui     $t0, 0x0800
    ori     $t0, $t0, 0x0000       /* DDR line 0 */
    lui     $t1, 0x1122
    ori     $t1, $t1, 0x3344
    sw      $t1, 0($t0)
    lui     $t1, 0xa5a5
    ori     $t1, $t1, 0x5a5a
    sw      $t1, 4($t0)
    lw      $t2, 0($t0)
    lw      $t3, 4($t0)

    lui     $t4, 0x0800
    ori     $t4, $t4, 0x0040       /* distinct cache line */
    lui     $t5, 0xcafe
    ori     $t5, $t5, 0xbeef
    sw      $t5, 0($t4)
    lw      $t6, 0($t4)
    lw      $t7, 0($t0)            /* final hit */

    lui     $t8, 0xa000
    ori     $t8, $t8, 0xfffc
    lui     $t9, 0xdead
    ori     $t9, $t9, 0xbeef
    sw      $t9, 0($t8)
1:
    j       1b
    nop
