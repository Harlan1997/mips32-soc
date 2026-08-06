    .set noreorder
    .set noat

    .equ USER_EVEN,     0x08000000
    .equ USER_ODD,      0x08004000
    .equ PFN_EVEN,      0x08010
    .equ PFN_ODD,       0x08020
    .equ PAGE_MASK_16K, 0x00006000
    .equ MARK_CONTEXT,  0xC0030001
    .equ MARK_ACCESS,   0xC0030002

    .section .text.init, "ax"
    .globl _start
_start:
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256
    lui     $t0, 0x1040
    mtc0    $t0, $12
    nop
    nop
    nop
    nop

    /* Wired global 4KB APB mapping keeps the mailbox available. */
    mtc0    $zero, $0
    nop
    lui     $t0, 0xC000
    mtc0    $t0, $10
    nop
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x0017
    mtc0    $t0, $2
    nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop
    mtc0    $zero, $5
    nop
    tlbwi
    nop
    addiu   $t0, $zero, 1
    mtc0    $t0, $6
    nop

    addiu   $t0, $zero, 7
    mtc0    $t0, $10
    nop
    nop
    nop

    /* Even 16KB half. */
    lui     $t0, 0x0800
    lui     $t1, 0x165A
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    /* VA bit 14 selects the odd 16KB half. */
    lui     $t0, 0x0800
    ori     $t0, $t0, 0x4000
    lui     $t1, 0x265A
    ori     $t1, $t1, 0x0002
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    /* Non-zero offsets exercise the larger-page PFN folding path. */
    lui     $t0, 0x0800
    ori     $t0, $t0, 0x1000
    lui     $t1, 0x165A
    ori     $t1, $t1, 0x1001
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    lui     $t0, 0x0800
    ori     $t0, $t0, 0x5000
    lui     $t1, 0x265A
    ori     $t1, $t1, 0x1002
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lui     $t1, 0xC003
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)
    addiu   $t0, $t0, 4
    lui     $t1, 0xC003
    ori     $t1, $t1, 0x0002
    sw      $t1, 0($t0)
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)
pass_loop:
    b       pass_loop
    nop
fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
fail_loop:
    b       fail_loop
    nop

    .section .tlb_refill, "ax"
    .globl _tlb_refill
_tlb_refill:
    sw      $t0, 0($sp)
    sw      $t1, 4($sp)
    sw      $t2, 8($sp)
    sw      $t3, 12($sp)
    mfc0    $k0, $8
    mfc0    $t1, $10
    lui     $k1, 0xFFFF
    ori     $k1, $k1, 0xE000
    and     $k0, $k0, $k1
    andi    $t1, $t1, 0x00FF
    or      $k0, $k0, $t1
    mtc0    $k0, $10
    nop
    nop

    /* One 16KB pair: C=3, D=1, V=1. PageMask[28:13]=0x0003. */
    lui     $t2, 0x0000
    ori     $t2, $t2, PFN_EVEN
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $2
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, PFN_ODD
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $3
    nop
    addiu   $t2, $zero, PAGE_MASK_16K
    mtc0    $t2, $5
    nop
    tlbwr
    nop
    lw      $t0, 0($sp)
    lw      $t1, 4($sp)
    lw      $t2, 8($sp)
    lw      $t3, 12($sp)
    eret
    nop
