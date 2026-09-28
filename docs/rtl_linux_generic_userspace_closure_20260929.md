# Generic RTL Linux Userspace Closure

Date: 2026-09-29

Status: `CLOSED` for the declared generic userspace workload. Full
RTL/QEMU architectural differential, arbitrary Linux applications, SMP,
unrestricted ISA/MMU/OS behavior, and physical product signoff remain separate
contracts.

## Gate

The fresh run used the current RTL source, the seeded generic Linux image, and
the terminal-stop gate. All build and simulation output was kept under
`/data/disk/tmp/mips32-soc`.

```text
source /etc/profile.d/modules.sh && module load vcs && \
RUN_DIR=/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded \
KERNEL=/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-build/kernel/vmlinux \
LINUX_IMAGE_DIR=/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-image-seeded \
SKIP_COVERAGE=1 HOST_TIMEOUT=21600s LINUX_TIMEOUT_CYCLES=800000000 \
LINUX_TIMEOUT_NS=8000000000 \
LINUX_RNG_SEED=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
LINUX_TERMINAL_STOP=1 LINUX_REQUIRE_USERSPACE=1 LINUX_PROGRESS_TRACE=1 \
tb/linux_boot/run_rtl_linux_generic_userspace_gate.sh
```

The gate returned `RTL Linux generic userspace gate: PASS`. The simulator
reported `LINUX_TERMINAL_MARKER_REACHED cycle=206355646 retire=70084080` and
`LINUX_TERMINAL_STOP_COMPLETE cycle=206355648`, then exited with status 0.

## Marker Evidence

The authoritative raw guest stream is:

`/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded/sim/uart.transcript`

The normalized stream is:

`/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded/sim/markers.normalized.log`

The required marker sequence is present in order:

```text
BOOT_SUCCESS
GPIO_SUCCESS
MPROTECT_FAULT_SUCCESS
MPROTECT_SUCCESS
BRK_SUCCESS
SLEEP_SUCCESS
MMAP_SUCCESS
EXEC_SUCCESS
YIELD_SUCCESS
WAIT_STATUS_SUCCESS
FORK_WAIT_SUCCESS
TERMINAL
```

`BOOT_SUCCESS` and `EXEC_SUCCESS` are each emitted twice by the declared
fork/exec workload. Every other required marker occurs once, and
`MIPS32_SOC_LINUX_TERMINAL` occurs exactly once. The gate's independent
`VALIDATE_EXISTING_RUN=1` replay also returned PASS.

The runtime log and UART stream contain no `Kernel panic`, `Oops`, `BUG`,
`BadVA`/`BadVAddr`, `REGRESSION_TEST_FAILED`, `SIGABRT`, simulation-bound, or
userspace-failure diagnostic.

## Immutable Inputs

The image identity audit and SoC contract audit both pass:

```text
kernel  f3ef9707ed33450d92e32c2da1ae1e503dfbcc575430db87942b087d115cd735
dtb     cf58ab731c4adbe0889216141f22ac6dfe21c920f3ac8da716d81fad836a36cf
bootrom 85a12627f4cb4255a35e23771f8a1f1fb5fb397863e946a0a62cc469d4cb5956
ddr     b8153ea05bd34175ba91d4286a8d1ab7dc1a0d93a16c460b89a96bb050045348
seed-id a8ae6e6ee929abea3afcfc5258c8ccd6f85273e0d4626d26c7279f3250f77c8e
```

The source-level terminal fix is in
`tb/soc_test/tb_mips_soc.v`: terminal matching is byte-oriented and accepts
the guest UART's CRLF framing, allowing the testbench to finish at the unique
terminal marker instead of running on to the watchdog.

## Evidence Paths

- Generic gate report:
  `/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded/completion_report.md`
- Progress runner log:
  `/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded/progress_runner.log`
- Runtime log:
  `/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-gate-seeded/sim/sim.log`
- Image manifest:
  `/data/disk/tmp/mips32-soc/rtl-linux-userspace-current-image-seeded/image_manifest.txt`
