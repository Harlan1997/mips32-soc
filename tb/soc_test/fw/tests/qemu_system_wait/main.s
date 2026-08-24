.set    noreorder
.section .text.init
.globl  _start

_start:
    # Establish a clean interrupt state, then pend software interrupt 0.
    mtc0    $zero, $12
    ehb
    ori     $t0, $zero, 0x0100
    mtc0    $t0, $13
    ori     $t0, $zero, 0x0101       # IE | IM0 (matches Cause.SW0)
    mtc0    $t0, $12
    ehb

    # WAIT must retire and suspend until the pending interrupt is accepted.
    .word   0x42000020
    nop

    # Returned from the handler: prove execution resumed after WAIT.
    lui     $t1, 0xa000
    ori     $t1, $t1, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t1)
1:
    j       1b
    nop

.section .except_vector, "ax"
.align  2
.globl  _except_handler
_except_handler:
    # Clear SW0 while EXL is set, count the wakeup, then return.
    mtc0    $zero, $13
    addiu   $s0, $s0, 1
    eret
    nop
