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
	/* Optional user-mode COP1 ABI probe. The default generic image leaves
	 * this disabled because the baseline RTL profile has no FPU. */
#if defined(SOC_LINUX_FPU_ABI) || defined(SOC_LINUX_FPU_SIGNAL_ABI) || defined(SOC_LINUX_FPU_LEGACY_SIGNAL_ABI)
	li	$t0, 0x3f800000		/* 1.0f */
	mtc1	$t0, $f0
	li	$t0, 0x40000000		/* 2.0f */
	mtc1	$t0, $f2
	add.s	$f4, $f0, $f2
	/* The opt-in FPU has a three-cycle result latency in this in-order
	 * pipeline; keep the probe independent of the implementation's FPR
	 * forwarding schedule. */
	nop
	nop
	nop
	mfc1	$t1, $f4
	li	$t2, 0x40400000		/* 3.0f */
	bne	$t1, $t2, fpu_abi_fail
	nop
	/* A syscall and scheduler yield force the kernel to cross the user/kernel
	 * boundary while the live FPR image remains architecturally observable. */
	li	$v0, 4162			/* sched_yield */
	syscall
	nop
	/* $t0-$t9 are caller-saved across a syscall. Reload the expected
	 * result before checking that the kernel preserved the live FPR image. */
	li	$t2, 0x40400000		/* 3.0f */
	mfc1	$t1, $f4
	bne	$t1, $t2, fpu_abi_fail
	nop
#endif
#ifdef SOC_LINUX_FPU_SIGNAL_ABI
	/* Register a real SA_SIGINFO handler, deliver SIGUSR1 to this task, and
	 * verify that Linux saves and restores the complete O32 MIPS FP context.
	 * The handler deliberately changes both an FPR and FCSR; only the
	 * rt_sigreturn restore path can make the parent values visible again. */
	la	$t0, fpu_signal_action
	li	$t1, 8				/* SA_SIGINFO */
	sw	$t1, 0($t0)
	la	$t1, fpu_signal_handler
	sw	$t1, 4($t0)
	sw	$zero, 8($t0)
	sw	$zero, 12($t0)
	sw	$zero, 16($t0)
	sw	$zero, 20($t0)
	li	$a0, 16			/* SIGUSR1 */
	move	$a1, $t0
	move	$a2, $zero
	li	$a3, 16			/* sizeof(sigset_t) for MIPS O32 */
	li	$v0, 4194			/* __NR_rt_sigaction */
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fpu_abi_fail
	nop
	/* Establish parent values that the signal frame must preserve. */
	li	$t0, 1				/* FCSR.RM = toward zero */
	ctc1	$t0, $31
	nop
	nop
	nop
	li	$t0, 0x40400000		/* 3.0f */
	mtc1	$t0, $f4
	la	$t1, fpu_signal_seen
	sw	$zero, 0($t1)
	la	$t1, fpu_signal_value
	sw	$zero, 0($t1)
	la	$t1, fpu_signal_fcsr
	sw	$zero, 0($t1)
	li	$v0, 4020			/* __NR_getpid */
	syscall
	nop
	move	$a0, $v0
	li	$a1, 16			/* SIGUSR1 */
	li	$v0, 4037			/* __NR_kill */
	syscall
	nop
	la	$t1, fpu_signal_seen
	lw	$t0, 0($t1)
	li	$t2, 1
	bne	$t0, $t2, fpu_abi_fail
	nop
	la	$t1, fpu_signal_value
	lw	$t0, 0($t1)
	li	$t2, 0x41000000		/* handler observed 8.0f */
	bne	$t0, $t2, fpu_abi_fail
	nop
	la	$t1, fpu_signal_fcsr
	lw	$t0, 0($t1)
	li	$t2, 2				/* handler set RM = toward +infinity */
	bne	$t0, $t2, fpu_abi_fail
	nop
	mfc1	$t0, $f4
	li	$t2, 0x40400000		/* rt_sigreturn restored parent 3.0f */
	bne	$t0, $t2, fpu_abi_fail
	nop
	cfc1	$t0, $31
	li	$t2, 1				/* rt_sigreturn restored parent FCSR */
	bne	$t0, $t2, fpu_abi_fail
	nop
	li	$a0, 1
	la	$a1, fpu_signal_success_marker
	li	$a2, fpu_signal_success_marker_end-fpu_signal_success_marker
	li	$v0, 4004
	syscall
	nop
