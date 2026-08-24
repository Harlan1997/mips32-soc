    .set noreorder
    .set noat

    .equ UART_TX_DATA,  0x40000000
    .equ MAILBOX_ADDR,  0xA000FFFC
    .equ PASS_MARK,     0xDEADBEEF
    .equ FAIL_MARK,     0xDEADDEAD
    .equ FAULT_ADDR,    0x00008000

    .section .text.init, "ax"
    .globl _start
_start:
    /* Keep one observable UART event for the legacy SoC testbench. */
    lui     $t0, 0x4000
    addiu   $t1, $zero, 'E'
    sw      $t1, 0($t0)

    /* This line is selected by the opt-in AXI DDR model fault hook. */
    lui     $t0, 0x0000
    ori     $t0, $t0, 0x8000
    lw      $t1, 0($t0)

    /* The handler skips the faulting load and resumes at this PASS path. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)
pass:
    b       pass
    nop

    .section .except_vector, "ax"
    .align 2
    .globl _except_handler
_except_handler:
    mfc0    $k0, $13
    srl     $k0, $k0, 2
    andi    $k0, $k0, 0x1f
    addiu   $k1, $zero, 30          /* CacheErr */
    bne     $k0, $k1, fail
    nop

    /* ErrorEPC is the precise faulting load; skip it and return from ERL. */
    mfc0    $k0, $30
    addiu   $k0, $k0, 4
    mtc0    $k0, $30
    eret
    nop

    /* The handler returns to the fail branch only if recovery is wrong. */
fail:
    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFFC
    lui     $k1, 0xDEAD
    ori     $k1, $k1, 0xDEAD
    sw      $k1, 0($k0)
1:  b       1b
    nop

    .section .cache_error, "ax"
    .globl _cache_error
_cache_error:
    /* Some link layouts use the dedicated CacheErr section. */
    b       _except_handler
    nop
