    .section .text.init
    .globl _start

_start:
    .set    noreorder
    # Initialize Status Register (enable Coprocessor 0)
    # CU0=1, IE=0 (interrupts disabled initially)
    lui     $8, 0x1000
    mtc0    $8, $12
    nop

    # Initialize Stack Pointer (SP)
    # Point it to the top of SRAM (e.g. 0x0001_0000 = 64KB)
    lui     $sp, 0x0001
    
    # Jump to main in C
    jal     main
    nop
    .set    reorder

    # Infinite loop if main returns
end_loop:
    j       end_loop
    nop

    .section .except_vector, "ax"
    .globl _except_handler
_except_handler:
    # Save caller-saved registers (v0-v1, a0-a3, t0-t9, ra)
    # Total 17 registers * 4 = 68 bytes
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
    sw      $v1,  8($sp)
    sw      $v0,  4($sp)
    
    # Jump to C interrupt handler
    jal     c_interrupt_handler
    nop
    
    # Restore registers
    lw      $v0,  4($sp)
    lw      $v1,  8($sp)
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
