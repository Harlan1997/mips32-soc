    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* Test payload: a real kseg0 instruction fetch after Boot ROM handoff. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

stage1_loop:
    b       stage1_loop
    nop
