.set noreorder
.set noat

.equ SHARED,     0xA0000000
.equ DATA_OLD,   0xA0009000
.equ VDATA,      0xC0009000
.equ CTRL,       0xA000FFF0
.equ MAILBOX,    0xA000FFFC
.equ VPN2_DATA,  0x60004

.section .text.init, "ax"
.globl _start
_start:
  lui   $sp,0xA001
  addiu $sp,$sp,-256
  lui   $t0,0x1040
  mtc0  $t0,$12
  nop; nop; nop; nop; nop

  /* Each core owns its private TLB; install a wired APB pair and data pair. */
  mtc0  $zero,$0
  nop; nop; nop; nop; nop
  lui   $t0,0xC000
  mtc0  $t0,$10
  nop; nop; nop; nop; nop
  lui   $t0,0x0100
  ori   $t0,$t0,0x0017
  mtc0  $t0,$2
  nop; nop; nop; nop; nop
  addiu $t0,$t0,0x0040
  mtc0  $t0,$3
  nop; nop; nop; nop; nop
  tlbwi
  nop; nop; nop; nop; nop

  addiu $t0,$zero,1
  mtc0  $t0,$0
  nop; nop; nop; nop; nop
  lui   $t0,0xC000
  ori   $t0,$t0,0xA000
  mtc0  $t0,$10
  nop; nop; nop; nop; nop
  lui   $t0,0x0100
  ori   $t0,$t0,0x0297
  mtc0  $t0,$2
  nop; nop; nop; nop; nop
  addiu $t0,$t0,0x0040
  mtc0  $t0,$3
  nop; nop; nop; nop; nop
  tlbwi
  nop; nop; nop; nop; nop
  addiu $t0,$zero,2
  mtc0  $t0,$6
  nop; nop; nop; nop; nop

  /* Index 2 is the page under test: C0009000 -> physical 9000. */
  addiu $t0,$zero,2
  mtc0  $t0,$0
  nop; nop; nop; nop; nop
  lui   $t0,0xC000
  ori   $t0,$t0,0x9000
  mtc0  $t0,$10
  nop; nop
  lui   $t0,0x0000
  ori   $t0,$t0,0x0217
  mtc0  $t0,$2
  nop; nop
  ori   $t0,$t0,0x0040
  mtc0  $t0,$3
  nop; nop
  tlbwi
  nop; nop

  /* Both harts can arrive here in either order, so seed the shared physical
     word before the first translated load on either hart. */
  lui   $t6,0xA000
  ori   $t6,$t6,0x9000
  lui   $t5,0x1111
  ori   $t5,$t5,0x1111
  sw    $t5,0($t6)

  /* CPUNum is the architectural discriminator in the two-core wrapper. */
  .word 0x7c08003b       /* RDHWR t0,$29 */
  bne   $t0,$zero,core1
  nop
  b     core0
  nop

.section .text.body, "ax"
core0:
  lui   $t0,0xA000
  ori   $t0,$t0,0x9000
  lui   $t0,0xA000
  ori   $t0,$t0,0xFFF0
  addiu $t1,$zero,1
  sw    $t1,0($t0)
  addiu $t5,$zero,1

wait_ready:
  lw    $t1,0($t0)
  bne   $t1,$t5,wait_ready
  nop
  lui   $t2,0xA000
  ori   $t2,$t2,0x9000
  lui   $t3,0x2222
  ori   $t3,$t3,0x2222
  sw    $t3,0($t2)

  /* Target core 1, generation 1, page-scope invalidation. */
  lui   $t7,0xC000
  ori   $t7,$t7,0xA000
  ori   $t1,$zero,0x0101
  sw    $t1,0x20($t7)
  ori   $t1,$zero,1
  sw    $t1,0x24($t7)
  lui   $t1,0x0006
  ori   $t1,$t1,0x0004
  sw    $t1,0x28($t7)
  sw    $zero,0x2c($t7)
  ori   $t1,$zero,1
  sw    $t1,0x30($t7)
poll_done:
  lw    $t1,0x34($t7)
  andi  $t2,$t1,4
  bne   $t2,$zero,signal
  nop
  andi  $t2,$t1,8
  bne   $t2,$zero,fail
  nop
  b     poll_done
  nop

signal:
  lui   $t0,0xA000
  ori   $t0,$t0,0xFFF0
  ori   $t1,$zero,2
  sw    $t1,4($t0)
wait_core1:
  lw    $t1,8($t0)
  ori   $t2,$zero,3
  bne   $t1,$t2,wait_core1
  nop
  lui   $t3,0xA000
  ori   $t3,$t3,0xFFFC
  lui   $t4,0xDEAD
  ori   $t4,$t4,0xBEEF
  sw    $t4,0($t3)
  b     done
  nop

core1:
  /* First access establishes the micro-TLB hit that the IPI must remove. */
  lui   $t0,0xC000
  ori   $t0,$t0,0x9000
  lw    $t1,0($t0)
  lui   $t2,0x1111
  ori   $t2,$t2,0x1111
  bne   $t1,$t2,fail
  nop
  lui   $t3,0xA000
  ori   $t3,$t3,0xFFF8
  ori   $t4,$zero,3
  sw    $t4,0($t3)
  lui   $t3,0xA000
  ori   $t3,$t3,0xFFF0
  ori   $t4,$zero,1
  sw    $t4,0($t3)
  addiu $t5,$zero,2
wait_release:
  lw    $t4,4($t3)
  bne   $t4,$t5,wait_release
  nop
  /* This load must refill after the target-1 IPI and see the new value. */
  lw    $t1,0($t0)
  lui   $t2,0x2222
  ori   $t2,$t2,0x2222
  bne   $t1,$t2,fail
  nop
  lui   $t3,0xA000
  ori   $t3,$t3,0xFFFC
  lui   $t4,0xDEAD
  ori   $t4,$t4,0xBEEF
  sw    $t4,0($t3)
done:
  b done
  nop

fail:
  lui   $t3,0xA000
  ori   $t3,$t3,0xFFFC
  lui   $t4,0xDEAD
  ori   $t4,$t4,0xDEAD
  sw    $t4,0($t3)
fail_loop:
  b fail_loop
  nop

.section .tlb_refill, "ax"
.globl _tlb_refill
_tlb_refill:
  /* EntryHi is hardware-updated to the faulting VPN2; retry the same page. */
  addiu $t0,$zero,2
  mtc0  $t0,$0
  nop; nop
  lui   $t0,0x0000
  ori   $t0,$t0,0x0217
  mtc0  $t0,$2
  nop; nop
  ori   $t0,$t0,0x0040
  mtc0  $t0,$3
  nop; nop
  mtc0  $zero,$5
  nop; nop
  tlbwi
  nop; nop
  eret
  nop
