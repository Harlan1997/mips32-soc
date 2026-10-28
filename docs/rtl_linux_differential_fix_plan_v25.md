# RTL Linux Nonblocking Differential Closure v25

Plan date: 2026-10-29  
Status: `CLOSED / DECLARED 5M-RETIRE CONTRACT`

This record captures the five-million-retire blocking-versus-opt-in-
nonblocking Linux differential. The differential uses an explicit,
opt-in retirement-based CP0 Count contract so cache-path latency cannot
change Count reads between the two configurations. Default cycle-based CP0
Count timing remains unchanged.

## Run

Evidence is retained under:

```text
/data/disk/tmp/mips32-soc/nb-diff-retire-count-5m-20261029/
```

Both simulations used the same seeded Linux image and kernel:

```text
KERNEL=/data/disk/tmp/mips32-soc/full-qemu-marker-build/kernel/vmlinux
LINUX_IMAGE_DIR=/data/disk/tmp/mips32-soc/full-qemu-marker-image-seeded-20261029
LINUX_PROFILE=rtl-minimal
RTL_CYCLE_LIMIT=300000000
LINUX_TIMEOUT_CYCLES=300000000
RETIRE_TRACE_MAX_RECORDS=5000000
```

Both runs used `TB_LINUX_DIFF_UART_TIMING=1` and
`SOC_CP0_RETIRE_COUNT_ENABLE=1`. The nonblocking run also added
`SOC_L1_NONBLOCKING_ENABLE=1`, `SOC_CPU_NONBLOCKING_ENABLE=1`,
`SOC_ROB_FIFO_ENABLE=1`, and `SOC_L1_NONBLOCKING_DDR_ENABLE=1`.

## Result

- Both RTL progress gates passed with simulator status 0.
- Both traces contain exactly 5,000,000 contiguous retire records.
- The optimized schema-1 Linux stream comparator reports
  `TRACE_COMPARE_PASS records=5000000 mode=stream-limit`.
- Both sides have zero unpaired records and zero synchronous redirects.
- The Count reads at the former mismatch region now match, for example
  retire `3,029,604` reads `0x00171d32` on both paths.
- Both traces are gzip-streamed during capture and contain exactly 5,000,000
  contiguous records.

The completion report, image hash manifest, child gate logs, compressed traces,
and comparator log are all retained in the run directory.

## Contract and boundary

`SOC_CP0_RETIRE_COUNT_ENABLE` is defined only by the differential runner and
is disabled by default in `soc_config.vh`. With it enabled, Count advances on
the same `wb_valid` architectural retire pulse in both CPU configurations,
using the existing `SOC_CP0_COUNT_DIV` prescaler. No cache, UART, or default
CP0 timing behavior is changed. This closes the declared 5M-record
blocking/nonblocking Linux differential; unrestricted Linux, full
ISA/MMU/FPU/OS semantics, coherency, and product signoff remain separate.
