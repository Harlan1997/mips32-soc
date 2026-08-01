    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* Exercise a small kseg0 runtime data layout after handoff. */
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x7000
    lui     $t1, 0xCAFE
    ori     $t1, $t1, 0xBABE
    sw      $t1, 0($t0)

    addiu   $t0, $t0, 4
    lui     $t1, 0x1357
    ori     $t1, $t1, 0x9BDF
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t2, $t1, stage1_data_fail
    nop

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)
    b       stage1_loop
    nop

stage1_data_fail:
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

stage1_loop:
    b       stage1_loop
    nop
