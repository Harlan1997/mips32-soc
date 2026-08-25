/* SPDX-License-Identifier: GPL-2.0-or-later */
	.set noreorder
	.set noat
	.text
	.globl _start
	.ent _start
_start:
	li	$a0, 1
	la	$a1, boot_marker
	li	$a2, boot_marker_end-boot_marker
	li	$v0, 4004
	syscall
	nop
	la	$a0, console_path
	li	$a1, 1
	li	$a2, 0
	li	$v0, 4005
	syscall
	move	$s0, $v0
	/* Exercise Linux user-stack growth across four page boundaries before the
	 * completion marker. The marker is emitted only after all stores retire. */
	sw	$zero, 0($sp)
	addiu	$t0, $sp, -0x1000
	sw	$zero, 0($t0)
	addiu	$t0, $sp, -0x2000
	sw	$zero, 0($t0)
	addiu	$t0, $sp, -0x3000
	sw	$zero, 0($t0)
	move	$a0, $s0
	la	$a1, boot_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 0
	li	$v0, 4001
	syscall
	nop
	.set	at
	.end _start
	.section .rodata
console_path:
	.ascii "/dev/ttyS0\0"
boot_marker:
	.ascii "MIPS32_SOC_LINUX_BOOT_SUCCESS\n"
boot_marker_end:
