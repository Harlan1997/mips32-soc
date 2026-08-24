    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    /* Enable CP0 and CU1, then enable only the Divide-by-zero FPE. */
    lui     $t0, 0x3000
    mtc0    $t0, $12
    nop
    nop
    nop
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x0400       /* FCSR Enable[div0] = bit 10 */
    ctc1    $t0, $31
    nop
    nop

    /* 1.0 / 0.0 raises FPE before the destination FPR is written. */
    lui     $t0, 0x3f80
    mtc1    $t0, $f0
    mtc1    $zero, $f2
    div.s   $f4, $f0, $f2
    nop

    /* Reaching this point means the enabled exception was lost. */
    b       fail_main
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    mfc0    $k0, $13
    nop
    nop
    nop
    srl     $k0, $k0, 2
    andi    $k0, $k0, 0x1f
    addiu   $k1, $zero, 15
    bne     $k0, $k1, fail_cause
    nop

    /* Cause[16:12] must report div0 (flag index 3), Flags[6:2] sticky. */
    cfc1    $k0, $31
    nop
    nop
    srl     $k1, $k0, 12
    andi    $k1, $k1, 0x1f
    addiu   $t0, $zero, 8
    bne     $k1, $t0, fail_fcsr_cause
    nop
    srl     $k1, $k0, 2
    andi    $k1, $k1, 0x1f
    addiu   $t0, $zero, 8
    bne     $k1, $t0, fail_fcsr_flags
    nop

    /* FPE is precise: DIV.S must not commit an arbitrary result to FPR4. */
    mfc1    $k0, $f4
    nop
    nop
    bne     $k0, $zero, fail_fpr
    nop

    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
1:  b       1b
    nop

fail_main:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0001
    b       fail_emit
    nop
fail_cause:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0002
    b       fail_emit
    nop
fail_fcsr_cause:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0003
    b       fail_emit
    nop
fail_fcsr_flags:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0004
    b       fail_emit
    nop
fail_fpr:
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x0005
    b       fail_emit
    nop
fail_emit:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    sw      $k1, 0($k0)
2:  b       2b
    nop
