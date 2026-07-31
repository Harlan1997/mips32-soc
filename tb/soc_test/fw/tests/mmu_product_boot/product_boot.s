    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start

_start:
    /* Stack uses the writable kseg1 SRAM alias, not the Boot ROM. */
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256

    /* Keep BEV set for the BFC0_0200 refill vector, clear ERL before ERET. */
    lui     $t0, 0x1040
    mtc0    $t0, $12
    nop
    nop
    nop
    nop
    nop

    /* Wired index 0: VA C000_0000/1000 -> PA 4000_0000/1000 (APB). */
    mtc0    $zero, $0
    nop
    nop
    nop
    nop
    nop
    lui     $t0, 0xC000
    mtc0    $t0, $10
    nop
    nop
    nop
    nop
    nop
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x0017
    mtc0    $t0, $2
    nop
    nop
    nop
    nop
    nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop
    nop
    nop
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    nop
    nop
    nop
    tlbwi
    nop
    nop
    nop
    nop
    nop
    addiu   $t0, $zero, 1
    mtc0    $t0, $6
    nop
    nop
    nop
    nop
    nop

    /* A useg DDR access must enter the ROM refill handler once. */
    lui     $t0, 0x0800
    lui     $t1, 0xA5A5
    ori     $t1, $t1, 0x5A5A
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    /* Exercise the wired kseg2 mapping through an uncacheable APB write. */
    lui     $t0, 0xC000
    addiu   $t1, $zero, 0x4D
    sw      $t1, 0($t0)

    /* Existing SoC testbench observes this kseg1 SRAM mailbox directly. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

pass_loop:
    j       pass_loop
    nop

fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

fail_loop:
    j       fail_loop
    nop

    .section .tlb_refill, "ax"
    .globl _tlb_refill

_tlb_refill:
    /* Identity-map the faulting 8KB VA pair and retry with ERET. */
    sw      $t0, 0($sp)
    sw      $t1, 4($sp)
    mfc0    $k0, $8
    nop
    nop
    nop
    lui     $k1, 0xFFFF
    ori     $k1, $k1, 0xE000
    and     $k0, $k0, $k1
    mtc0    $k0, $10
    nop
    nop
    nop
    nop
    nop
    srl     $t0, $k0, 12
    sll     $t0, $t0, 6
    ori     $t0, $t0, 0x001F
    mtc0    $t0, $2
    nop
    nop
    nop
    nop
    nop
    addiu   $t1, $t0, 0x0040
    mtc0    $t1, $3
    nop
    nop
    nop
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    nop
    nop
    nop
    tlbwr
    nop
    nop
    nop
    nop
    nop
    lw      $t0, 0($sp)
    lw      $t1, 4($sp)
    nop
    nop
    nop
    nop
    nop
    eret
    nop
