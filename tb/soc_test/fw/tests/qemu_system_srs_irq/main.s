    .set    noreorder
    .section .text.init
    .globl  _start

/*
 * Drive a real SoC VIC interrupt through Cause.IP2 and verify that the
 * opt-in SRSMap entry for IP2 selects shadow set 3.  The same guest runs on
 * RTL and mips32-soc-ref; no reference-only interrupt injection is used.
 */
_start:
    mtc0    $zero, $12
    ehb

    /* SRSMap[IP2] = 3; SRSMap[0..1] stay zero. */
    lui     $t0, 0
    ori     $t0, $zero, 0x0300
    mtc0    $t0, $12, 3
    ehb

    /* Enable VIC source 4, then raise it through the APB soft source. */
    lui     $t1, 0x4000
    ori     $t2, $zero, 0x0010
    sw      $t2, 0x4004($t1)
    sw      $t2, 0x401c($t1)

    /* IE + IM2.  The VIC output is wired to external Cause.IP2. */
    ori     $t0, $zero, 0x0401
    mtc0    $t0, $12
    ehb
1:
    b       1b
    nop

    .section .except_vector, "ax"
    .align  2
_except_handler:
    /* Interrupt entry must have captured bank 0 and selected bank 3. */
    mfc0    $k0, $12, 2
    andi    $k0, $k0, 0x03ff
    ori     $k1, $zero, 0x0003
    bne     $k0, $k1, 2f
    nop

    /* Clear source 4 before returning from the mapped bank. */
    lui     $k0, 0x4000
    ori     $k1, $zero, 0x0010
    sw      $k1, 0x4020($k0)
    sw      $k1, 0x4208($k0)

    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0xbeef
    sw      $k1, 0($k0)
3:
    b       3b
    nop

2:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 1
    sw      $k1, 0($k0)
4:
    b       4b
    nop
