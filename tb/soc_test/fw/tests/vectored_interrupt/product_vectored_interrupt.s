    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start

_start:
    /* Cause.IV makes accepted BEV=0 interrupts use the EBase vector table. */
    lui     $t0, 0x0080
    mtc0    $t0, $13
    nop
    nop
    nop
    nop
    nop

    /* VS=1 means 32-byte spacing. IP1 therefore selects EBase + 0x220. */
    addiu   $t0, $zero, 0x20
    mtc0    $t0, $12, 1
    nop
    nop
    nop
    nop
    nop

    /* Cause writes cover both IV and software IP fields, so preserve IV while
     * setting IP1 before it becomes globally enabled. */
    lui     $t0, 0x0080
    ori     $t0, $t0, 0x0200
    mtc0    $t0, $13
    nop
    nop
    nop
    nop
    nop

    /* Clear reset BEV/ERL and atomically enable IE plus mask bit IM1. */
    addiu   $t0, $zero, 0x0201
    mtc0    $t0, $12
    nop
    nop
    nop
    nop
    nop

no_interrupt_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

fail_loop:
    b       fail_loop
    nop

    .section .vectored_interrupt, "ax"
    .globl vectored_interrupt_handler

vectored_interrupt_handler:
    /* The product gate completes when this vector fetch is observed. */
vector_loop:
    b       vector_loop
    nop
