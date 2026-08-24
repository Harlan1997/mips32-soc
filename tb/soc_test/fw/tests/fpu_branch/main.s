    .set noreorder
    .section .text.init
    .globl _start
_start:
    lui     $t9, 0x2000
    mtc0    $t9, $12
    nop
    nop
    nop
    lui     $t0, 0x3f80
    mtc1    $t0, $f0
    mtc1    $t0, $f2
    lui     $t1, 0x4000
    mtc1    $t1, $f4
    addiu   $t2, $zero, 0
    c.eq.s  $f0, $f2
    .word   0x45010001
    addiu   $t2, $t2, 1
    addiu   $t2, $t2, 2
    c.eq.s  $f0, $f4
    .word   0x45010001
    addiu   $t2, $t2, 16
    addiu   $t2, $t2, 4
    .word   0x45000001
    addiu   $t2, $t2, 8
    addiu   $t2, $t2, 16
    c.eq.s  $f0, $f2
    .word   0x45030001
    addiu   $t2, $t2, 32
    addiu   $t2, $t2, 64
    .word   0x45020001
    addiu   $t2, $t2, 128
    addiu   $t2, $t2, 1
    addiu   $t3, $zero, 144
    bne     $t2, $t3, fail
    nop
    lui     $t6, 0xa000
    ori     $t6, $t6, 0xfffc
    lui     $t7, 0xdead
    ori     $t7, $t7, 0xbeef
    sw      $t7, 0($t6)
1:  b       1b
    nop
fail:
    lui     $t6, 0xa000
    ori     $t6, $t6, 0xfffc
    lui     $t7, 0xbad0
    ori     $t7, $t7, 0x0001
    sw      $t7, 0($t6)
2:  b       2b
    nop
