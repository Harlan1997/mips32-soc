    .set noreorder
    .set noat

    .equ BOOT_STATUS, 0xC0008000
    .equ BOOT_STAGE,  0xC0008000
    .equ BOOT_FAIL,   0xC0008004
    .equ BOOT_CAUSE,  0xC0008008
    .equ WDT_CTRL,    0xC0007000
    .equ WDT_LOAD,    0xC0007004
    .equ WDT_STATUS,  0xC0007010
    .equ STAGE_HEADER, 0x20
    .equ STAGE_HANDOFF, 0x70
    .equ FAILURE_TIMEOUT, 0xB0070002

    .macro cp0_wait
    nop
    nop
    nop
    nop
    nop
    .endm

    .section .text.init, "ax"
    .globl _start
_start:
    # Install four wired 4-KB-pair entries for the APB window before any
    # status/watchdog access. Product boot cannot use an identity APB map.
    addiu   $t0, $zero, 0
map_apb:
    mtc0    $t0, $0
    cp0_wait
    sll     $t1, $t0, 13
    lui     $t2, 0xC000
    addu    $t2, $t2, $t1
    mtc0    $t2, $10
    cp0_wait
    sll     $t1, $t0, 7
    lui     $t2, 0x0100
    ori     $t2, $t2, 0x0017
    addu    $t2, $t2, $t1
    mtc0    $t2, $2
    cp0_wait
    addiu   $t2, $t2, 0x0040
    mtc0    $t2, $3
    cp0_wait
    mtc0    $zero, $5
    cp0_wait
    tlbwi
    cp0_wait
    addiu   $t0, $t0, 1
    slti    $t1, $t0, 5
    bne     $t1, $zero, map_apb
    nop
    addiu   $t0, $zero, 5
    mtc0    $t0, $6
    cp0_wait

    lui     $t0, 0xC000
    ori     $t0, $t0, 0x8008       # boot-status RESET_CAUSE
    lw      $t1, 0($t0)
    andi    $t2, $t1, 0x0002
    bne     $t2, $zero, after_wdt_reset
    nop

    # First entry must be POR-only. Record stage/code before arming WDT.
    andi    $t2, $t1, 0x0001
    beq     $t2, $zero, boot_fail
    nop
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x8000
    addiu   $t1, $zero, STAGE_HEADER
    sw      $t1, 0($t0)
    lui     $t1, 0xB007
    ori     $t1, $t1, 0x0002
    sw      $t1, 4($t0)

    lui     $t0, 0xC000
    ori     $t0, $t0, 0x7004
    addiu   $t1, $zero, 4
    sw      $t1, 0($t0)
    addiu   $t0, $t0, -4
    addiu   $t1, $zero, 1
    sw      $t1, 0($t0)

wait_for_wdt:
    b       wait_for_wdt
    nop

after_wdt_reset:
    # The always-on block must retain stage, failure and POR|WDT cause.
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x8008
    lw      $t1, 0($t0)
    addiu   $t2, $zero, 3
    bne     $t1, $t2, boot_fail
    nop
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x8000
    lw      $t1, 0($t0)
    addiu   $t2, $zero, STAGE_HEADER
    bne     $t1, $t2, boot_fail
    nop
    lw      $t1, 4($t0)
    lui     $t2, 0xB007
    ori     $t2, $t2, 0x0002
    bne     $t1, $t2, boot_fail
    nop

    # Clear observed state and report the successful second boot.
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x7010
    addiu   $t1, $zero, 1
    sw      $t1, 0($t0)
    lui     $t0, 0xC000
    ori     $t0, $t0, 0x8000
    addiu   $t1, $zero, STAGE_HANDOFF
    sw      $t1, 0($t0)
    sw      $zero, 4($t0)
    addiu   $t0, $t0, 8
    addiu   $t1, $zero, 3
    sw      $t1, 0($t0)

    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

pass_loop:
    b       pass_loop
    nop

boot_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
fail_loop:
    b       fail_loop
    nop
