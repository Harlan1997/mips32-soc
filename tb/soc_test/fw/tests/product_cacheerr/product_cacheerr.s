    .set noreorder
    .set noat

    .equ CACHEERR_VA,  0xC000F000
    .equ APB_PFN_EVEN, 0x4000E
    .equ APB_PFN_ODD,  0x4000F
    .equ MARKER_ADDR,  0xA000FFF0
    .equ MAILBOX_ADDR, 0xA000FFFC
    .equ CACHEERR_MARK, 0xCACE0001
    .equ PASS_MARK,     0xDEADBEEF
    .equ FAIL_MARK,     0xDEADDEAD

    .macro cp0_wait
    nop
    nop
    nop
    nop
    .endm

    .section .text.init, "ax"
    .globl _start
_start:
    /* Keep reset/refill execution in the uncached Boot ROM/kseg1 path. */
    lui     $sp, 0xA001
    addiu   $sp, $sp, -256

    /* BEV remains set so CacheErr dispatches to BFC0_0100. */
    lui     $t0, 0x1040
    mtc0    $t0, $12
    cp0_wait

    /* TLB index 0: C000_E000/F000 -> 4000_E000/F000, C=3, D/V/G=1. */
    mtc0    $zero, $0
    cp0_wait
    lui     $t0, 0xC000
    ori     $t0, $t0, 0xE000
    mtc0    $t0, $10
    cp0_wait
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x039F
    mtc0    $t0, $2
    cp0_wait
    lui     $t0, 0x0100
    ori     $t0, $t0, 0x03DF
    mtc0    $t0, $3
    cp0_wait
    mtc0    $zero, $5
    cp0_wait
    tlbwi
    cp0_wait
    addiu   $t0, $zero, 1
    mtc0    $t0, $6
    cp0_wait

    /* The cached refill reaches APB fault injection and must raise CacheErr. */
    lui     $t0, 0xC000
    ori     $t0, $t0, 0xF000
    lw      $t1, 0($t0)

    /* ErrorEPC is advanced by the handler, so execution resumes here. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xBEEF
    sw      $t1, 0($t0)

pass_loop:
    b       pass_loop
    nop

    .section .cache_error, "ax"
    .globl _cache_error
_cache_error:
    /* Verify that this vector is entered only for MIPS CacheErr (30). */
    mfc0    $k0, $13
    cp0_wait
    andi    $k1, $k0, 0x007C
    addiu   $t0, $zero, 0x0078
    bne     $k1, $t0, cacheerr_fail
    nop

    /* Software-visible recovery marker: handler ran exactly once. */
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFF0
    lui     $t1, 0xCACE
    ori     $t1, $t1, 0x0001
    sw      $t1, 0($t0)

    /* Skip the faulting load using ErrorEPC and return through ERL. */
    mfc0    $k0, $30
    cp0_wait
    addiu   $k0, $k0, 4
    mtc0    $k0, $30
    cp0_wait
    eret
    nop

cacheerr_fail:
    lui     $t0, 0xA000
    ori     $t0, $t0, 0xFFFC
    lui     $t1, 0xDEAD
    ori     $t1, $t1, 0xDEAD
    sw      $t1, 0($t0)
fail_loop:
    b       fail_loop
    nop
