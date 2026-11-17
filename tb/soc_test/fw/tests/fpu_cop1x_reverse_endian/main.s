    .set noreorder
    .set noat

    .equ UART_TX,  0x40000000
    .equ DATA_K1,  0xA0003000
    .equ MAILBOX,  0xA000FFFC

    .section .text.init, "ax"
    .globl _start
_start:
    /* Kernel bootstrap: CU0 only, interrupts disabled. */
    lui     $t0, 0x1000
    mtc0    $t0, $12
    nop
    nop
    nop
    nop
    lui     $sp, 0x0001
    addiu   $sp, $sp, -16

    j       main_body
    nop

    .section .text, "ax"
    .globl main_body
main_body:

    /* Keep the UART marker outside the user-mode probe. */
    lui     $t0, 0x4000
    addiu   $t1, $zero, 'R'
    sw      $t1, 0($t0)

    /* Initialize four native-order words through the kernel alias. */
    lui     $t8, 0xa000
    ori     $t8, $t8, 0x3000
    lui     $t0, 0xa5a5
    ori     $t0, $t0, 0xa5a5
    sw      $t0, -4($t8)
    lui     $t0, 0x1122
    ori     $t0, $t0, 0x3344
    sw      $t0, 0($t8)
    lui     $t0, 0x5566
    ori     $t0, $t0, 0x7788
    sw      $t0, 4($t8)
    lui     $t0, 0x5a5a
    ori     $t0, $t0, 0x5a5a
    sw      $t0, 8($t8)

    /* CU1|FR|RE and KSU=User.  The data pointer must use kuseg. */
    addiu   $t8, $zero, 0x3000
    addiu   $t9, $zero, 0
    mfc0    $t6, $12
    lui     $t0, 0x2600             /* CU1, FR, RE */
    ori     $t0, $t0, 0x0010       /* KSU=User */
    or      $t6, $t6, $t0
    mtc0    $t6, $12
    nop
    nop
    nop
    nop

    /* LUXC1: reverse-endian phase 0 reads base+4, phase 1 reads base. */
    .word   0x4f194005             /* luxc1 $f8,$t9($t8) */
    nop
    nop
    nop
    mfc1    $t6, $f8
    lui     $t0, 0x5566
    ori     $t0, $t0, 0x7788
    bne     $t6, $t0, user_fail
    nop
    .word   0x446e4000             /* mfhc1 $t6,$f8 */
    lui     $t0, 0x1122
    ori     $t0, $t0, 0x3344
    bne     $t6, $t0, user_fail
    nop

    /* LDXC1 has the same translated two-beat ordering. */
    .word   0x4f194001             /* ldxc1 $f8,$t9($t8) */
    nop
    nop
    nop
    mfc1    $t6, $f8
    lui     $t0, 0x5566
    ori     $t0, $t0, 0x7788
    bne     $t6, $t0, user_fail
    nop
    .word   0x446e4000             /* mfhc1 $t6,$f8 */
    lui     $t0, 0x1122
    ori     $t0, $t0, 0x3344
    bne     $t6, $t0, user_fail
    nop

    /* SUXC1 writes the low FPR word to base+4 and high word to base. */
    lui     $t2, 0xaabb
    ori     $t2, $t2, 0xccdd
    mtc1    $t2, $f10
    lui     $t3, 0xeeff
    ori     $t3, $t3, 0x0011
    .word   0x44eb5000             /* mthc1 $t3,$f10 */
    nop
    nop
    nop
    .word   0x4f19500d             /* suxc1 $f10,$t9($t8) */
    nop
    nop
    nop

    /* LDXC1 after SUXC1 verifies both store beats without ordinary RE loads. */
    .word   0x4f194001             /* ldxc1 $f8,$t9($t8) */
    nop
    nop
    nop
    mfc1    $t6, $f8
    bne     $t6, $t2, user_fail
    nop
    .word   0x446e4000             /* mfhc1 $t6,$f8 */
    bne     $t6, $t3, user_fail
    nop

    /* SDXC1 writes a second known pair in the same reverse order. */
    lui     $t2, 0x1234
    ori     $t2, $t2, 0x5678
    mtc1    $t2, $f10
    lui     $t3, 0x9abc
    ori     $t3, $t3, 0xdef0
    .word   0x44eb5000             /* mthc1 $t3,$f10 */
    nop
    nop
    nop
    .word   0x4f195009             /* sdxc1 $f10,$t9($t8) */
    nop
    nop
    nop

    /* Publish the dirty user cache line before the kernel uncached checks. */
    .word   0xbf150000             /* cache 0x15, 0($t8): Hit_Writeback_Invalidate_D */
    nop
    nop
    nop
    b       user_done
    nop

user_fail:
    addiu   $s0, $zero, 1
user_done:
    /* The handler returns in kernel mode so the normal mailbox is legal. */
    syscall
    nop
    nop

    lui     $t7, 0xa000
    ori     $t7, $t7, 0x3000
    lw      $t6, -4($t7)
    lui     $t0, 0xa5a5
    ori     $t0, $t0, 0xa5a5
    bne     $t6, $t0, kernel_fail
    nop
    lw      $t6, 0($t7)
    lui     $t0, 0x9abc
    ori     $t0, $t0, 0xdef0
    bne     $t6, $t0, kernel_fail
    nop
    lw      $t6, 4($t7)
    lui     $t0, 0x1234
    ori     $t0, $t0, 0x5678
    bne     $t6, $t0, kernel_fail
    nop
    lw      $t6, 8($t7)
    lui     $t0, 0x5a5a
    ori     $t0, $t0, 0x5a5a
    bne     $t6, $t0, kernel_fail
    nop
    bne     $s0, $zero, kernel_fail
    nop

    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xbeef
    sw      $t6, 0($t7)
1:  b       1b
    nop

kernel_fail:
    lui     $t7, 0xa000
    ori     $t7, $t7, 0xfffc
    lui     $t6, 0xdead
    ori     $t6, $t6, 0xdead
    sw      $t6, 0($t7)
2:  b       2b
    nop

    .section .except_vector, "ax"
    .globl _except_handler
_except_handler:
    /* Syscall is the only expected user exception in this probe. */
    mfc0    $k0, $14
    addiu   $k0, $k0, 4
    mtc0    $k0, $14
    mtc0    $zero, $12
    nop
    nop
    nop
    nop
    eret
    nop
