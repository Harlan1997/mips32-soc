    .set noreorder
    .set noat
    .section .text.init, "ax"
    .globl _start

_start:
    /*
     * Linux installs its exception vectors in the relocated kseg0 image.
     * Product reset leaves BEV/ERL asserted, which is appropriate for the
     * mask-ROM handoff but would route an early kernel trap back into ROM.
     */
    lui     $t1, 0x1000
    mtc0    $t1, $12
    nop
    nop
    nop
    nop
    lui     $t1, 0x8000
    mtc0    $t1, $15, 1
    nop
    nop
    nop
    nop
    /* Linux generic MIPS consumes the UHI firmware argument pair. */
    addiu   $a0, $zero, -2
    lui     $a1, 0x88f0
    ori     $a1, $a1, 0x0000
    move    $a2, $zero
    move    $a3, $zero
    lui     $t0, %hi(KERNEL_ENTRY)
    ori     $t0, $t0, %lo(KERNEL_ENTRY)
    jr      $t0
    nop

boot_hang:
    b       boot_hang
    nop
