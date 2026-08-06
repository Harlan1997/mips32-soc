    .set noreorder
    .set noat

    .equ PFN_BASE,       0x08002
    .equ PROCESS_MARK,   0xC0020001
    .equ SHOOTDOWN_MARK, 0xC0020002

    .section .text.init, "ax"
    .globl _start

_start:
    /* Keep bootstrap state in the direct kseg1 SRAM alias. */
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256
    lui     $t0, 0x1040
    mtc0    $t0, $12
    nop
    nop
    nop
    nop

    /* Reserve TLB index 0 for a wired global mapping. */
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

    /* First pass: allocate four software ASIDs and touch each process page. */
    addiu   $s0, $zero, 1
first_process:
    mtc0    $s0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lui     $t1, 0x1000
    or      $t1, $t1, $s0
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop
    addiu   $s0, $s0, 1
    slti    $t0, $s0, 5
    bne     $t0, $zero, first_process
    nop

    /* Reverse round-robin: all four mappings must remain isolated. */
    addiu   $s0, $zero, 4
second_process:
    beq     $s0, $zero, second_done
    nop
    mtc0    $s0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lui     $t1, 0x1000
    or      $t1, $t1, $s0
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop
    addiu   $s0, $s0, -1
    b       second_process
    nop
second_done:

    /* Shoot down all dynamic entries, retaining only the wired slot. */
    addiu   $s0, $zero, 1
flush_dynamic:
    mtc0    $s0, $0
    nop
    nop
    mtc0    $zero, $10
    mtc0    $zero, $2
    mtc0    $zero, $3
    mtc0    $zero, $5
    nop
    nop
    tlbwi
    nop
    nop
    addiu   $s0, $s0, 1
    slti    $t0, $s0, 64
    bne     $t0, $zero, flush_dynamic
    nop

    /* The wired mapping still works after the dynamic shootdown. */
    lui     $t0, 0xC000
    addiu   $t1, $zero, 0x005A
    sw      $t1, 0($t0)

    /* Second allocation pass: each process must refill after shootdown. */
    addiu   $s0, $zero, 1
third_process:
    mtc0    $s0, $10
    nop
    nop
    nop
    lui     $t0, 0x0800
    lui     $t1, 0x1000
    or      $t1, $t1, $s0
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop
    addiu   $s0, $s0, 1
    slti    $t0, $s0, 5
    bne     $t0, $zero, third_process
    nop

    /* Report the bounded multi-process/context-switch slice. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lui     $t1, 0xC002
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)
    addiu   $t0, $t0, 4
    lui     $t1, 0xC002
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
    /* Preserve temporaries across the software page-table lookup. */
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

    /* Four software PTEs: PFN_BASE + ASID, one physical page per process. */
    lui     $t2, 0x0000
    ori     $t2, $t2, PFN_BASE
    addu    $t2, $t2, $t1
    sll     $t2, $t2, 6
    /* C=3, D=1, V=1: keep this ASID-pressure test on the cacheable DDR
       path; uncached AXI read response behavior is covered separately. */
    ori     $t2, $t2, 0x001e
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
