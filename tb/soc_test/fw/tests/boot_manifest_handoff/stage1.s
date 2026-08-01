    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* Exercise both kseg0 instruction and data paths after handoff. */
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x7000
    lui     $t1, 0xCAFE
    ori     $t1, $t1, 0xBABE
    sw      $t1, 0($t0)

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

stage1_loop:
    b       stage1_loop
    nop
