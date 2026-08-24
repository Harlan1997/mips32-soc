    .set noreorder
    .text
    .section .text.init
    .globl _start

_start:
    lui     $t1, 0x4000
    addiu   $t2, $zero, 'C'
    sw      $t2, 0($t1)          /* satisfy the SoC smoke UART observation */
    nop
    /* COP1 is disabled after this write; the following MTC1 must trap. */
    mtc0    $zero, $12
    nop
    nop
    lui     $t0, 0x1234
    ori     $t0, $t0, 0x5678
    mtc1    $t0, $f0

    /* Reaching here means the unusable-COP1 exception was lost. */
    b       fail
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    mfc0    $k0, $13
    srl     $k0, $k0, 2
    andi    $k0, $k0, 0x1f
    addiu   $k1, $zero, 11       /* ExcCode=CpU */
    bne     $k0, $k1, fail
    nop

    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
1:  b       1b
    nop

fail:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xbad0
    ori     $k1, $k1, 0x0001
    sw      $k1, 0($k0)
2:  b       2b
    nop
