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
	/* Fork a child, let it report through the modeled UART, and require the
	 * parent to reap it with wait4 before the final success marker. */
	li	$v0, 4002
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	move	$s1, $v0
	beq	$s1, $zero, fork_child
	nop
	move	$a0, $s1
	move	$a1, $zero
	move	$a2, $zero
	move	$a3, $zero
	li	$v0, 4114
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	b	fork_parent_done
	nop

fork_child:
	la	$a0, exec_path
	la	$a1, exec_argv
	la	$a2, exec_env
	li	$v0, 4011
	syscall
	nop
	b	fork_fail
	nop

fork_parent_done:
	move	$a0, $s0
	la	$a1, boot_marker
	li	$v0, 4004
	syscall
	nop
	move	$a0, $s0
	la	$a1, fork_success_marker
	li	$a2, fork_success_marker_end-fork_success_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 0
	li	$v0, 4001
	syscall
	nop

fork_fail:
	move	$a0, $s0
	la	$a1, fork_fail_marker
	li	$a2, fork_fail_marker_end-fork_fail_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
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
	exec_path:
	.ascii "/bin/vm_child\0"
	.align 2
	exec_argv:
	.word exec_path, 0
	exec_env:
	.word 0
	fork_success_marker:
	.ascii "MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS\n"
fork_success_marker_end:
fork_fail_marker:
	.ascii "MIPS32_SOC_LINUX_FORK_WAIT_FAILURE\n"
fork_fail_marker_end:
