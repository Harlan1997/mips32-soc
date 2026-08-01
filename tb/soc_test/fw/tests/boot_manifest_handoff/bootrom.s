    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start

_start:
    /* Read the fixed development manifest through the kseg1 XIP window. */
    lui     $s0, 0xB000
    lw      $t0, 0($s0)
    lui     $t1, 0x534F
    ori     $t1, $t1, 0x4331
    bne     $t0, $t1, boot_fail
    nop

    lw      $t0, 4($s0)
    addiu   $t1, $zero, 1
    bne     $t0, $t1, boot_fail
    nop

    lw      $t0, 8($s0)
    addiu   $t1, $zero, 64
    bne     $t0, $t1, boot_fail
    nop

    lw      $t0, 12($s0)
    addiu   $t1, $zero, 64
    bne     $t0, $t1, boot_fail
    nop

    lw      $s1, 16($s0)
    beq     $s1, $zero, boot_fail
    nop
    andi    $t0, $s1, 3
    bne     $t0, $zero, boot_fail
    nop
    ori     $t0, $zero, 0x8000
    sltu    $t1, $t0, $s1
    bne     $t1, $zero, boot_fail
    nop

    lw      $t0, 20($s0)
    ori     $t1, $zero, 0x1000
    bne     $t0, $t1, boot_fail
    nop

    lw      $t0, 24($s0)
    lui     $t1, 0x8000
    ori     $t1, $t1, 0x1000
    bne     $t0, $t1, boot_fail
    nop

    lw      $t0, 28($s0)
    andi    $t0, $t0, 1
    beq     $t0, $zero, boot_fail
    nop

    lw      $s2, 32($s0)
    addiu   $s5, $s0, 64
    lui     $s3, 0xA000
    ori     $s3, $s3, 0x1000
    addu    $s4, $s1, $zero

copy_payload:
    lw      $t0, 0($s5)
    sw      $t0, 0($s3)
    addiu   $s5, $s5, 4
    addiu   $s3, $s3, 4
    addiu   $s4, $s4, -4
    bne     $s4, $zero, copy_payload
    nop

    /* CRC32/IEEE over the copied little-endian payload. */
    lui     $s3, 0xA000
    ori     $s3, $s3, 0x1000
    addu    $s4, $s1, $zero
    lui     $s6, 0xFFFF
    ori     $s6, $s6, 0xFFFF
    lui     $s7, 0xEDB8
    ori     $s7, $s7, 0x8320

crc_word:
    lw      $t0, 0($s3)
    addiu   $t1, $zero, 4

crc_byte:
    andi    $t2, $t0, 0x00FF
    xor     $s6, $s6, $t2
    addiu   $t3, $zero, 8

crc_bit:
    andi    $t4, $s6, 1
    srl     $s6, $s6, 1
    beq     $t4, $zero, crc_no_xor
    nop
    xor     $s6, $s6, $s7

crc_no_xor:
    addiu   $t3, $t3, -1
    bne     $t3, $zero, crc_bit
    nop
    srl     $t0, $t0, 8
    addiu   $t1, $t1, -1
    bne     $t1, $zero, crc_byte
    nop
    addiu   $s3, $s3, 4
    addiu   $s4, $s4, -4
    bne     $s4, $zero, crc_word
    nop

    nor     $s6, $s6, $zero
    bne     $s6, $s2, boot_fail
    nop

    /* This SRAM marker is the current observable handoff record until the
     * product APB boot-status block exists. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF8
    lui     $t1, 0x4841
    ori     $t1, $t1, 0x4E44
    sw      $t1, 0($t0)

    /* EBase resets to 0x80000000; clear BEV and ERL before entering stage 1. */
    lui     $t0, 0x1000
    mtc0    $t0, $12
    nop
    nop
    nop
    nop
    nop
    lui     $t9, 0x8000
    ori     $t9, $t9, 0x1000
    jr      $t9
    nop

boot_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

boot_fail_loop:
    b       boot_fail_loop
    nop
