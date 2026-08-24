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
2:
	wait
	b	2b
	nop
	.set	at
	.end _start
	.section .rodata
boot_marker:
	.ascii "MIPS32_SOC_LINUX_BOOT_SUCCESS\n"
boot_marker_end:
