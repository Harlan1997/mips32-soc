    .set noreorder
    .set noat

    .equ UART_TX_DATA,  0x40000000
    .equ MAILBOX_ADDR,  0xA000FFFC
    .equ PASS_MARK,     0xDEADBEEF
    .equ FAIL_MARK,     0xDEADDEAD
    .equ ERROR_COUNT,   0x00007000

    .section .text.init, "ax"
    .globl _start
_start:
    lui     $t0, 0x4000
    addiu   $t1, $zero, '2'
    sw      $t1, 0($t0)

    /* Issue two independent cache-line loads back-to-back.  Both requests
       must be in flight before either injected response is consumed. */
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x8000
    lui     $t3, 0x0000
    ori     $t3, $t3, 0x9000
    lw      $t1, 0($t0)
    lw      $t2, 0($t3)

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)
1:  b       1b
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    mfc0    $k0, $13
    srl     $k0, $k0, 2
    andi    $k0, $k0, 0x1f
    addiu   $k1, $zero, 30
    bne     $k0, $k1, fail
    nop

    /* Count precise CacheErr entries in SRAM and skip the faulting load. */
    lui     $k0, 0x0000
    ori     $k0, $k0, ERROR_COUNT
    lw      $k1, 0($k0)
    addiu   $k1, $k1, 1
    sw      $k1, 0($k0)
    mfc0    $k0, $30
    addiu   $k0, $k0, 4
    mtc0    $k0, $30
    eret
    nop

fail:
    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFFC
    lui     $k1, 0xDEAD
    ori     $k1, $k1, 0xDEAD
    sw      $k1, 0($k0)
2:  b       2b
    nop
