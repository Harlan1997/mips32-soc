.set noreorder
.set noat

.equ DDR_BASE,    0x08008000
.equ MAILBOX,     0xA000FFFC
.equ PASS,        0xDEADBEEF
.equ FAIL,        0xDEADDEAD

.section .text
.globl _start
_start:
    lui     $t7, 0x4000
    addiu   $t6, $zero, 'D'
    sw      $t6, 0($t7)
    lui     $t0, 0x0800
    ori     $t0, $t0, 0x8000
    lui     $t1, 0x1122
    ori     $t1, $t1, 0x3344
    sw      $t1, 0($t0)
    lui     $t2, 0x5566
    ori     $t2, $t2, 0x7788
    sw      $t2, 4($t0)
    lui     $t3, 0x99aa
    ori     $t3, $t3, 0xbbcc
    sw      $t3, 0x20($t0)

    /* Same-line readback checks store merge and a refill response. */
    lw      $t4, 0($t0)
    bne     $t4, $t1, fail
    nop
    lw      $t4, 4($t0)
    bne     $t4, $t2, fail
    nop

    /* A different line exercises the second MSHR/line ownership path. */
    lw      $t4, 0x20($t0)
    bne     $t4, $t3, fail
    nop
    lw      $t4, 0($t0)
    bne     $t4, $t1, fail
    nop

    lui     $t5, 0xA000
    ori     $t5, $t5, 0xFFFC
    lui     $t6, 0xDEAD
    ori     $t6, $t6, 0xBEEF
    sw      $t6, 0($t5)
1:  b       1b
    nop

fail:
    lui     $t5, 0xA000
    ori     $t5, $t5, 0xFFFC
    lui     $t6, 0xDEAD
    ori     $t6, $t6, 0xDEAD
    sw      $t6, 0($t5)
2:  b       2b
    nop
