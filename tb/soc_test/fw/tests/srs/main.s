    .set noreorder
    .section .text.init
    .globl _start

_start:
    lui     $sp, 0x0001

    # SRSCtl.PSS = 3. CSS remains zero, so ordinary GPR accesses stay in
    # bank zero while RDPGPR/WRPGPR address the selected shadow bank.
    addiu   $t2, $zero, 0x00c0
    mtc0    $t2, $12, 2
    nop
    nop
    nop

    lui     $t1, 0x1122
    ori     $t1, $t1, 0x3344
    # WRPGPR $t0,$t1: shadow[0x08] = current $t1.
    .word   0x41c94000
    nop
    addiu   $t1, $zero, 0
    # RDPGPR $t1,$t0: current $t1 = shadow[0x08].
    .word   0x41484800
    nop
    lui     $t2, 0x1122
    ori     $t2, $t2, 0x3344
    bne     $t1, $t2, fail
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t0)
1:
    b       1b
    nop

fail:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xdead
    sw      $t2, 0($t0)
2:
    b       2b
    nop
