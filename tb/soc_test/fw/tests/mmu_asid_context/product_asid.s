    .set noreorder
    .set noat

    .equ USER_VA,       0x08002000
    .equ PFN_ASID1,     0x08002
    .equ PFN_ASID2,     0x08003
    .equ PATTERN_ASID1, 0x11112222
    .equ PATTERN_ASID2, 0x33334444
    .equ MARK_CONTEXT,  0xC0010001
    .equ MARK_FLUSH,    0xC0010002

    .section .text.init, "ax"
    .globl _start

_start:
    /* Stack and status remain in the direct kseg1 SRAM alias. */
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256
    lui     $t0, 0x1040
    mtc0    $t0, $12
    nop
    nop
    nop
    nop

    /* Reserve TLB index 0 for a wired global entry. */
    mtc0    $zero, $0
    nop
    nop
    nop
    lui     $t0, 0xC000
    mtc0    $t0, $10
    nop
    nop
    nop
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x0017
    mtc0    $t0, $2
    nop
    nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    tlbwi
    nop
    nop
    addiu   $t0, $zero, 1
    mtc0    $t0, $6
    nop
    nop

    /* Context 1: first access takes a refill and maps USER_VA to PFN_ASID1. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lui     $t1, 0x1111
    ori     $t1, $t1, 0x2222
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    /* Context 2: same VA must refill to a different PFN and data page. */
    addiu   $t0, $zero, 2
    mtc0    $t0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lui     $t1, 0x3333
    ori     $t1, $t1, 0x4444
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

    /* Switching back must hit the ASID-1 entry and recover PATTERN_ASID1. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lw      $t2, 0($t0)
    lui     $t1, 0x1111
    ori     $t1, $t1, 0x2222
    bne     $t1, $t2, fail
    nop

    /* Real APB mailbox shootdown: invalidate ASID 1 dynamic entries. */
    jal     do_mailbox_shootdown
    nop

    /* The wired entry must remain usable after the dynamic flush. */
    lui     $t0, 0xC000
    addiu   $t1, $zero, 0x4D
    sw      $t1, 0($t0)

    /* Reusing ASID 1 after shootdown must take a fresh refill. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lw      $t2, 0($t0)
    lui     $t1, 0x1111
    ori     $t1, $t1, 0x2222
    bne     $t1, $t2, fail
    nop

    jal     lease_contract
    nop

    /* Tell the directed testbench which phase completed, then pass. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lui     $t1, 0xC001
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)
    addiu   $t0, $t0, 4
    lui     $t1, 0xC001
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

    .section .text.contract, "ax"
    .globl lease_contract
lease_contract:
    /* Root lease contract: allocate slot 0, reject a stale release, then
       release with generation 0 and verify generation-1 reuse. */
    lui     $t7, 0xC000
    ori     $t7, $t7, 0x9000
    ori     $t0, $zero, 1
    sw      $t0, 40($t7)             /* ROOT_ALLOC at 0x28 */
    lw      $t1, 40($t7)
    lui     $t2, 0x0010
    bne     $t1, $t2, fail
    nop
    lw      $t1, 44($t7)             /* ROOT_GENERATION */
    bne     $t1, $zero, fail
    nop
    sw      $t2, 44($t7)             /* ROOT_RELEASE_ROOT holding */
    lui     $t0, 0x8000
    ori     $t0, $t0, 1              /* stale generation 1 */
    sw      $t0, 48($t7)             /* ROOT_RELEASE */
    lw      $t1, 52($t7)             /* ROOT_EVENT */
    addiu   $t0, $zero, 9
    bne     $t1, $t0, fail
    nop
    addiu   $t0, $zero, 8
    sw      $t0, 56($t7)             /* clear stale-release event */
    sw      $t2, 44($t7)
    lui     $t0, 0x8000              /* valid generation 0 */
    sw      $t0, 48($t7)
    lw      $t1, 52($t7)
    addiu   $t0, $zero, 5
    bne     $t1, $t0, fail
    nop
    sw      $t0, 56($t7)             /* clear root event bits 0 and 2 */
    ori     $t0, $zero, 1
    sw      $t0, 40($t7)
    lw      $t1, 44($t7)
    addiu   $t0, $zero, 1
    bne     $t1, $t0, fail
    nop

    /* Atomic root/ASID leases: fill all four slots, reject a duplicate
       release, then allocate slot 1 again with generation 1. */
    ori     $t0, $zero, 1
    sw      $t0, 60($t7)
    lw      $t1, 0($t7)
    ori     $t2, $zero, 1
    bne     $t1, $t2, fail
    nop
    sw      $t0, 60($t7)
    lw      $t1, 0($t7)
    ori     $t2, $zero, 2
    bne     $t1, $t2, fail
    nop
    sw      $t0, 60($t7)
    lw      $t1, 0($t7)
    ori     $t2, $zero, 3
    bne     $t1, $t2, fail
    nop
    sw      $t0, 60($t7)
    lw      $t1, 0($t7)
    ori     $t2, $zero, 4
    bne     $t1, $t2, fail
    nop
    lui     $t0, 0x0010
    ori     $t0, $t0, 0x1000         /* slot 1 root */
    sw      $t0, 44($t7)
    lui     $t0, 0x8000
    ori     $t0, $t0, 2              /* release ASID 2, generation 0 */
    sw      $t0, 60($t7)
    sw      $t0, 60($t7)             /* duplicate release is stale */
    lw      $t1, 52($t7)
    addiu   $t0, $zero, 13
    bne     $t1, $t0, fail
    nop
    addiu   $t0, $zero, 12
    sw      $t0, 56($t7)
    ori     $t0, $zero, 1
    sw      $t0, 60($t7)
    lw      $t1, 0($t7)
    addiu   $t2, $zero, 0x0102     /* generation 1, ASID 2 */
    bne     $t1, $t2, fail
    nop
    lw      $t1, 44($t7)
    ori     $t0, $zero, 1
    bne     $t1, $t0, fail
    nop

    /* Page-frame lease contract: bounded page allocation, stale release,
       valid release and generation-incremented reuse. */
    ori     $t0, $zero, 1
    sw      $t0, 64($t7)             /* PAGE_ALLOC at 0x40 */
    lw      $t1, 64($t7)
    lui     $t2, 0x0000
    ori     $t2, $t2, 0x6000
    bne     $t1, $t2, fail
    nop
    lw      $t1, 68($t7)             /* PAGE_GENERATION */
    bne     $t1, $zero, fail
    nop
    sw      $t2, 68($t7)             /* PAGE_RELEASE_PAGE holding */
    lui     $t0, 0x8000
    ori     $t0, $t0, 1              /* stale generation 1 */
    sw      $t0, 72($t7)             /* PAGE_RELEASE */
    lw      $t1, 76($t7)             /* PAGE_EVENT */
    addiu   $t0, $zero, 9
    bne     $t1, $t0, fail
    nop
    addiu   $t0, $zero, 8
    sw      $t0, 80($t7)             /* PAGE_EVENT_CLEAR */
    sw      $t2, 68($t7)
    lui     $t0, 0x8000              /* valid generation 0 */
    sw      $t0, 72($t7)
    lw      $t1, 76($t7)
    addiu   $t0, $zero, 5
    bne     $t1, $t0, fail
    nop
    sw      $t0, 80($t7)             /* clear alloc/release events */
    ori     $t0, $zero, 1
    sw      $t0, 64($t7)
    lw      $t1, 64($t7)
    bne     $t1, $t2, fail
    nop
    lw      $t1, 68($t7)
    addiu   $t0, $zero, 1
    bne     $t1, $t0, fail
    nop

    jr      $ra
    nop

    .section .text.shootdown, "ax"
    .globl do_mailbox_shootdown
do_mailbox_shootdown:
    /* Install APB context mapping as the second wired entry. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $0
    nop
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x9000
    mtc0    $t0, $10
    nop
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x0217
    mtc0    $t0, $2
    nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop
    mtc0    $zero, $5
    tlbwi
    nop
    addiu   $t0, $zero, 2
    mtc0    $t0, $6
    nop
    lui     $t7, 0xC000
    ori     $t7, $t7, 0x9000
    ori     $t0, $zero, 1
    sw      $t0, 0($t7)
    ori     $t0, $zero, 0x8002
    sw      $t0, 4($t7)
    ori     $t0, $zero, 1
    sw      $t0, 8($t7)
    sw      $t0, 28($t7)
    lw      $t1, 36($t7)
    andi    $t2, $t1, 1
    beq     $t2, $zero, fail
    nop
    sw      $t2, 32($t7)
    lw      $t1, 36($t7)
    andi    $t2, $t1, 4
    beq     $t2, $zero, fail
    nop
    jr      $ra
    nop

    .section .tlb_refill, "ax"
    .globl _tlb_refill

_tlb_refill:
    /* Preserve temporaries across the software page-table walk. */
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
    nop

    /* Software PTE selection: ASID 1 and 2 use different PFNs. */
    addiu   $t2, $zero, 1
    beq     $t1, $t2, pte_asid1
    nop
    lui     $t2, 0x0000
    ori     $t2, $t2, PFN_ASID2
    b       pte_build
    nop
pte_asid1:
    lui     $t2, 0x0000
    ori     $t2, $t2, PFN_ASID1
pte_build:
    sll     $t2, $t2, 6
    ori     $t2, $t2, 0x0016
    mtc0    $t2, $2
    nop
    nop
    addiu   $t3, $t2, 0x0040
    mtc0    $t3, $3
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    tlbwr
    nop
    nop

    lw      $t0, 0($sp)
    lw      $t1, 4($sp)
    lw      $t2, 8($sp)
    lw      $t3, 12($sp)
    eret
    nop