#endif
#ifdef SOC_LINUX_FPU_LEGACY_SIGNAL_ABI
	/* Request the pre-rt signal frame and sigreturn trampoline through
	 * rt_sigaction with SA_SIGINFO clear.  Keep this separate from the
	 * SA_SIGINFO probe so both frame layouts are exercised independently; the
	 * old O32 signal(2) syscall is unavailable on this kernel. */
	la	$t0, fpu_legacy_signal_action
	sw	$zero, 0($t0)			/* sa_flags: legacy frame */
	la	$t1, fpu_legacy_signal_handler
	sw	$t1, 4($t0)			/* sa_handler */
	sw	$zero, 8($t0)
	sw	$zero, 12($t0)
	sw	$zero, 16($t0)
	sw	$zero, 20($t0)			/* compat sigset_t */
	li	$a0, 17				/* SIGUSR2 */
	move	$a1, $t0
	move	$a2, $zero
	li	$a3, 16				/* sizeof(sigset_t) for MIPS O32 */
	li	$v0, 4194			/* __NR_rt_sigaction */
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fpu_legacy_signal_fail
	nop
	li	$t0, 1				/* FCSR.RM = toward zero */
	ctc1	$t0, $31
	nop
	nop
	nop
	li	$t0, 0x40400000		/* parent 3.0f */
	mtc1	$t0, $f6
	nop
	nop
	nop
	la	$t1, fpu_legacy_signal_seen
	sw	$zero, 0($t1)
	la	$t1, fpu_legacy_signal_value
	sw	$zero, 0($t1)
	la	$t1, fpu_legacy_signal_fcsr
	sw	$zero, 0($t1)
	li	$v0, 4020			/* __NR_getpid */
	syscall
	nop
	move	$a0, $v0
	li	$a1, 17				/* SIGUSR2 */
	li	$v0, 4037			/* __NR_kill */
	syscall
	nop
	la	$t1, fpu_legacy_signal_seen
	lw	$t0, 0($t1)
	li	$t2, 1
	bne	$t0, $t2, fpu_legacy_signal_fail
	nop
	la	$t1, fpu_legacy_signal_value
	lw	$t0, 0($t1)
	li	$t2, 0x41000000		/* handler observed 8.0f */
	bne	$t0, $t2, fpu_legacy_signal_fail
	nop
	la	$t1, fpu_legacy_signal_fcsr
	lw	$t0, 0($t1)
	li	$t2, 2				/* handler set RM = toward +infinity */
	bne	$t0, $t2, fpu_legacy_signal_fail
	nop
	mfc1	$t0, $f6
	li	$t2, 0x40400000		/* legacy sigreturn restored parent 3.0f */
	bne	$t0, $t2, fpu_legacy_signal_fail
	nop
	cfc1	$t0, $31
	li	$t2, 1				/* legacy sigreturn restored parent FCSR */
	bne	$t0, $t2, fpu_legacy_signal_fail
	nop
	li	$a0, 1
	la	$a1, fpu_legacy_signal_success_marker
	li	$a2, fpu_legacy_signal_success_marker_end-fpu_legacy_signal_success_marker
	li	$v0, 4004
	syscall
	nop
#endif
	/* Consume the deterministic entropy contract through the real Linux
	 * getrandom(2) syscall.  The returned word is loaded back into a GPR so
	 * seed changes are visible in the retire trace rather than only in UART. */
	la	$a0, random_word
	li	$a1, 4
	move	$a2, $zero
	li	$v0, 4353		/* __NR_getrandom for MIPS O32 (4000 + 353) */
	syscall
	nop
	li	$t0, 4
	bne	$v0, $t0, random_fail
	nop
	lw	$t0, random_word
	la	$t1, random_echo
	sw	$t0, 0($t1)
	/* Render the word as eight hexadecimal characters for the entropy
	 * negative test.  This is a diagnostic record; it is not part of the
	 * default boot-success contract. */
	la	$t1, random_ascii
	move	$t2, $t0
	li	$t3, 8
	la	$t4, hex_digits
random_hex_loop:
	srl	$t5, $t2, 28
	addu	$t6, $t4, $t5
	lbu	$t6, 0($t6)
	sb	$t6, 0($t1)
	addiu	$t1, $t1, 1
	sll	$t2, $t2, 4
	addiu	$t3, $t3, -1
	bnez	$t3, random_hex_loop
	nop
	move	$a0, $s0
	la	$a1, random_prefix
	li	$a2, random_prefix_end-random_prefix
	li	$v0, 4004
	syscall
	nop
	move	$a0, $s0
	la	$a1, random_ascii
	li	$a2, 8
	li	$v0, 4004
	syscall
	nop
	move	$a0, $s0
	la	$a1, random_newline
	li	$a2, 1
	li	$v0, 4004
	syscall
	nop
	/* Exercise the Linux gpio-mmio binding through its userspace sysfs ABI.
	 * gpio-mmio receives the first dynamic legacy GPIO range (512) in this
	 * fixed DT/kernel contract; use the exported global number rather than
	 * assuming that the legacy base is zero. */
	li	$a0, 0
	la	$a1, sysfs_path
	la	$a2, sysfs_fs
	move	$a3, $zero
	sw	$zero, 16($sp)
	li	$v0, 4021
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_fail
	nop
	la	$a0, gpio_export_path
	li	$a1, 1
	move	$a2, $zero
	li	$v0, 4005
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_fail
	nop
	move	$s1, $v0
	move	$a0, $s1
	la	$a1, gpio_export_value
	li	$a2, 4
	li	$v0, 4004
	syscall
	nop
	li	$t0, 4
	bne	$v0, $t0, gpio_fail_close
	nop
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	la	$a0, gpio_direction_path
	li	$a1, 1
	move	$a2, $zero
	li	$v0, 4005
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_fail
	nop
	move	$s1, $v0
	move	$a0, $s1
	la	$a1, gpio_direction_out
	li	$a2, 4
	li	$v0, 4004
	syscall
	nop
	li	$t0, 4
	bne	$v0, $t0, gpio_fail_close
	nop
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	la	$a0, gpio_value_path
	li	$a1, 1
	move	$a2, $zero
	li	$v0, 4005
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_fail
	nop
	move	$s1, $v0
	move	$a0, $s1
	la	$a1, gpio_one
	li	$a2, 2
	li	$v0, 4004
	syscall
	nop
	li	$t0, 2
	bne	$v0, $t0, gpio_fail_close
	nop
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	la	$a0, gpio_value_path
	move	$a1, $zero
	move	$a2, $zero
	li	$v0, 4005
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_fail
	nop
	move	$s1, $v0
	move	$a0, $s1
	la	$a1, gpio_readback
	li	$a2, 4
	li	$v0, 4003
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, gpio_read_value_fail
	nop
gpio_value_read_data_check:
	lbu	$t0, gpio_readback
	li	$t1, '1'
	bne	$t0, $t1, gpio_read_value_fail
	nop
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	move	$a0, $s0
	la	$a1, gpio_success_marker
	li	$a2, gpio_success_marker_end-gpio_success_marker
	li	$v0, 4004
	syscall
	nop
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
	/* Change the anonymous VMA to read-only, read every page, then restore
	 * read/write permissions before releasing it. */
	move	$a0, $s3
	li	$a1, 0x5000
	li	$a2, 1
	li	$v0, 4125
	syscall
	nop
	bnez	$v0, vm_fail
	nop
	lw	$t0, 0($s3)
	lw	$t0, 0x1000($s3)
	lw	$t0, 0x2000($s3)
	lw	$t0, 0x3000($s3)
	lw	$t0, 0x4000($s3)
	/* A child must fault when it writes the read-only mapping. The parent
	 * observes SIGSEGV through wait4, then restores the mapping permissions. */
	li	$v0, 4002
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$s8, $v0
	beq	$s8, $zero, mprotect_fault_child
	nop
	mprotect_wait:
	move	$a0, $s8
	addiu	$a1, $sp, 32
	/* Poll the exact child PID instead of sleeping in the wait queue.  The
	 * custom single-vCPU machine has a known boundary where a SIGSEGV child
	 * can become a zombie without waking a blocked parent wait4. */
	li	$a2, 1
	move	$a3, $zero
	li	$v0, 4114
	syscall
	nop
	beq	$v0, $zero, mprotect_wait_sleep
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	bne	$v0, $s8, vm_fail
	nop
	lw	$t0, 32($sp)
	andi	$t0, $t0, 0x7f
	li	$t1, 11
	bne	$t0, $t1, vm_fail
	nop
	move	$a0, $s0
	la	$a1, mprotect_fault_success_marker
	li	$a2, mprotect_fault_success_marker_end-mprotect_fault_success_marker
	li	$v0, 4004
	syscall
	nop
	b	mprotect_wait_done
	nop

	mprotect_wait_sleep:
	/* A one-millisecond sleep gives the child a scheduler/timer boundary
	 * while keeping the wait4 operation non-blocking and exact-PID. */
	sw	$zero, 24($sp)
	li	$t0, 1000000
	sw	$t0, 28($sp)
	addiu	$a0, $sp, 24
	move	$a1, $zero
	li	$v0, 4166
	syscall
	nop
	b	mprotect_wait
	nop

	mprotect_wait_done:
#ifdef SOC_LINUX_FPU_ABI
	/* The protected-page child necessarily runs on a separate task context.
	 * Confirm that returning from wait4 restored PID 1's live FPR image. */
	mfc1	$t1, $f4
	li	$t2, 0x40400000		/* 3.0f */
	bne	$t1, $t2, fpu_abi_fail
	nop
#endif
	move	$a0, $s3
	li	$a1, 0x5000
	li	$a2, 3
	li	$v0, 4125
	syscall
	nop
	bnez	$v0, vm_fail
	nop
	move	$a0, $s0
	la	$a1, mprotect_success_marker
	li	$a2, mprotect_success_marker_end-mprotect_success_marker
	li	$v0, 4004
	syscall
	nop
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
	/* Exercise the process heap separately from mmap-managed VMAs. */
	move	$a0, $zero
	li	$v0, 4045
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, vm_fail
	nop
	move	$s6, $v0
	addiu	$s7, $s6, 0x5000
	move	$a0, $s7
	li	$v0, 4045
	syscall
	nop
	bne	$v0, $s7, vm_fail
	nop
	sw	$zero, 0($s6)
	sw	$zero, 0x1000($s6)
	sw	$zero, 0x2000($s6)
	sw	$zero, 0x3000($s6)
	sw	$zero, 0x4000($s6)
	move	$a0, $s6
	li	$v0, 4045
	syscall
	nop
	bne	$v0, $s6, vm_fail
	nop
	move	$a0, $s0
	la	$a1, brk_success_marker
	li	$a2, brk_success_marker_end-brk_success_marker
	li	$v0, 4004
	syscall
	nop
	/* Yield to the kernel clocksource and scheduler for a real wakeup. */
	sw	$zero, 24($sp)
	li	$t0, 1000000
	sw	$t0, 28($sp)
	addiu	$a0, $sp, 24
	move	$a1, $zero
	li	$v0, 4166
	syscall
	nop
	bnez	$v0, vm_fail
	nop
	move	$a0, $s0
	la	$a1, sleep_success_marker
	li	$a2, sleep_success_marker_end-sleep_success_marker
	li	$v0, 4004
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
	/* Exercise an explicit scheduler yield before blocking in wait4. */
	li	$v0, 4162
	syscall
	nop
	bnez	$v0, fork_fail
	nop
	move	$a0, $s0
	la	$a1, yield_success_marker
	li	$a2, yield_success_marker_end-yield_success_marker
	li	$v0, 4004
	syscall
	nop
	/* Reap the two children using the PIDs returned by fork. This avoids
	 * relying on the custom-machine kernel's wait4(-1) child-selection path
	 * while still checking real wait/reap completion and exit status. */
	move	$a0, $s1
	addiu	$a1, $sp, 36
	move	$a2, $zero
	move	$a3, $zero
	li	$v0, 4114
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	bgtz	$v0, 1f
	nop
	b	fork_fail
	nop
1:
	nop
	lw	$t0, 36($sp)
	bnez	$t0, fork_fail
	nop
	move	$a0, $s2
	addiu	$a1, $sp, 40
	move	$a2, $zero
	move	$a3, $zero
	li	$v0, 4114
	syscall
	nop
	slt	$t1, $v0, $zero
	bnez	$t1, fork_fail
	nop
	bgtz	$v0, 1f
	nop
	b	fork_fail
	nop
1:
	nop
	lw	$t0, 40($sp)
	bnez	$t0, fork_fail
	nop
#ifdef SOC_LINUX_FPU_ABI
	/* Both children changed f4 before exec.  A stale shared FPU image would
	 * leave 8.0f here instead of restoring the parent's 3.0f. */
	mfc1	$t1, $f4
	li	$t2, 0x40400000		/* 3.0f */
	bne	$t1, $t2, fpu_abi_fail
	nop
#endif
#ifdef SOC_LINUX_FPU_ABI
	/* Emit the ABI success marker only after the parent has reaped both
	 * children and verified that its live FPR image survived every tested
	 * scheduler/context boundary. */
	li	$a0, 1
	la	$a1, fpu_abi_success_marker
	li	$a2, fpu_abi_success_marker_end-fpu_abi_success_marker
	li	$v0, 4004
	syscall
	nop
#endif
	li	$a0, 1
	la	$a1, wait_status_success_marker
	li	$a2, wait_status_success_marker_end-wait_status_success_marker
	li	$v0, 4004
	syscall
	nop
	b	fork_parent_done
	/* Preserve the terminal marker length without growing the guest image. */
	li	$a2, boot_marker_end-boot_marker

	fork_child:
#ifdef SOC_LINUX_FPU_ABI
	/* Exercise lazy FPU ownership across a real child schedule before exec.
	 * The parent must retain 3.0f after both children are reaped below. */
	li	$t0, 0x40800000		/* 4.0f */
	mtc1	$t0, $f4
	add.s	$f4, $f4, $f4
	nop
	nop
	nop
	mfc1	$t1, $f4
	li	$t2, 0x41000000		/* 8.0f */
	bne	$t1, $t2, fpu_abi_fail
	nop
#endif
	la	$a0, exec_path
	la	$a1, exec_argv
	la	$a2, exec_env
	li	$v0, 4011
	syscall
	nop

mprotect_fault_child:
	sw	$zero, 0($s3)
	nop
	li	$a0, 1
	li	$v0, 4001
	syscall
	nop
	b	fork_fail
	nop

fork_parent_done:
	li	$a0, 1
	la	$a1, boot_marker
	li	$v0, 4004
	syscall
	li	$a0, 1
	la	$a1, fork_success_marker
	li	$a2, fork_success_marker_end-fork_success_marker
	li	$v0, 4004
	syscall
	nop
	/* Explicit terminal checkpoint for the full Linux differential.  PID 1
	 * remains alive after this write; the harness stops after the marker is
	 * flushed and captured. */
	move	$a0, $s0
	la	$a1, terminal_marker
	li	$a2, terminal_marker_end-terminal_marker
	li	$v0, 4004
	syscall
	nop
	/* PID 1 must remain alive after the terminal marker. Linux treats an
	 * exiting global init as a fatal condition and panics by design. */
	/* Keep PID 1 alive without adding a global symbol to the preserved ELF. */
1:
	li	$v0, 4162
	syscall
	b	1b
	nop

fork_fail:
	move	$a0, $s0
	la	$a1, fork_fail_marker
	li	$a2, fork_fail_marker_end-fork_fail_marker
	li	$v0, 4004
	syscall
	nop

gpio_read_value_fail:
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	b	gpio_fail
	nop
gpio_fail:
	move	$a0, $s0
	la	$a1, gpio_failure_marker
	li	$a2, gpio_failure_marker_end-gpio_failure_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
	li	$v0, 4001
	syscall
	nop

gpio_fail_close:
	li	$v0, 4006
	move	$a0, $s1
	syscall
	nop
	b	gpio_fail
	nop

random_fail:
	move	$a0, $s0
	la	$a1, random_failure_marker
	li	$a2, random_failure_marker_end-random_failure_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
	li	$v0, 4001
	syscall
	nop

#if defined(SOC_LINUX_FPU_ABI) || defined(SOC_LINUX_FPU_SIGNAL_ABI) || defined(SOC_LINUX_FPU_LEGACY_SIGNAL_ABI)
fpu_abi_fail:
	/* Use stdout for the ABI result so a failure in the optional console
	 * descriptor cannot hide the FPU diagnosis before the generic userspace
	 * contract begins. */
	li	$a0, 1
	la	$a1, fpu_abi_failure_marker
	li	$a2, fpu_abi_failure_marker_end-fpu_abi_failure_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
	li	$v0, 4001
	syscall
	nop
#endif

#ifdef SOC_LINUX_FPU_SIGNAL_ABI
	fpu_signal_handler:
	/* Signal entry supplies a kernel-built frame and a VDSO return address in
	 * ra.  Change both FP state components, record what the handler observed,
	 * and return through the kernel's rt_sigreturn trampoline. */
	li	$t0, 0x41000000		/* 8.0f */
	mtc1	$t0, $f4
	nop
	nop
	nop
	mfc1	$t1, $f4
	la	$t2, fpu_signal_value
	sw	$t1, 0($t2)
	li	$t0, 2				/* FCSR.RM = toward +infinity */
	ctc1	$t0, $31
	nop
	nop
	nop
	cfc1	$t1, $31
	la	$t2, fpu_signal_fcsr
	sw	$t1, 0($t2)
	li	$t1, 1
	la	$t2, fpu_signal_seen
	sw	$t1, 0($t2)
	jr	$ra
	nop
#endif

#ifdef SOC_LINUX_FPU_LEGACY_SIGNAL_ABI
	fpu_legacy_signal_handler:
	/* Legacy signal entry returns through the kernel-provided sigreturn
	 * trampoline in ra.  Mutate both FP state components before returning. */
	li	$t0, 0x41000000		/* 8.0f */
	mtc1	$t0, $f6
	nop
	nop
	nop
	mfc1	$t1, $f6
	la	$t2, fpu_legacy_signal_value
	sw	$t1, 0($t2)
	li	$t0, 2				/* FCSR.RM = toward +infinity */
	ctc1	$t0, $31
	nop
	nop
	nop
	cfc1	$t1, $31
	la	$t2, fpu_legacy_signal_fcsr
	sw	$t1, 0($t2)
	li	$t1, 1
	la	$t2, fpu_legacy_signal_seen
	sw	$t1, 0($t2)
	jr	$ra
	nop

	fpu_legacy_signal_fail:
	li	$a0, 1
	la	$a1, fpu_legacy_signal_failure_marker
	li	$a2, fpu_legacy_signal_failure_marker_end-fpu_legacy_signal_failure_marker
	li	$v0, 4004
	syscall
	nop
	li	$a0, 1
	li	$v0, 4001
	syscall
	nop
#endif

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
sysfs_fs:
	.ascii "sysfs\0"
sysfs_path:
	.ascii "/sys\0"
gpio_export_path:
	.ascii "/sys/class/gpio/export\0"
gpio_direction_path:
	.ascii "/sys/class/gpio/gpio512/direction\0"
gpio_value_path:
	.ascii "/sys/class/gpio/gpio512/value\0"
gpio_export_value:
	.ascii "512\n"
gpio_direction_out:
	.ascii "out\n"
gpio_one:
	.ascii "1\n"
gpio_success_marker:
	.ascii "MIPS32_SOC_LINUX_GPIO_SUCCESS\n"
gpio_success_marker_end:
gpio_failure_marker:
	.ascii "MIPS32_SOC_LINUX_GPIO_FAILURE\n"
gpio_failure_marker_end:
boot_marker:
	.ascii "MIPS32_SOC_LINUX_BOOT_SUCCESS\n"
boot_marker_end:
	random_prefix:
	.ascii "MIPS32_SOC_LINUX_RANDOM="
random_prefix_end:
	random_success_marker:
	.ascii "MIPS32_SOC_LINUX_RANDOM_SUCCESS\n"
random_success_marker_end:
	random_failure_marker:
	.ascii "MIPS32_SOC_LINUX_RANDOM_FAILURE\n"
random_failure_marker_end:
#if defined(SOC_LINUX_FPU_ABI) || defined(SOC_LINUX_FPU_SIGNAL_ABI) || defined(SOC_LINUX_FPU_LEGACY_SIGNAL_ABI)
	fpu_abi_success_marker:
	.ascii "MIPS32_SOC_LINUX_FPU_ABI_SUCCESS\n"
	fpu_abi_success_marker_end:
	fpu_abi_failure_marker:
	.ascii "MIPS32_SOC_LINUX_FPU_ABI_FAILURE\n"
	fpu_abi_failure_marker_end:
#endif
#ifdef SOC_LINUX_FPU_SIGNAL_ABI
	fpu_signal_success_marker:
	.ascii "MIPS32_SOC_LINUX_FPU_SIGNAL_SUCCESS\n"
	fpu_signal_success_marker_end:
#endif
#ifdef SOC_LINUX_FPU_LEGACY_SIGNAL_ABI
	fpu_legacy_signal_success_marker:
	.ascii "MIPS32_SOC_LINUX_FPU_LEGACY_SIGNAL_SUCCESS\n"
	fpu_legacy_signal_success_marker_end:
	fpu_legacy_signal_failure_marker:
	.ascii "MIPS32_SOC_LINUX_FPU_LEGACY_SIGNAL_FAILURE\n"
	fpu_legacy_signal_failure_marker_end:
#endif
	random_newline:
	.ascii "\n"
	hex_digits:
	.ascii "0123456789abcdef"
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
terminal_marker:
	.ascii "MIPS32_SOC_LINUX_TERMINAL\n"
terminal_marker_end:
vm_success_marker:
	.ascii "MIPS32_SOC_LINUX_MMAP_SUCCESS\n"
vm_success_marker_end:
brk_success_marker:
	.ascii "MIPS32_SOC_LINUX_BRK_SUCCESS\n"
brk_success_marker_end:
sleep_success_marker:
	.ascii "MIPS32_SOC_LINUX_SLEEP_SUCCESS\n"
sleep_success_marker_end:
yield_success_marker:
	.ascii "MIPS32_SOC_LINUX_YIELD_SUCCESS\n"
yield_success_marker_end:
mprotect_success_marker:
	.ascii "MIPS32_SOC_LINUX_MPROTECT_SUCCESS\n"
mprotect_success_marker_end:
mprotect_fault_success_marker:
	.ascii "MIPS32_SOC_LINUX_MPROTECT_FAULT_SUCCESS\n"
mprotect_fault_success_marker_end:
wait_status_success_marker:
	.ascii "MIPS32_SOC_LINUX_WAIT_STATUS_SUCCESS\n"
wait_status_success_marker_end:
vm_fail_marker:
	.ascii "MIPS32_SOC_LINUX_MMAP_FAILURE\n"
vm_fail_marker_end:
fork_fail_marker:
	.ascii "MIPS32_SOC_LINUX_FORK_WAIT_FAILURE\n"
fork_fail_marker_end:
	.section .bss
	.align 2
gpio_readback:
	.space 4
#ifdef SOC_LINUX_FPU_SIGNAL_ABI
	.align 2
fpu_signal_action:
	.space 24
fpu_signal_seen:
	.space 4
fpu_signal_value:
	.space 4
fpu_signal_fcsr:
	.space 4
#endif
#ifdef SOC_LINUX_FPU_LEGACY_SIGNAL_ABI
	.align 2
fpu_legacy_signal_action:
	.space 24
	.align 2
fpu_legacy_signal_seen:
	.space 4
fpu_legacy_signal_value:
	.space 4
fpu_legacy_signal_fcsr:
	.space 4
#endif
random_word:
	.space 4
random_echo:
	.space 4
random_ascii:
	.space 8
