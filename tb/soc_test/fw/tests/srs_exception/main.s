    .set noreorder
    .section .text.init
    .globl _start

_start:
    # Start in CSS=0 with interrupts disabled and CP0 enabled.
    addiu   $t3, $zero, 0x1000
    mtc0    $t3, $12
    nop
    nop

    # Distinguish the current bank from the exception bank and configure
    # PSS=1, ESS=1.  WRPGPR writes bank 1 while CSS remains bank 0.
    lui     $t0, 0x5566
    ori     $t0, $t0, 0x7788
    lui     $t1, 0x1122
    ori     $t1, $t1, 0x3344
    addiu   $t2, $zero, 0x1040
    mtc0    $t2, $12, 2
    nop
    nop
    .word   0x41c94000       # WRPGPR $t0,$t1 -> bank 1
    nop

    syscall
    nop

    # ERET must restore CSS=0.  The handler left the result of RDPGPR in the
    # exception bank only, so the architectural check here is SRSCtl itself.
    mfc0    $t3, $12, 2
    andi    $t3, $t3, 0x03ff # CSS/PSS fields
    bne     $t3, $zero, fail
    nop

    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xbeef
    sw      $t2, 0($t0)
1:
    b       1b
    nop

fail:
    lui     $t0, 0xa000
    ori     $t0, $t0, 0xfffc
    lui     $t2, 0xdead
    ori     $t2, $t2, 0xdead
    sw      $t2, 0($t0)
2:
    b       2b
    nop

    .section .except_vector, "ax"
    .align  2
    .globl  _except_handler
_except_handler:
    # No stack use: the exception bank has a separately selected GPR image.
    mfc0    $k0, $13
    mfc0    $k1, $12, 2
    andi    $k1, $k1, 0x03ff # CSS=1 and PSS=0 at entry
    addiu   $t3, $zero, 0x0001
    bne     $k1, $t3, handler_fail_entry
    nop
    # PSS now addresses the pre-exception bank; verify its t0 image.
    .word   0x41485000       # RDPGPR $t2,$t0
    nop
    lui     $t3, 0x5566
    ori     $t3, $t3, 0x7788
    bne     $t2, $t3, handler_fail_data
    nop
    mfc0    $k1, $14
    addiu   $k1, $k1, 4
    mtc0    $k1, $14
    nop
    eret
    nop

handler_fail_entry:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0x0001
    sw      $k1, 0($k0)
3:
    b       3b
    nop

handler_fail_data:
    lui     $k0, 0xa000
    ori     $k0, $k0, 0xfffc
    lui     $k1, 0xdead
    ori     $k1, $k1, 0x0002
    sw      $k1, 0($k0)
4:
    b       4b
    nop
