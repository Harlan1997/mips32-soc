    .set noreorder
    .set noat

    .equ SRAM_ALIAS,       0xA0000000
    .equ APB_IPI,          0xC000A000
    .equ CORE0_MARKER,     0x0000FF00
    .equ CORE1_MARKER,     0x0000FF04
    .equ SHARED_WORD0,     0x00003000
    .equ SHARED_WORD1,     0x00003004
    .equ HANDOFF_WORD,     0x0000FFF8
    .equ MAILBOX_WORD,     0x0000FFFC

    .section .text.init, "ax"
    .globl stage1_entry

stage1_entry:
    /* CPUNum is returned in t0 by RDHWR $0. */
    .word   0x7c68003b
    nop
    nop
    nop
    nop
    bne     $t0, $zero, kernel_core1
    nop
    /* The product kernel uses the wired APB window before a full MMU setup. */
    mtc0    $zero, $0
    nop
    nop
    nop
    nop
    lui     $t1, 0xC000
    ori     $t1, $t1, 0xA000
    mtc0    $t1, $10
    nop
    nop
    nop
    nop
    lui     $t1, 0x0100
    ori     $t1, $t1, 0x0297
    mtc0    $t1, $2
    nop
    nop
    nop
    nop
    addiu   $t1, $t1, 0x0040
    mtc0    $t1, $3
    nop
    nop
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    nop
    nop
    tlbwi
    nop
    nop
    nop
    nop
    addiu   $t1, $zero, 1
    mtc0    $t1, $6
    nop
    nop
    nop
    nop
    nop
kernel_core0:
    lui     $s0, 0xA000
    ori     $s0, $s0, CORE0_MARKER
    lui     $t1, 0xC0DE
    ori     $t1, $t1, 0x0000
    sw      $t1, 0($s0)

    /* Shared-memory handoff marker is visible through the uncached alias. */
    lui     $s1, 0xA000
    ori     $s1, $s1, SHARED_WORD0
    lui     $t1, 0xCAFE
    ori     $t1, $t1, 0x0000
    sw      $t1, 0($s1)

    /* Let the secondary finish its local TLB setup and publish its marker. */
    ori     $t3, $zero, 0x03FF
kernel_core0_start_delay:
    addiu   $t3, $t3, -1
    bne     $t3, $zero, kernel_core0_start_delay
    nop

    /* Send generation 1 to core 1 through the product IPI window. */
    lui     $s2, 0xC000
    ori     $s2, $s2, 0xA000
    lui     $t1, 0x0000
    ori     $t1, $t1, 0x0101
    sw      $t1, 0x20($s2)
    addiu   $t1, $zero, 1
    sw      $t1, 0x24($s2)
    sw      $zero, 0x28($s2)
    sw      $zero, 0x2C($s2)
    sw      $t1, 0x30($s2)

kernel_core0_done:
    /* Completion records boot and IPI delivery; software ACK handling is a
     * later product-kernel responsibility beyond this boot contract. */
    lui     $s0, 0xA000
    ori     $s0, $s0, HANDOFF_WORD
    lui     $t1, 0x4841
    ori     $t1, $t1, 0x4E44
    sw      $t1, 0($s0)
    addiu   $s0, $s0, 4
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($s0)
kernel_core0_loop:
    b       kernel_core0_loop
    nop

kernel_core1:
    lui     $s0, 0xA000
    ori     $s0, $s0, CORE1_MARKER
    lui     $t1, 0xC0DE
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($s0)
    lui     $s1, 0xA000
    ori     $s1, $s1, SHARED_WORD1
    lui     $t1, 0xCAFE
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($s1)
kernel_core1_loop:
    b       kernel_core1_loop
    nop

kernel_fail:
    lui     $s0, 0xA000
    ori     $s0, $s0, MAILBOX_WORD
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($s0)
    b       kernel_fail
    nop
