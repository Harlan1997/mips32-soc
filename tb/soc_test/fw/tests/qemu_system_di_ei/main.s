.set    noreorder
.section .text.init
.globl  _start

_start:
    # Start with interrupts disabled and make the old Status observable.
    mtc0    $zero, $12
    ehb
    .word   0x41686000       # di $t0
    bne     $t0, $zero, fail
    nop

    # EI returns the old Status (IE=0), then enables IE.
    .word   0x41696020       # ei $t1
    bne     $t1, $zero, fail
    nop
    mfc0    $t2, $12
    andi    $t2, $t2, 1
    beq     $t2, $zero, fail
    nop

    # DI returns the old Status (IE=1), then disables IE again.
    .word   0x416b6000       # di $t3
    andi    $t3, $t3, 1
    beq     $t3, $zero, fail
    nop
    mfc0    $t4, $12
    andi    $t4, $t4, 1
    bne     $t4, $zero, fail
    nop

    lui     $t5, 0xa000
    ori     $t5, $t5, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xbeef
    sw      $t6, 0($t5)
pass_loop:
    j       pass_loop
    nop

fail:
    lui     $t5, 0xa000
    ori     $t5, $t5, 0xfffc
    lui     $t6, 0xbad0
    ori     $t6, $t6, 0x0001
    sw      $t6, 0($t5)
fail_loop:
    j       fail_loop
    nop
