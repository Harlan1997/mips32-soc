    .set noreorder
    .set noat
    .section .text.init, "ax"
    .globl _start

_start:
    /*
     * Match the reset-visible CP0 Status of mips32-soc-ref: BEV and ERL are
     * asserted until the kernel's own startup code takes ownership of the
     * exception vectors.  In particular, Linux uses this value while
     * constructing its initial Status image before the first mtc0.
     */
    lui     $t1, 0x0040
    ori     $t1, $t1, 0x0004
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
    lui     $a1, %hi(DTB_LOAD_VIRTUAL)
    ori     $a1, $a1, %lo(DTB_LOAD_VIRTUAL)
    move    $a2, $zero
    move    $a3, $zero
    lui     $t0, %hi(KERNEL_ENTRY)
    ori     $t0, $t0, %lo(KERNEL_ENTRY)
    jr      $t0
    nop

boot_hang:
    b       boot_hang
    nop
