    .set noreorder
    .set noat

    .section .text.init, "ax"
    .globl _start

_start:
    /* Stack and the relocation target use the writable kseg1 SRAM alias. */
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256

    /* Copy the relocatable general handler into EBase + 0x180. */
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
    addiu   $t1, $t1, 4
    sltu    $t4, $t0, $t2
    bne     $t4, $zero, copy_handler
    nop

    /* TLB index 1: useg VA 0x0800_0000/0x1000 -> identical DDR PA pair.
     * EntryLo0 starts valid but non-dirty so the first store raises Mod. */
    addiu   $t0, $zero, 1
    mtc0    $t0, $0
    nop
    nop
    nop
    nop
    nop
    lui     $t0, 0x0800
    mtc0    $t0, $10
    nop
    nop
    nop
    nop
    nop
    lui     $t0, 0x0020
    ori     $t0, $t0, 0x001B
    mtc0    $t0, $2
    nop
    nop
    nop
    nop
    nop
    addiu   $t0, $t0, 0x0040
    mtc0    $t0, $3
    nop
    nop
    nop
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    nop
    nop
    nop
    tlbwi
    nop
    nop
    nop
    nop
    nop

    /* EBase reset value is 0x8000_0000. Clear BEV and ERL before the store. */
    lui     $t0, 0x1000
    mtc0    $t0, $12
    nop
    nop
    nop
    nop
    nop

    lui     $t0, 0x0800
    lui     $t1, 0xB16B
    ori     $t1, $t1, 0x00B5
_mod_store:
    sw      $t1, 0($t0)
    lw      $t2, 0($t0)
    bne     $t1, $t2, fail
    nop

pass:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

pass_loop:
    b       pass_loop
    nop

fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)

fail_loop:
    b       fail_loop
    nop

    .section .runtime_general_handler, "ax"
    .globl _runtime_general_handler
    .globl _runtime_general_handler_end

_runtime_general_handler:
    /* The copied code deliberately uses only k0/k1, so ERET can retry the
     * interrupted store without restoring ordinary caller registers. */
    mfc0    $k0, $13
    nop
    nop
    nop
    nop
    nop
    andi    $k0, $k0, 0x007C
    addiu   $k1, $zero, 0x0004
    bne     $k0, $k1, handler_fail
    nop

    mfc0    $k0, $8
    nop
    nop
    nop
    nop
    nop
    lui     $k1, 0x0800
    bne     $k0, $k1, handler_fail
    nop

    mfc0    $k0, $14
    nop
    nop
    nop
    nop
    nop
    lui     $k1, %hi(_mod_store)
    ori     $k1, $k1, %lo(_mod_store)
    bne     $k0, $k1, handler_fail
    nop

    /* Rewrite the matched entry with D=1, then retry the original store. */
    addiu   $k0, $zero, 1
    mtc0    $k0, $0
    nop
    nop
    nop
    nop
    nop
    lui     $k0, 0x0800
    mtc0    $k0, $10
    nop
    nop
    nop
    nop
    nop
    lui     $k0, 0x0020
    ori     $k0, $k0, 0x001F
    mtc0    $k0, $2
    nop
    nop
    nop
    nop
    nop
    addiu   $k0, $k0, 0x0040
    mtc0    $k0, $3
    nop
    nop
    nop
    nop
    nop
    mtc0    $zero, $5
    nop
    nop
    nop
    nop
    nop
    tlbwi
    nop
    nop
    nop
    nop
    nop
    eret
    nop

handler_fail:
    lui     $k0, 0xA000
    ori     $k0, $k0, 0xFFFC
    lui     $k1, 0xDEAD
    ori     $k1, $k1, 0xDEAD
    sw      $k1, 0($k0)

handler_fail_loop:
    b       handler_fail_loop
    nop

_runtime_general_handler_end:
