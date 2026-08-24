    .set    noreorder
    .section .text.init
    .globl  _start

/*
 * Two software VIC sources are made pending together. Source 9 has higher
 * priority than source 8, so the two exception entries must observe VEC_ID
 * 9 then 8. This intentionally has no stack, .bss, or UART dependency.
 */
_start:
    mtc0    $zero, $12
    ehb
    move    $s0, $zero

    lui     $t0, 0x4000
    addiu   $t1, $zero, 3
    sw      $t1, 0x4120($t0)      /* PRIO[8] */
    addiu   $t1, $zero, 11
    sw      $t1, 0x4124($t0)      /* PRIO[9] */
    ori     $t1, $zero, 0x0300
    sw      $t1, 0x4004($t0)      /* INTR_ENABLE */
    sw      $t1, 0x401c($t0)      /* SOFT */

    ori     $t1, $zero, 0x0401    /* IE plus CP0 IP2 mask */
    mtc0    $t1, $12
    ehb
1:
    sltiu   $t2, $s0, 2
    bnez    $t2, 1b
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
2:
    j       2b
    nop

    .section .except_vector, "ax"
    .align  2
_except_handler:
    lui     $k0, 0x4000
    lw      $k1, 0x4200($k0)      /* accept highest-priority source */
    beq     $s0, $zero, 3f
    nop
    addiu   $t0, $zero, 8
    bne     $k1, $t0, 5f
    nop
    ori     $t1, $zero, 0x0100
    b       4f
    nop
3:
    addiu   $t0, $zero, 9
    bne     $k1, $t0, 5f
    nop
    ori     $t1, $zero, 0x0200
4:
    sw      $t1, 0x4208($k0)      /* ACK active source */
    sw      $t1, 0x4020($k0)      /* SOFT_CLR source */
    addiu   $s0, $s0, 1
    eret
    nop
5:
    /* A wrong VEC_ID must not reach the success mailbox. */
    j       5b
    nop
