    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    lui     $t0, 0x3000
    mtc0    $t0, $12
    nop
    nop
    nop

    /* DIV.D 1.0 / 0.0: enable only divide-by-zero (FCSR bit 10). */
    ori     $t0, $zero, 0x0400
    ctc1    $t0, $31
    nop
    mtc1    $zero, $f0
    lui     $t0, 0x3ff0
    .word   0x44880800       /* mtc1 $t0,$f1: 1.0 high word */
    mtc1    $zero, $f2
    addu    $t0, $zero, $zero
    .word   0x44881800       /* mtc1 $t0,$f3, with $t0 currently zero */
div0_op:
    div.d   $f4, $f0, $f2
    nop
    b       fail
    nop

invalid_resume:
    /* DIV.D 0.0 / 0.0: enable only invalid (FCSR bit 11). */
    ori     $t0, $zero, 0x0800
    ctc1    $t0, $31
    nop
    mtc1    $zero, $f6
    addu    $t0, $zero, $zero
    .word   0x44883800       /* mtc1 $t0,$f7, with $t0 currently zero */
invalid_op:
    div.d   $f8, $f6, $f6
    nop
    b       fail
    nop

overflow_resume:
    /* max finite double * 2.0: enable only overflow (FCSR bit 9). */
    ori     $t0, $zero, 0x0200
    ctc1    $t0, $31
    nop
    lui     $t0, 0xffff
    ori     $t0, $t0, 0xffff
    mtc1    $t0, $f10
    lui     $t0, 0x7fef
    ori     $t0, $t0, 0xffff
    .word   0x44885800       /* mtc1 $t0,$f11: max finite double high */
    mtc1    $zero, $f12
    lui     $t0, 0x4000
    .word   0x44886800       /* mtc1 $t0,$f13: 2.0 high */
overflow_op:
    mul.d   $f14, $f10, $f12
    nop
    b       fail
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
    bne     $k0, $k1, fail
    nop
    /* This slice is ID-origin.  Use the architectural FCSR Cause field to
     * identify the exception class; EPC propagation is covered separately. */
    cfc1    $k1, $31
    nop
    nop
    srl     $t0, $k1, 12
    andi    $t0, $t0, 0x1f
    addiu   $k1, $zero, 8
    beq     $t0, $k1, check_div0
    nop
    addiu   $k1, $zero, 16
    beq     $t0, $k1, check_invalid
    nop
    addiu   $k1, $zero, 4
    beq     $t0, $k1, check_overflow
    nop
    b       fail
    nop

check_div0:
    addiu   $t0, $zero, 8
    b       check_common
    nop
check_invalid:
    addiu   $t0, $zero, 16
    b       check_common
    nop
check_overflow:
    addiu   $t0, $zero, 4

check_common:
    cfc1    $k1, $31
    nop
    nop
    srl     $t1, $k1, 12
    andi    $t1, $t1, 0x1f
    bne     $t1, $t0, fail
    nop
    srl     $t1, $k1, 2
    andi    $t1, $t1, 0x1f
    bne     $t1, $t0, fail
    nop

    /* No double operation may commit either word of its destination pair. */
    mfc1    $t1, $f4
    nop
    nop
    bne     $t1, $zero, fail
    nop
    .word   0x44092800       /* mfc1 $t1,$f5 */
    nop
    nop
    bne     $t1, $zero, fail
    nop
    mfc1    $t1, $f8
    nop
    nop
    bne     $t1, $zero, fail
    nop
    .word   0x44094800       /* mfc1 $t1,$f9 */
    nop
    nop
    bne     $t1, $zero, fail
    nop
    mfc1    $t1, $f14
    nop
    nop
    bne     $t1, $zero, fail
    nop
    .word   0x44097800       /* mfc1 $t1,$f15 */
    nop
    nop
    bne     $t1, $zero, fail
    nop

    addiu   $k1, $zero, 8
    beq     $t0, $k1, return_invalid
    nop
    addiu   $k1, $zero, 16
    beq     $t0, $k1, return_overflow
    nop
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
1:  b       1b
    nop

return_invalid:
    la      $k0, invalid_resume
    mtc0    $k0, $14
    eret
    nop
return_overflow:
    la      $k0, overflow_resume
    mtc0    $k0, $14
    eret
    nop

fail:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdeaf
    ori     $k1, $k1, 0x00d0
    sw      $k1, 0($k0)
2:  b       2b
    nop
