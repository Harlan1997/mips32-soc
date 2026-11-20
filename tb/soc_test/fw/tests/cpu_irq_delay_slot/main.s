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
    bnez    $s0, delay_probe_nottaken_setup
    nop
    move    $v0, $zero                /* arm the next probe iteration */
    b       delay_probe_branch
    nop

/* 2. Not-taken conditional branch delay slot: must not commit v0=10 before IRQ. */
delay_probe_nottaken_setup:
    move    $s0, $zero
delay_probe_nottaken_loop:
    move    $v0, $zero
delay_probe_nottaken:
    bnez    $v0, delay_probe_wrong
    addiu   $v0, $zero, 10            /* must not commit before an IRQ */
    beqz    $s0, delay_probe_nottaken_loop
    nop

/* 3. Indirect jump (JR) delay slot: ERET replays JR with BD=1, EPC=delay_probe_jr. */
delay_probe_jr_setup:
    move    $s0, $zero
    lui     $t2, %hi(delay_probe_jr_target)
    ori     $t2, $t2, %lo(delay_probe_jr_target)
delay_probe_jr_loop:
    move    $v0, $zero
delay_probe_jr:
    jr      $t2
    addiu   $v0, $zero, 10
delay_probe_jr_target:
    ori     $t3, $zero, 10
    bne     $v0, $t3, delay_probe_wrong
    nop
    beqz    $s0, delay_probe_jr_loop
    nop

/* 4. Older synchronous exception (SYSCALL) must beat pending timer IRQ. */
sync_beats_irq_setup:
    move    $s1, $zero
    lui     $t0, 0x4000
    ori     $t1, $zero, 0x0040
    sw      $t1, 0x1004($t0)         /* TIMER_LOAD: allow handler to return */
    ori     $t1, $zero, 0x0003
    sw      $t1, 0x1000($t0)
sync_beats_irq_loop:
    syscall 0
    nop
    beqz    $s1, sync_beats_irq_loop
    nop

/* 5. Sequential non-branch PCs must never fabricate Cause.BD on timer IRQ. */
neg_seq_setup:
    move    $s2, $zero
neg_seq_start:
    nop
    nop
    nop
    nop
neg_seq_end:
    beqz    $s2, neg_seq_start
    nop
    b       irq_delay_pass
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    mfc0    $k0, $13
    mfc0    $k1, $14

    /* Check ExcCode = Cause[6:2]. */
    srl     $t0, $k0, 2
    andi    $t0, $t0, 0x1f
    ori     $t1, $zero, 8             /* ExcCode 8 = Syscall */
    bne     $t0, $t1, handle_irq
    nop
    /* Syscall: if IP2 (Cause[10]) is also pending, sync beat async IRQ. */
    srl     $t0, $k0, 10
    andi    $t0, $t0, 1
    beqz    $t0, syscall_ret
    nop
    ori     $s1, $zero, 1
syscall_ret:
    addiu   $k1, $k1, 4
    mtc0    $k1, $14
    ehb
    eret
    nop

handle_irq:
    /* Keep the timer running while retrying non-target interrupt windows. */
    lui     $t1, 0x4000
    ori     $t0, $zero, 0x0001
    sw      $t0, 0x100c($t1)         /* TIMER_INTCLR */

    /* Negative sequential-PC check: [neg_seq_start, neg_seq_end) must have BD=0. */
    lui     $t0, %hi(neg_seq_start)
    ori     $t0, $t0, %lo(neg_seq_start)
    sltu    $t1, $k1, $t0
    bnez    $t1, check_bd_targets
    nop
    lui     $t0, %hi(neg_seq_end)
    ori     $t0, $t0, %lo(neg_seq_end)
    sltu    $t1, $k1, $t0
    beqz    $t1, check_bd_targets
    nop
    srl     $t0, $k0, 31
    bnez    $t0, delay_probe_wrong    /* sequential PC falsely reported Cause.BD=1 */
    nop
    ori     $s2, $zero, 1
    b       irq_delay_retry
    nop

check_bd_targets:
    srl     $t0, $k0, 31             /* Cause.BD */
    beqz    $t0, irq_delay_retry
    nop
    lui     $t0, %hi(delay_probe_branch)
    ori     $t0, $t0, %lo(delay_probe_branch)
    beq     $k1, $t0, mark_bd_hit
    nop
    lui     $t0, %hi(delay_probe_nottaken)
    ori     $t0, $t0, %lo(delay_probe_nottaken)
    beq     $k1, $t0, mark_bd_hit
    nop
    lui     $t0, %hi(delay_probe_jr)
    ori     $t0, $t0, %lo(delay_probe_jr)
    bne     $k1, $t0, irq_delay_retry
    nop
mark_bd_hit:
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
