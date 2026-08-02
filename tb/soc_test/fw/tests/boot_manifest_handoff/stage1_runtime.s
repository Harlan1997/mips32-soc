    .set noreorder
    .set noat

    /* The loader keeps text in place and relocates writable runtime data. */
    .equ HANDLER_OFFSET,       0x000000A0
    .equ MAIN_OFFSET,          0x00000100
    .equ LINK_DATA_OFFSET,     0x000002D0
    .equ RUNTIME_DATA_OFFSET,  0x00000670
    .equ RUNTIME_BSS_OFFSET,   0x00000680
    .equ RELOC_OFFSET,         0x00000300

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* Copy the initialized data word to its runtime address and apply the
     * absolute relocation slot in-place. Both writes use kseg1 so the
     * handoff is visible before the kseg0 runtime reads it. */
    lui     $s0, 0xA000
    ori     $s0, $s0, 0x1000
    addiu   $t0, $s0, LINK_DATA_OFFSET
    lui     $t1, 0xA000
    ori     $t1, $t1, 0x1670
    lw      $t2, 0($t0)
    sw      $t2, 0($t1)

    addiu   $t0, $s0, RELOC_OFFSET
    lui     $t1, 0x8000
    ori     $t1, $t1, 0x1670
    sw      $t1, 0($t0)

    /* Uncached loader writes must drain before entering kseg0 runtime. */
    lw      $t2, 0($t1)
    nop
    nop

    lui     $t9, 0x8000
    ori     $t9, $t9, 0x1100
    jr      $t9
    nop

    /* This handler is copied by the relocated runtime to EBase+0x180. */
    .section .runtime_handler, "ax"
runtime_general_handler:
    mfc0    $k0, $14
    nop
    nop
    nop
    nop
    nop
    addiu   $k0, $k0, 4
    mtc0    $k0, $14
    nop
    nop
    nop
    nop
    nop
    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFF0
    lui     $k1, 0xACCE
    ori     $k1, $k1, 0x5511
    sw      $k1, 0($k0)
    eret
    nop

    /* All symbols below are addressed through the runtime base, not through
     * link-time absolute addresses. This is the loader ABI under test. */
    .section .runtime_main, "ax"
runtime_main:
    lui     $s0, 0x8000
    ori     $s0, $s0, 0x1000

    /* Relocate the exception entry to EBase+0x180. */
    addiu   $t0, $s0, HANDLER_OFFSET
    lui     $t1, 0xA000
    ori     $t1, $t1, 0x0180
    addiu   $t2, $zero, 20
copy_handler:
    lw      $t3, 0($t0)
    sw      $t3, 0($t1)
    addiu   $t0, $t0, 4
    addiu   $t1, $t1, 4
    addiu   $t2, $t2, -1
    bne     $t2, $zero, copy_handler
    nop

    /* The relocated pointer must now identify the copied .data word. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0x1300
    lw      $t1, 0($t0)
    lui     $t2, 0x8000
    ori     $t2, $t2, 0x1670
    nop
    nop
    bne     $t1, $t2, runtime_fail
    nop
    lw      $t3, 0($t1)
    lui     $t4, 0xCAFE
    ori     $t4, $t4, 0x1234
    nop
    nop
    bne     $t3, $t4, runtime_fail
    nop

    /* Explicit .bss clear and readback. */
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x1680
    addiu   $t1, $t0, 16
bss_clear:
    sw      $zero, 0($t0)
    addiu   $t0, $t0, 4
    bne     $t0, $t1, bss_clear
    nop
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x1680
    lw      $t2, 0($t0)
    nop
    nop
    bne     $t2, $zero, runtime_fail
    nop

    /* A deterministic bump allocation exercises the runtime heap contract. */
    lui     $t0, 0x8000
    ori     $t0, $t0, 0x7000
    lui     $t1, 0x1357
    ori     $t1, $t1, 0x9BDF
    sw      $t1, 0($t0)
    lui     $t2, 0x2468
    ori     $t2, $t2, 0xACE0
    sw      $t2, 4($t0)
    lw      $t3, 0($t0)
    nop
    nop
    bne     $t3, $t1, runtime_fail
    nop
    lw      $t4, 4($t0)
    nop
    nop
    bne     $t4, $t2, runtime_fail
    nop

    /* Stack access stays below the linker-provided stack top. */
    lui     $sp, 0x8000
    ori     $sp, $sp, 0x8000
    addiu   $sp, $sp, -16
    lui     $t0, 0x5A5A
    ori     $t0, $t0, 0xA5A5
    sw      $t0, 0($sp)
    lw      $t1, 0($sp)
    nop
    nop
    bne     $t1, $t0, runtime_fail
    nop

    /* Publish the copied vector through the I-cache maintenance contract. */
    mtc0    $zero, $28
    nop
    nop
    nop
    .word   0xbc080180
    nop
    .word   0xbc080980
    nop
    .word   0xbc081180
    nop
    .word   0xbc081980
    nop

    /* Exercise the relocated general exception entry and ERET retry. */
    syscall
    nop
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lw      $t1, 0($t0)
    lui     $t2, 0xACCE
    ori     $t2, $t2, 0x5511
    bne     $t1, $t2, runtime_fail
    addiu   $t5, $zero, 7

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF8
    lui     $t1, 0x4841
    ori     $t1, $t1, 0x4E44
    sw      $t1, 0($t0)
    addiu   $t0, $t0, 4
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

runtime_loop:
    b       runtime_loop
    nop

runtime_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
    b       runtime_loop
    nop

    .section .rodata, "a"
runtime_rodata_word:
    .word   0x13579BDF

    .section .data, "aw"
runtime_data_word:
    .word   0xCAFE1234

    .section .bss, "aw", @nobits
runtime_bss_words:
    .space  16

    .section .runtime_reloc, "a"
runtime_data_relocation:
    .word   0x800012D0
