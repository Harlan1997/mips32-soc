    .set noreorder
    .set noat

    .section .rodata, "a"
    .align 2
runtime_rodata_word:
    .word 0x13579BDF

    .section .data, "aw"
    .align 2
runtime_data_word:
    .word 0xCAFE1234

    .section .bss, "aw", @nobits
    .align 2
runtime_bss_words:
    .space 16

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* The linker places these symbols in the loaded kseg0 runtime image. */
    lui     $sp, %hi(__runtime_stack_top)
    /* addiu consumes the sign-adjusted low half when bit 15 is set. */
    addiu   $sp, $sp, %lo(__runtime_stack_top)
    addiu   $sp, $sp, -16
    lui     $t0, 0x5A5A
    ori     $t0, $t0, 0xA5A5
    sw      $t0, 0($sp)
    lw      $t1, 0($sp)
    bne     $t1, $t0, stage1_data_fail
    nop

    lui     $t2, %hi(runtime_rodata_word)
    ori     $t2, $t2, %lo(runtime_rodata_word)
    lw      $t3, 0($t2)
    lui     $t4, 0x1357
    ori     $t4, $t4, 0x9BDF
    bne     $t3, $t4, stage1_data_fail
    nop

    lui     $t2, %hi(runtime_data_word)
    ori     $t2, $t2, %lo(runtime_data_word)
    lw      $t3, 0($t2)
    lui     $t4, 0xCAFE
    ori     $t4, $t4, 0x1234
    bne     $t3, $t4, stage1_data_fail
    nop

    /* Explicit BSS initialization is part of this freestanding runtime ABI. */
    lui     $t2, %hi(__runtime_bss_start)
    ori     $t2, $t2, %lo(__runtime_bss_start)
    lui     $t3, %hi(__runtime_bss_end)
    ori     $t3, $t3, %lo(__runtime_bss_end)
bss_zero:
    beq     $t2, $t3, bss_check
    nop
    sw      $zero, 0($t2)
    addiu   $t2, $t2, 4
    b       bss_zero
    nop

bss_check:
    lui     $t2, %hi(runtime_bss_words)
    ori     $t2, $t2, %lo(runtime_bss_words)
    lw      $t3, 0($t2)
    bne     $t3, $zero, stage1_data_fail
    nop
    lui     $t4, 0xFACE
    ori     $t4, $t4, 0xB00C
    sw      $t4, 0($t2)
    lw      $t3, 0($t2)
    bne     $t3, $t4, stage1_data_fail
    nop

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF8
    lui     $t1, 0x4841
    ori     $t1, $t1, 0x4E44
    sw      $t1, 0($t0)
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

stage1_loop:
    b       stage1_loop
    nop

stage1_data_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
    b       stage1_loop
    nop
