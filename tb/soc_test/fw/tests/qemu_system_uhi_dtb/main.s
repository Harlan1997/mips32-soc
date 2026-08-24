    .set noreorder
    .section .text.init
    .globl _start

_start:
    /* MIPS UHI: a0=-2 and a1 points at the FDT in kseg0. */
    addiu   $t0, $zero, -2
    bne     $a0, $t0, fail
    nop

    lui     $t0, 0x8000
    sltu    $t1, $a1, $t0
    bnez    $t1, fail
    nop

    lw      $t2, 0($a1)
    lui     $t0, 0xedfe
    ori     $t0, $t0, 0x0dd0
    bne     $t2, $t0, fail
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)

1:
    j       1b
    nop

fail:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xbaad
    ori     $t1, $t1, 0xf00d
    sw      $t1, 0($t0)
2:
    j       2b
    nop
