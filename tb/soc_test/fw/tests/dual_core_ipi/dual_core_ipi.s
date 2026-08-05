.set noreorder
.set noat
.section .text
.globl _start

/*
 * Both harts execute this freestanding probe.  The APB window is accessed
 * uncached at its physical fabric address because this gate intentionally
 * does not enable the software-managed MMU. The first transaction targets
 * core 1; the second transaction closes target-0 routing
 * without claiming a separate core-1 APB master yet.
 */
_start:
  lui   $t7,0x4000
  ori   $t7,$t7,0xA000

  /* target=core1, generation=1 */
  lui   $t0,0x0000
  ori   $t0,$t0,0x0101
  sw    $t0,0x20($t7)
  addiu $t0,$zero,1
  sw    $t0,0x24($t7)       /* ASID */
  lui   $t0,0x0001
  ori   $t0,$t0,0x2345
  sw    $t0,0x28($t7)       /* VPN */
  sw    $zero,0x2c($t7)     /* page scope */
  addiu $t0,$zero,1
  sw    $t0,0x30($t7)       /* IPI_SEND */

poll:
  lw    $t1,0x34($t7)       /* status */
  andi  $t2,$t1,0x0004      /* done */
  bne   $t2,$zero,pass
  nop
  andi  $t2,$t1,0x0008      /* timeout */
  bne   $t2,$zero,fail
  nop
  b     poll
  nop

pass:
  /* Clear the first completion and send generation 2 to target core 0. */
  sw    $t1,0x38($t7)
  lui   $t0,0x0000
  ori   $t0,$t0,0x0200
  sw    $t0,0x20($t7)
  lui   $t0,0x0001
  ori   $t0,$t0,0x2346
  sw    $t0,0x28($t7)
  addiu $t0,$zero,1
  sw    $t0,0x30($t7)

poll_reverse:
  lw    $t1,0x34($t7)
  andi  $t2,$t1,0x0004
  bne   $t2,$zero,success
  nop
  andi  $t2,$t1,0x0008
  bne   $t2,$zero,fail
  nop
  b     poll_reverse
  nop

success:
  /* SoC-level timeout injection: hide the target, require sticky timeout. */
  addiu $t0,$zero,1
  sw    $t0,0x3c($t7)
  lui   $t0,0x0000
  ori   $t0,$t0,0x0301
  sw    $t0,0x20($t7)
  addiu $t0,$zero,3
  sw    $t0,0x24($t7)
  addiu $t0,$zero,1
  sw    $t0,0x30($t7)

poll_timeout:
  lw    $t1,0x34($t7)
  andi  $t2,$t1,0x0008
  bne   $t2,$zero,timeout_seen
  nop
  b     poll_timeout
  nop

timeout_seen:
  /* Force a mismatched ACK and require stale-ack plus timeout status. */
  addiu $t0,$zero,4
  sw    $t0,0x3c($t7)
  lui   $t0,0x0000
  ori   $t0,$t0,0x0401
  sw    $t0,0x20($t7)
  addiu $t0,$zero,1
  sw    $t0,0x30($t7)

poll_stale:
  lw    $t1,0x34($t7)
  andi  $t2,$t1,0x0020
  beq   $t2,$zero,poll_stale
  nop
  andi  $t2,$t1,0x0008
  beq   $t2,$zero,poll_stale
  nop
  sw    $t1,0x38($t7)

  /* Hold ACK low, then issue a second send while the first is busy. */
  addiu $t0,$zero,2
  sw    $t0,0x3c($t7)
  lui   $t0,0x0000
  ori   $t0,$t0,0x0501
  sw    $t0,0x20($t7)
  addiu $t0,$zero,1
  sw    $t0,0x30($t7)
  sw    $t0,0x30($t7)

poll_rejected:
  lw    $t1,0x34($t7)
  andi  $t2,$t1,0x0010
  beq   $t2,$zero,poll_rejected
  nop
  andi  $t2,$t1,0x0008
  beq   $t2,$zero,poll_rejected
  nop
  sw    $zero,0x3c($t7)
  addiu $t0,$zero,0x3f
  sw    $t0,0x38($t7)
  /* Reset core 1 only; core 0 must continue to the success mailbox. */
  addiu $t0,$zero,8
  sw    $t0,0x3c($t7)
  lui   $t0,0xA000
  ori   $t0,$t0,0xFFFC
  lui   $t1,0xDEAD
  ori   $t1,$t1,0xBEEF
  sw    $t1,0($t0)
  b     done
  nop

done:
  b     done
  nop

fail:
  lui   $t0,0xA000
  ori   $t0,$t0,0xFFFC
  lui   $t1,0xDEAD
  ori   $t1,$t1,0xDEAD
  sw    $t1,0($t0)
  b     fail
  nop
