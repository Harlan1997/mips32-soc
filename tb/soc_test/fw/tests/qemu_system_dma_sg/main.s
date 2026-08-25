    .set noreorder
    .section .text.init
    .globl _start

# A bounded SG-only corpus for RTL/QEMU retire differential.  It exercises
# two real descriptor data moves without the long status-poll loops in the
# broader DMA product firmware.
_start:
    lui     $t7, 0xa000

    la      $t0, src_data
    or      $t0, $t0, $t7
    la      $t1, dst_data
    or      $t1, $t1, $t7
    la      $t2, desc0
    or      $t2, $t2, $t7
    la      $t3, desc1
    or      $t3, $t3, $t7

    sw      $t0, 0($t2)
    sw      $t1, 4($t2)
    addiu   $t4, $zero, 16
    sw      $t4, 8($t2)
    sw      $t3, 12($t2)

    addiu   $t0, $t0, 16
    addiu   $t1, $t1, 16
    sw      $t0, 0($t3)
    sw      $t1, 4($t3)
    sw      $t4, 8($t3)
    sw      $zero, 12($t3)

    lui     $t5, 0x4000
    ori     $t5, $t5, 0x30d0       # DMA v2 channel 2 DESC
    sw      $t2, 0($t5)
    addiu   $t5, $t5, -16          # channel 2 CTRL
    addiu   $t6, $zero, 3          # EN | SG_MODE
    sw      $t6, 0($t5)

    # The RTL DMA performs the two descriptor fetches and data beats over a
    # bounded sequence of bus cycles, while the reference model completes the
    # copy at START.  Use an architectural delay so the single STATUS read
    # observes DONE in both models without hiding a status mismatch.
    addiu   $t2, $zero, 512
delay:
    addiu   $t2, $t2, -1
    bne     $t2, $zero, delay
    nop

    addiu   $t5, $t5, 20           # channel 2 STATUS
    lw      $t6, 0($t5)
    andi    $t6, $t6, 4            # ERR is bit 2 in the architectural status
    bne     $t6, $zero, fail
    nop

    la      $t0, dst_data
    or      $t0, $t0, $t7
    la      $t1, src_data
    or      $t1, $t1, $t7
    addiu   $t2, $zero, 8
check:
    lw      $t3, 0($t0)
    lw      $t4, 0($t1)
    bne     $t3, $t4, fail
    nop
    addiu   $t0, $t0, 4
    addiu   $t1, $t1, 4
    addiu   $t2, $t2, -1
    bne     $t2, $zero, check
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xbeef
    sw      $t1, 0($t0)
done:
    b       done
    nop

fail:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t1, 0xdead
    ori     $t1, $t1, 0xdead
    sw      $t1, 0($t0)
fail_loop:
    b       fail_loop
    nop

    .section .data
    .align  4
src_data:
    .word   0x5a5a0000, 0x5a5a0001, 0x5a5a0002, 0x5a5a0003
    .word   0x5a5a0004, 0x5a5a0005, 0x5a5a0006, 0x5a5a0007
dst_data:
    .word   0, 0, 0, 0, 0, 0, 0, 0
    .align  4
desc0:
    .space  16
desc1:
    .space  16
