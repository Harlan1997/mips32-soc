    .set    noreorder
    .section .text.init
    .globl  _start

/*
 * Cause a real timer/PIC interrupt while the CPU is executing a branch
 * delay slot.  The delay-slot write is deliberately part of the branch
 * condition: an implementation that commits it before taking the
 * interrupt will choose the wrong path when ERET replays the branch.
 */
_start:
    /* Disable interrupts and unmask the timer source (VIC source 2). */
    mtc0    $zero, $12
    ehb
    lui     $t0, 0x4000
    ori     $t1, $zero, 0x0004
    sw      $t1, 0x4004($t0)         /* PIC_MASK: enable timer source 2 */
    ori     $t1, $zero, 0x0067
    sw      $t1, 0x1004($t0)         /* TIMER_LOAD */
    ori     $t1, $zero, 0x0003
    sw      $t1, 0x1000($t0)         /* TIMER_CTRL: enable + IRQ enable */

    /* IE + IM2, then enter the delay-slot retirement probe. */
    ori     $t1, $zero, 0x0401
    mtc0    $t1, $12
    ehb
    move    $s0, $zero                /* handler sets this on the target BD */
    move    $v0, $zero
delay_probe_branch:
    beqz    $v0, delay_probe_taken
    addiu   $v0, $zero, 10            /* must not commit before an IRQ */
delay_probe_wrong:
    /* ERET saw v0=10: the delay-slot write was committed too early. */
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xdead
    sw      $t1, 0($t0)
1:
    b       1b
    nop
delay_probe_taken:
    bnez    $s0, irq_delay_pass
    nop
    move    $v0, $zero                /* arm the next probe iteration */
    b       delay_probe_branch
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    mfc0    $k0, $13
    mfc0    $k1, $14
    /* Keep the timer running while retrying non-target interrupt windows. */
    lui     $t1, 0x4000
    ori     $t0, $zero, 0x0001
    sw      $t0, 0x100c($t1)         /* TIMER_INTCLR */

    srl     $t0, $k0, 31             /* Cause.BD */
    beqz    $t0, irq_delay_retry
    nop
    lui     $t0, %hi(delay_probe_branch)
    ori     $t0, $t0, %lo(delay_probe_branch)
    bne     $k1, $t0, irq_delay_retry
    nop
    ori     $s0, $zero, 1             /* target delay-slot interrupt observed */

irq_delay_retry:
    eret
    nop

irq_delay_pass:
    lui     $t0, 0x4000
    sw      $zero, 0x1000($t0)       /* TIMER_CTRL */
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
3:
    b       3b
    nop
