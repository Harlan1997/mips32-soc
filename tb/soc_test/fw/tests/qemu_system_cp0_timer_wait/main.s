.set    noreorder
.section .text.init
.globl  _start

_start:
    # Disable interrupts while programming Count/Compare.  Use a fixed value
    # far enough ahead of reset for RTL/QEMU's different Count clock domains;
    # MFC0 Count timing is covered by the direct RTL CP0 gate.
    mtc0    $zero, $12
    ehb
    ori     $t0, $zero, 0x4000
    mtc0    $t0, $11
    ehb

    # Enable IE and the timer's default IP7 mask, then suspend.  The handler
    # clears TI by writing Compare before returning from the interrupt.
    lui     $t1, 0x0000
    ori     $t1, $t1, 0x8001       # IM7 | IE
    mtc0    $t1, $12
    ehb
    .word   0x42000020             # WAIT
    nop

    # Reaching this store proves Count/Compare woke WAIT and ERET resumed at
    # the sequential instruction following WAIT.
    lui     $t2, 0xa000
    ori     $t2, $t2, 0xfffc
    lui     $t3, 0xdead
    ori     $t3, $t3, 0xbeef
    sw      $t3, 0($t2)
1:
    j       1b
    nop

.section .except_vector, "ax"
.align  2
.globl  _except_handler
_except_handler:
    # This test has only the CP0 timer enabled.  Clear TI and return.
    mtc0    $zero, $11
    ehb
    eret
    nop
