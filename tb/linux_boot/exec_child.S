/* SPDX-License-Identifier: GPL-2.0-or-later */
	.set noreorder
	.set noat
	.text
	.globl _start
	.ent _start
_start:
	li	$a0, 1
	la	$a1, exec_marker
	li	$a2, exec_marker_end-exec_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 0
	li	$v0, 4001
	syscall
	nop
	.set at
	.end _start
	.section .rodata
exec_marker:
	.ascii "MIPS32_SOC_LINUX_EXEC_SUCCESS\n"
exec_marker_end:
