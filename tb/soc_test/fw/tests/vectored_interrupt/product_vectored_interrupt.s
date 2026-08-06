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

    /* VS=1 means 32-byte spacing; the VIC source ID selects the VEIC slot. */
    addiu   $t0, $zero, 0x20
    mtc0    $t0, $12, 1
    nop
    nop
    nop
    nop
    nop

    /* Preserve IV and leave pending-source generation to the real VIC path. */
    nop
    nop
    nop
    nop
    nop

    /* Clear reset BEV/ERL and enable IE plus external IP2 (IM2, bit 10). */
    addiu   $t0, $zero, 0x0401
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
