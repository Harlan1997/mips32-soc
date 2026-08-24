    .set noreorder
    .section .text.init
    .globl _start

_start:
    # Enable CP0 and select ESS=1 for the exception bank.
    addiu   $t0, $zero, 0x1000
    mtc0    $t0, $12
    nop
    nop
    addiu   $t0, $zero, 0x1000       # SRSCtl.ESS = 1
    mtc0    $t0, $12, 2
    nop
    nop
    addiu   $k0, $zero, 0
    syscall
    nop

    # The handler reports success directly after the nested-entry check.
1:
    b       1b
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    # Both the first and nested entries must retain CSS=1/PSS=0.  EXL is
    # already set on the nested entry, so CP0 must not overwrite the state.
    mfc0    $k1, $12, 2
    andi    $k1, $k1, 0x03ff
    addiu   $t0, $zero, 1
    bne     $k1, $t0, fail_state
    nop

    # k0 is in the current shadow bank. First entry marks it and deliberately
    # raises another synchronous exception; second entry observes the marker.
    bne     $k0, $zero, nested_success
    addiu   $k0, $zero, 0x5a5a
    syscall
    nop

nested_success:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
2:
    b       2b
    nop

fail_state:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 1
    sw      $t1, 0($t0)
3:
    b       3b
    nop
