    .set noreorder
    .set noat

    .equ USER_4K,       0x08000000
    .equ USER_16K,      0x08010000
    .equ USER_64K,      0x08040000
    .equ USER_256K,     0x08100000
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

    /* Each page-size phase uses a distinct ASID so every access must refill. */
    addiu   $t0, $zero, 4
    mtc0    $t0, $10
    nop
    nop
    nop

    /* Run four independent ASID/page-size phases through one small routine. */
    addiu   $t0, $zero, 4
    mtc0    $t0, $10
    nop
    nop
    lui     $a0, 0x0800
    ori     $a1, $zero, 0x1000
    ori     $a2, $zero, 0x165A
    ori     $a3, $zero, 0x265A
    jal     run_phase
    nop
    addiu   $t0, $zero, 5
    mtc0    $t0, $10
    nop
    nop
    lui     $a0, 0x0801
    ori     $a1, $zero, 0x4000
    ori     $a2, $zero, 0x365A
    ori     $a3, $zero, 0x465A
    jal     run_phase
    nop
    addiu   $t0, $zero, 6
    mtc0    $t0, $10
    nop
    nop
    lui     $a0, 0x0804
    lui     $a1, 0x0001
    ori     $a2, $zero, 0x565A
    ori     $a3, $zero, 0x665A
    jal     run_phase
    nop
    /* 256KB: explicitly exercise CP0 EntryHi/EntryLo/PageMask/TLBWI. */
    addiu   $t0, $zero, 7
    mtc0    $t0, $10
    nop
    nop
    addiu   $t0, $zero, 4
    mtc0    $t0, $0
    nop
    lui     $t0, 0x0810
    ori     $t0, $t0, 0x0007
    mtc0    $t0, $10
    nop
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x8000
    sll     $t0, $t0, 6
    ori     $t0, $t0, 0x001E
    mtc0    $t0, $2
    nop
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x8040
    sll     $t0, $t0, 6
    ori     $t0, $t0, 0x001E
    mtc0    $t0, $3
    nop
    lui     $t0, 0x0007
    ori     $t0, $t0, 0xE000
    mtc0    $t0, $5
    nop
    tlbwi
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

run_phase:
    sw      $a2, 0($a0)
    lw      $t2, 0($a0)
    bne     $a2, $t2, fail
    nop
    addu    $t0, $a0, $a1
    sw      $a3, 0($t0)
    lw      $t2, 0($t0)
    bne     $a3, $t2, fail
    nop
    jr      $ra
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

    /* Select the pair and PageMask from the current ASID. */
    andi    $t3, $t1, 0x00FF
    addiu   $t2, $zero, 4
    beq     $t3, $t2, mask_4k
    nop
    addiu   $t2, $zero, 5
    beq     $t3, $t2, mask_16k
    nop
    addiu   $t2, $zero, 6
    beq     $t3, $t2, mask_64k
    nop
    b       mask_256k
    nop

mask_4k:
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8010
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $2
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8020
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $3
    nop
    addiu   $t2, $zero, 0
    mtc0    $t2, $5
    nop
    b       refill_finish
    nop

mask_16k:
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8030
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $2
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8040
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $3
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x6000
    mtc0    $t2, $5
    nop
    b       refill_finish
    nop

mask_64k:
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8050
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $2
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8060
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $3
    nop
    lui     $t2, 0x0001
    ori     $t2, $t2, 0xE000
    mtc0    $t2, $5
    nop
    b       refill_finish
    nop

mask_256k:
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8000
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $2
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x8040
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x001E
    mtc0    $t2, $3
    nop
    lui     $t2, 0x0007
    ori     $t2, $t2, 0xE000
    mtc0    $t2, $5
    nop
refill_finish:
    nop
    tlbwr
    nop
    lw      $t0, 0($sp)
    lw      $t1, 4($sp)
    lw      $t2, 8($sp)
    lw      $t3, 12($sp)
    eret
    nop
