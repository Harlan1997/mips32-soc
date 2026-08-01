    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* Exercise a 20-word kseg0 data region across three cache lines. */
    lui     $s0, 0x8000
    ori     $s0, $s0, 0x7000
    addu    $s1, $zero, $zero

depth_write:
    lui     $t1, 0xA500
    or      $t1, $t1, $s1
    sw      $t1, 0($s0)
    addiu   $s0, $s0, 4
    addiu   $s1, $s1, 1
    slti    $t2, $s1, 20
    bne     $t2, $zero, depth_write
    nop

    /* Read every word back through the same translated kseg0 region. */
    lui     $s0, 0x8000
    ori     $s0, $s0, 0x7000
    addu    $s1, $zero, $zero

depth_read:
    lw      $t2, 0($s0)
    lui     $t1, 0xA500
    or      $t1, $t1, $s1
    bne     $t2, $t1, stage1_data_fail
    nop
    addiu   $s0, $s0, 4
    addiu   $s1, $s1, 1
    slti    $t2, $s1, 20
    bne     $t2, $zero, depth_read
    nop

    /* Exercise a stack location in the direct kseg0 SRAM mapping. */
    lui     $sp, 0x8000
    ori     $sp, $sp, 0x8000
    lui     $t1, 0x5A5A
    ori     $t1, $t1, 0xA5A5
    sw      $t1, 0($sp)
    lw      $t2, 0($sp)
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
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

stage1_loop:
    b       stage1_loop
    nop
