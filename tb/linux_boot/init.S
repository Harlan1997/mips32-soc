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
	/* Exercise anonymous demand paging across five mapped pages. MIPS O32
	 * passes mmap2's fifth and sixth arguments on the user stack. */
	move	$a0, $zero
	li	$a1, 0x5000
	li	$a2, 3
	li	$a3, 0x802
	li	$t0, -1
	sw	$t0, 16($sp)
	sw	$zero, 20($sp)
	li	$v0, 4210
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$s3, $v0
	sw	$zero, 0($s3)
	sw	$zero, 0x1000($s3)
	sw	$zero, 0x2000($s3)
	sw	$zero, 0x3000($s3)
	sw	$zero, 0x4000($s3)
	move	$a0, $s3
	li	$a1, 0x5000
	li	$v0, 4091
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	/* Map one file-backed page and read the ELF header before unmapping it. */
	la	$a0, exec_path
	move	$a1, $zero
	move	$a2, $zero
	li	$v0, 4005
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$s4, $v0
	move	$a0, $zero
	li	$a1, 0x1000
	li	$a2, 1
	li	$a3, 2
	sw	$s4, 16($sp)
	sw	$zero, 20($sp)
	li	$v0, 4210
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$s5, $v0
	lw	$t0, 0($s5)
	move	$a0, $s5
	li	$a1, 0x1000
	li	$v0, 4091
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$a0, $s4
	li	$v0, 4006
	syscall
	nop
	move	$a0, $s0
	la	$a1, vm_success_marker
	li	$a2, vm_success_marker_end-vm_success_marker
	li	$v0, 4004
	syscall
	nop
	/* Fork two children, let each report through the modeled UART, and require
	 * the parent to reap both with wait4 before the final success marker. */
	li	$v0, 4002
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	move	$s1, $v0
	beq	$s1, $zero, fork_child
	nop
	li	$v0, 4002
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	move	$s2, $v0
	beq	$s2, $zero, fork_child
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
	move	$a0, $s2
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

vm_fail:
	move	$a0, $s0
	la	$a1, vm_fail_marker
	li	$a2, vm_fail_marker_end-vm_fail_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
	li	$v0, 4001
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
vm_success_marker:
	.ascii "MIPS32_SOC_LINUX_MMAP_SUCCESS\n"
vm_success_marker_end:
vm_fail_marker:
	.ascii "MIPS32_SOC_LINUX_MMAP_FAILURE\n"
vm_fail_marker_end:
fork_fail_marker:
	.ascii "MIPS32_SOC_LINUX_FORK_WAIT_FAILURE\n"
fork_fail_marker_end:
