    .set noreorder
    .set noat

    .equ TABLE_PA,       0x00001800
    .equ TABLE_KSEG1,    0xA0001800
    .equ SEG_TEXT_PA,    0x00006000
    .equ SEG_RODATA_PA,  0x00007000
    .equ SEG_DATA_PA,    0x00007004
    .equ SEG_TEXT_SRC,   0x00001A00
    .equ SEG_RODATA_SRC, 0x00001A20
    .equ SEG_DATA_SRC,   0x00001A24
    .equ FLAG_R,          0x1
    .equ FLAG_W,          0x2
    .equ FLAG_X,          0x4

    .section .text.init, "ax"
    .globl stage1_entry
stage1_entry:
    /* Validate the segment table header and each descriptor's W^X policy. */
    lui     $s0, 0xA000
    ori     $s0, $s0, 0x1800
    lw      $t0, 0($s0)
    lui     $t1, 0x5345
    ori     $t1, $t1, 0x4731
    bne     $t0, $t1, multi_fail
    nop
    lw      $t0, 4($s0)
    addiu   $t1, $zero, 3
    bne     $t0, $t1, multi_fail
    nop

    addiu   $s1, $s0, 8
    addiu   $s2, $zero, 3
multi_descriptor:
    lw      $t0, 0($s1)       /* load physical address */
    lw      $t1, 4($s1)       /* source physical address */
    lw      $t2, 8($s1)       /* byte length */
    lw      $t3, 12($s1)      /* R/W/X flags */
    andi    $t4, $t3, (FLAG_W | FLAG_X)
    addiu   $t5, $zero, (FLAG_W | FLAG_X)
    beq     $t4, $t5, multi_fail
    nop
    beq     $t2, $zero, multi_fail
    nop
    andi    $t4, $t0, 3
    bne     $t4, $zero, multi_fail
    nop
    andi    $t4, $t1, 3
    bne     $t4, $zero, multi_fail
    nop

    /* Copy one word-aligned segment through uncached aliases. */
    lui     $t6, 0xA000
    srl     $t7, $t0, 16
    sll     $t7, $t7, 16
    or      $t6, $t6, $t7
    andi    $t7, $t0, 0xFFFF
    addu    $t6, $t6, $t7
    lui     $t7, 0xA000
    srl     $t8, $t1, 16
    sll     $t8, $t8, 16
    or      $t7, $t7, $t8
    andi    $t8, $t1, 0xFFFF
    addu    $t7, $t7, $t8
    srl     $t8, $t2, 2
multi_copy:
    lw      $t9, 0($t7)
    sw      $t9, 0($t6)
    addiu   $t7, $t7, 4
    addiu   $t6, $t6, 4
    addiu   $t8, $t8, -1
    bne     $t8, $zero, multi_copy
    nop

    addiu   $s1, $s1, 16
    addiu   $s2, $s2, -1
    bne     $s2, $zero, multi_descriptor
    nop

    /* Apply the single GOT-style relocation carried by the RW segment.
     * The link-time pointer names the source rodata alias; convert it to
     * the copied runtime rodata alias before entering the payload. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0x700C
    lw      $t1, 0($t0)
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x55E0
    addu    $t1, $t1, $t2
    sw      $t1, 0($t0)
    lui     $t0, 0xA000
    ori     $t0, $t0, 0x7010
    lw      $t1, 0($t0)
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x4600
    addu    $t1, $t1, $t2
    sw      $t1, 0($t0)

    /* Execute the copied X segment and verify the R-only and RW segments. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0x7010
    lw      $t9, 0($t0)
    jalr    $t9
    nop
    lui     $t0, 0xA000
    ori     $t0, $t0, 0x7000
    lw      $t1, 0($t0)
    lui     $t2, 0x524F
    ori     $t2, $t2, 0x4441
    bne     $t1, $t2, multi_fail
    nop
    lw      $t1, 4($t0)
    lui     $t2, 0x4441
    ori     $t2, $t2, 0x5441
    bne     $t1, $t2, multi_fail
    nop
    lw      $t1, 12($t0)
    lui     $t2, 0xA000
    ori     $t2, $t2, 0x7000
    bne     $t1, $t2, multi_fail
    nop
    lw      $t1, 0($t1)
    lui     $t2, 0x524F
    ori     $t2, $t2, 0x4441
    bne     $t1, $t2, multi_fail
    nop

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF8
    lui     $t1, 0x4841
    ori     $t1, $t1, 0x4E44
    sw      $t1, 0($t0)
    addiu   $t0, $t0, 4
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)
multi_loop:
    b       multi_loop
    nop

multi_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
    b       multi_loop
    nop

    .section .segment_table, "a"
    .word   0x53454731
    .word   3
    .word   0x00006000, SEG_TEXT_SRC, 24, (FLAG_R | FLAG_X)
    .word   0x00007000, SEG_RODATA_SRC, 4, FLAG_R
    .word   0x00007004, SEG_DATA_SRC, 16, (FLAG_R | FLAG_W)

    .section .segment_text, "ax"
segment_text_entry:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lui     $t1, 0x4D53
    ori     $t1, $t1, 0x4547
    sw      $t1, 0($t0)
    jr      $ra
    nop

    .section .segment_rodata, "a"
    .word   0x524F4441

    .section .segment_data, "aw"
    .word   0x44415441
    .word   0x00000000
    .word   0xA0001A20
    .word   0xA0001A00
