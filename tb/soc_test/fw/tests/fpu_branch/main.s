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

    /* Exercise non-zero FCC selectors through the real branch path.  The
     * compare destination field selects FCC3..FCC7; the branch rt field
     * selects the same condition and ordinary/likely mode. */
    addiu   $t3, $zero, 0
    .word   0x46020332       /* c.eq.s cc=3, $f0, $f2: true */
    .word   0x450d0001       /* BC1T cc=3 */
    addiu   $t3, $t3, 1      /* taken delay slot */
    addiu   $t3, $t3, 2      /* taken target */
    .word   0x46020432       /* c.eq.s cc=4, $f0, $f4: false */
    .word   0x45100001       /* BC1F cc=4 */
    addiu   $t3, $t3, 4      /* taken delay slot */
    addiu   $t3, $t3, 8      /* taken target */
    .word   0x46020532       /* c.eq.s cc=5, $f0, $f2: true */
    .word   0x45170001       /* BC1TL cc=5 */
    addiu   $t3, $t3, 16     /* taken-likely delay slot */
    addiu   $t3, $t3, 32     /* taken-likely target */
    .word   0x46020632       /* c.eq.s cc=6, $f0, $f4: false */
    .word   0x451a0001       /* BC1FL cc=6 */
    addiu   $t3, $t3, 64     /* annulled when branch is not taken */
    addiu   $t3, $t3, 128    /* post-annul target */
    .word   0x46020732       /* c.eq.s cc=7, $f0, $f2: true */
    .word   0x451d0001       /* BC1T cc=7 */
    addiu   $t3, $t3, 256    /* taken delay slot */
    addiu   $t3, $t3, 512    /* taken target */
    addiu   $t4, $zero, 959  /* 3+12+48+128+768 */
    bne     $t3, $t4, fail
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
