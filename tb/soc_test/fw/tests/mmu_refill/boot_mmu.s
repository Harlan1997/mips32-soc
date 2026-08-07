    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    /* The MMU-enabled prototype image executes through the kseg0 alias. */
    lui     $sp, 0x8000
    ori     $sp, $sp, 0xFFF0
    lui     $t0, 0x1000
    mtc0    $t0, $12              /* CU0=1, interrupts disabled */
    nop
    nop
    nop
    nop
    jal     main
    nop
1:
    b       1b
    nop

    .section .except_vector, "ax"
    .globl _except_handler
_except_handler:
    /* kseg0 keeps this path independent of the faulting useg mapping. */
    addiu   $sp, $sp, -72
    sw      $ra, 68($sp)
    sw      $t9, 64($sp)
    sw      $t8, 60($sp)
    sw      $t7, 56($sp)
    sw      $t6, 52($sp)
    sw      $t5, 48($sp)
    sw      $t4, 44($sp)
    sw      $t3, 40($sp)
    sw      $t2, 36($sp)
    sw      $t1, 32($sp)
    sw      $t0, 28($sp)
    sw      $a3, 24($sp)
    sw      $a2, 20($sp)
    sw      $a1, 16($sp)
    sw      $a0, 12($sp)
    sw      $v1, 8($sp)
    sw      $v0, 4($sp)
    jal     c_interrupt_handler
    nop
    lw      $v0, 4($sp)
    lw      $v1, 8($sp)
    lw      $a0, 12($sp)
    lw      $a1, 16($sp)
    lw      $a2, 20($sp)
    lw      $a3, 24($sp)
    lw      $t0, 28($sp)
    lw      $t1, 32($sp)
    lw      $t2, 36($sp)
    lw      $t3, 40($sp)
    lw      $t4, 44($sp)
    lw      $t5, 48($sp)
    lw      $t6, 52($sp)
    lw      $t7, 56($sp)
    lw      $t8, 60($sp)
    lw      $t9, 64($sp)
    lw      $ra, 68($sp)
    addiu   $sp, $sp, 72
    eret
    nop
