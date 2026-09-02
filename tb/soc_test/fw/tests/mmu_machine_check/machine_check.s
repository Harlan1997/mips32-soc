    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start
_start:
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256

    lui     $t0, %hi(_runtime_general_handler)
    ori     $t0, $t0, %lo(_runtime_general_handler)
    lui     $t1, 0xA000
    ori     $t1, $t1, 0x0180
    lui     $t2, %hi(_runtime_general_handler_end)
    ori     $t2, $t2, %lo(_runtime_general_handler_end)
copy_handler:
    lw      $t3, 0($t0)
    sw      $t3, 0($t1)
    addiu   $t0, $t0, 4
    sltu    $t4, $t0, $t2
    bne     $t4, $zero, copy_handler
    addiu   $t1, $t1, 4

    /* Populate main entry 1 and then fill the D micro-TLB from it. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $0
    nop; nop; nop; nop; nop
    lui     $t0, 0x0800
    mtc0    $t0, $10
    nop; nop; nop; nop; nop
    lui     $t0, 0x0020
    ori     $t0, $t0, 0x001F
    mtc0    $t0, $2
    nop; nop; nop; nop; nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop; nop; nop; nop; nop
    mtc0    $zero, $5
    nop; nop; nop; nop; nop
    tlbwi
    nop; nop; nop; nop; nop
    lui     $t0, 0x0800
    lw      $t2, 0($t0)

    /* Install a second, overlapping architectural entry. */
    addiu   $t1, $zero, 2
    mtc0    $t1, $0
    nop; nop; nop; nop; nop
    lui     $t1, 0x0800
    mtc0    $t1, $10
    nop; nop; nop; nop; nop
    lui     $t1, 0x0030
    ori     $t1, $t1, 0x001F
    mtc0    $t1, $2
    nop; nop; nop; nop; nop
    addiu   $t1, $t1, 0x0040
    mtc0    $t1, $3
    nop; nop; nop; nop; nop
    mtc0    $zero, $5
    nop; nop; nop; nop; nop
    tlbwi
    nop; nop; nop; nop; nop

    /* Clear BEV and let the testbench restore stale fast-path state. */
    lui     $t1, 0x1000
    mtc0    $t1, $12
    nop; nop; nop; nop; nop
    lui     $t0, 0x0800
trigger_machine_check:
    lw      $t2, 0($t0)
    lui     $t3, 0xA000
    ori     $t3, $t3, 0xFFFC
    lui     $t4, 0xDEAD
    ori     $t4, $t4, 0xBEEF
    sw      $t4, 0($t3)
1:
    b       1b
    nop

    .section .runtime_general_handler, "ax"
    .globl _runtime_general_handler
    .globl _runtime_general_handler_end
_runtime_general_handler:
    mfc0    $k0, $13
    nop; nop; nop; nop; nop
    andi    $k0, $k0, 0x007C
    addiu   $k1, $zero, 0x0060
    bne     $k0, $k1, machine_check_fail
    nop
    mfc0    $k0, $14
    nop; nop; nop; nop; nop
    lui     $k1, %hi(trigger_machine_check)
    ori     $k1, $k1, %lo(trigger_machine_check)
    bne     $k0, $k1, machine_check_fail
    nop

    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFFC
    lui     $k1, 0xCAFE
    ori     $k1, $k1, 0x1818
    sw      $k1, 0($k0)
machine_check_done:
    b       machine_check_done
    nop
machine_check_fail:
    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFFC
    lui     $k1, 0xDEAD
    ori     $k1, $k1, 0xDEAD
    sw      $k1, 0($k0)
    b       machine_check_done
    nop
_runtime_general_handler_end:
