# RTL Linux Nonblocking Differential Closure Plan v24

Plan date: 2026-10-29  
Status: `BOUNDED BLOCKING/NONBLOCKING CACHE-PATH DIFFERENTIAL PASS`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v23.md`

This revision records the fresh same-image blocking versus opt-in
nonblocking-L1 Linux differential. It closes the declared 1,200,000-retire
cache-path prefix and does not broaden the result to terminal-marker Linux,
unrestricted ISA/OS compliance, or product signoff.

## 1. Run contract

The gate was run with VCS outside the sandbox after loading the VCS module:

```text
KERNEL=/data/disk/tmp/mips32-soc/full-qemu-marker-build/kernel/vmlinux
RUN_DIR=/data/disk/tmp/mips32-soc/nb-diff-uart-contract-v2-20261029
LINUX_PROFILE=rtl-minimal
RETIRE_COMPARE_RECORDS=1200000
RTL_CYCLE_LIMIT=25000000
SKIP_COVERAGE=1
```

Both RTL runs used the immutable manifest in `shared_image_manifest.txt` and
the hashes in `shared_image.sha256`. The blocking run used the default cache
path; the nonblocking run used:

```text
SOC_L1_NONBLOCKING_ENABLE=1
SOC_CPU_NONBLOCKING_ENABLE=1
SOC_ROB_FIFO_ENABLE=1
SOC_L1_NONBLOCKING_DDR_ENABLE=1
TB_LINUX_DIFF_UART_TIMING=1
```

`TB_LINUX_DIFF_UART_TIMING` is an explicit differential-only peripheral
contract. It makes the TX-empty LSR bits deterministic so cache-dependent APB
arrival cycles cannot change the Linux polling branch. The normal 16550
frame-drain behavior remains the default and is covered separately by the
UART CPU gate.

## 2. Result

Evidence is retained under:

```text
/data/disk/tmp/mips32-soc/nb-diff-uart-contract-v2-20261029/
```

- `completion_report.md` reports `PASS`.
- `trace_compare.log` reports `TRACE_COMPARE_PASS records=1200000 mode=stream-limit`.
- RTL and nonblocking traces each contain exactly 1,200,000 contiguous records.
- The comparator consumed 1,200,000 records from each side, with zero unpaired
  records and zero synchronous exception redirects.
- The normal `uart-cpu-gate` passes with the default UART timing model under
  `/data/disk/tmp/mips32-soc/uart-cpu-contract-20261029`.

## 3. Boundary

This is bounded same-image cache-path evidence through retire 1,200,000. It
does not prove the nonblocking configuration through the Linux terminal marker,
arbitrary Linux workloads, complete MIPS32/privileged/MMU/FPU/OS semantics,
full RTL/QEMU nonblocking differential, coherency beyond the tested path,
physical DDR/QSPI behavior, or product release readiness.
