    .set    noreorder
    .section .text.init
    .globl  _start

/*
 * Cause a real timer/PIC interrupt while the CPU is executing a branch
 * delay slot.  The handler accepts only Cause.BD=1; this is a SoC-level
 * regression for the early-interrupt EPC selection in mips_cpu.
 */
_start:
    /* Disable interrupts and unmask the timer source (VIC source 2). */
    mtc0    $zero, $12
    ehb
    lui     $t0, 0x4000
    sw      $zero, 0x4004($t0)       /* PIC_MASK: all sources unmasked */
    ori     $t1, $zero, 0x0004
    sw      $t1, 0x1004($t0)         /* TIMER_LOAD */
    ori     $t1, $zero, 0x0003
    sw      $t1, 0x1000($t0)         /* TIMER_CTRL: enable + IRQ enable */

    /* IE + IM2, then enter the loop immediately. */
    ori     $t1, $zero, 0x0401
    mtc0    $t1, $12
    ehb
    ori     $a0, $zero, 0x0100
irq_delay_loop:
    bnez    $a0, irq_delay_loop
    addiu   $a0, $a0, -1

    /* No interrupt or a non-delay-slot interrupt is a failure. */
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)
1:
    b       1b
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    mfc0    $k0, $13
    /* Stop the level source before inspecting/returning. */
    lui     $k1, 0x4000
    sw      $zero, 0x1000($k1)       /* TIMER_CTRL */
    ori     $k1, $zero, 0x0001
    lui     $t0, 0x4000
    sw      $k1, 0x100c($t0)         /* TIMER_INTCLR */

    srl     $k1, $k0, 31             /* Cause.BD */
    bnez    $k1, irq_delay_pass
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0x0002
    sw      $t1, 0($t0)
2:
    b       2b
    nop

irq_delay_pass:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
3:
    b       3b
    nop
