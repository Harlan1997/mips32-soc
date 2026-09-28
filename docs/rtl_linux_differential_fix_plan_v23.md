# QEMU Linux Terminal Closure Plan v23

Plan date: 2026-09-28  
Status: `QEMU CLOSED / RTL DIFFERENTIAL OPEN`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v22.md`

This revision changes the immediate execution target from a coupled RTL/QEMU
terminal run to a standalone, compact QEMU closure. The RTL producer currently
Oopses in `__d_lookup_unhash` before userspace reaches its terminal marker, so
it cannot be used as a QEMU acceptance prerequisite. The v22 coupled gate
remains available as a future differential gate and is not relabeled as a
pass.

## 1. QEMU closure objective

Close the declared generic Linux image through the unique
`MIPS32_SOC_LINUX_TERMINAL` userspace marker with the exact kernel, DTB,
Boot ROM/DDR image identity, command line, machine properties, and
deterministic entropy seed. The executable entry point is:

```bash
tb/isa_ref/run_qemu_linux_terminal_closure_gate.sh
```

The gate uses summary-only plugin capture. It records the retired-instruction
count through the terminal event and the complete UART peripheral JSONL, but
does not materialize the roughly 150M-record architectural trace.

The repository-level entry point is `make qemu-system-linux-full-closure-gate`;
`qemu-system-linux-terminal-closure-gate` is an explicit alias. The old
`run_qemu_linux_full_closure_gate.sh` remains the coupled RTL/QEMU experiment
and is not the QEMU-only acceptance gate.

## 2. Acceptance contract

The gate passes only when all of the following hold:

1. `validate_linux_image_identity.py` accepts the supplied image manifest.
2. QEMU runs with the native Linux compatibility property `linux-guest=on`
   and the deterministic `linux-rng-seed` property. The DTB supplies the
   command line by default; `rtl-cp0-identity=on` is reserved for the deferred
   RTL differential phase.
3. QEMU stops because the terminal marker is observed, not because of a
   watchdog, capture limit, or host kill. Plugin status must contain
   `terminal_marker=flushed` and the terminal retire count.
4. Stdout and modeled UART bytes both contain the required marker sequence in
   workload order. The current image order is BOOT, GPIO, protection-fault,
   protection, brk, sleep, mmap, yield, exec, wait-status, fork/wait, then
   TERMINAL. Repeated BOOT/EXEC output is permitted where produced by the
   declared fork/exec workload; the terminal marker must occur exactly once.
5. The structured UART stream is valid JSONL, CRLF transport framing is
   normalized, and no panic/Oops/BUG/failure marker is present.
6. A compact manifest records hashes for the kernel, DTB, image artifacts,
   QEMU, plugin, marker evidence, command line, machine properties, entropy,
   commit, and terminal retire count.

## 3. Evidence and lifecycle

Each run is rooted under `/data/disk/tmp/mips32-soc` and retains:

- `completion_report.md`;
- `qemu_terminal_manifest.json`;
- `marker_evidence.json` and `marker_validation.log`;
- `qemu/qemu_stdout.log`, `qemu/qemu_capture_status.txt`, and
  `qemu/peripheral.jsonl`.

The QEMU capture lifecycle still has a large marker watchdog for deadlock
protection. Watchdog expiry, malformed peripheral records, missing or
duplicated terminal markers, and any capture-limit status fail closed.

## 4. Deferred RTL/differential phase

The following remain open and must not be inferred from QEMU PASS:

- RTL terminal-marker reachability;
- complete RTL/QEMU architectural retire comparison;
- equal trace lengths and first-mismatch ownership;
- blocking versus nonblocking RTL Linux results.

The current RTL blocker is recorded separately: Linux Oops at
`__d_lookup_unhash+0x7c` with `BadVA: 00000004` during the marker preflight.
Once that owner is fixed, v22 can be resumed with the same manifest and the
QEMU compact evidence retained as the reference workload proof.

## 5. Explicit non-claims

This plan does not close RTL Linux, unrestricted Linux, complete MIPS32/
privileged/FPU compliance, SMP shootdown, physical DDR/QSPI/PHY behavior,
U-Boot board support, CDC/RDC/lint/formal signoff, synthesis timing, or ASIC
release readiness.
