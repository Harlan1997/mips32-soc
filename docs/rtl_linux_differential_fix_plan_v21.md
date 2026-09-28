# RTL Linux Full-QEMU Closure Plan v21

Plan date: 2026-09-26  
Status: `SUPERSEDED BY v22 / FULL-QEMU TERMINAL-MARKER CLOSURE`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v20.md`

## 1. Objective

Close the declared generic Linux workload all the way from the exact kernel
handoff to its terminal userspace checkpoint in both QEMU and RTL. The final
QEMU/RTL differential must compare every complete architectural retire record
in that run through the terminal checkpoint. A fixed retire count, cycle count,
or host timeout is a watchdog only; it is never a successful terminal
condition.

"Full QEMU" here means the complete declared workload, not unrestricted
arbitrary Linux. The workload is the generic image and `/init` contract that
emits the ordered GPIO, VM, brk, sleep, yield, exec, wait-status, and
fork/wait markers. Full MIPS32/FPU compliance, arbitrary Linux workloads, and
product boot signoff remain separate contracts.

## 2. Terminal contract

The workload must emit a unique final marker after the last required userspace
marker:

```text
MIPS32_SOC_LINUX_TERMINAL\n
```

The terminal event is valid only when all of the following are true:

1. QEMU and RTL use byte-identical kernel, DTB, initramfs, Boot ROM, DDR
   image, command line, RAM size, and deterministic entropy inputs.
2. The required marker sequence, including `MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS`,
   appears exactly once in order before the terminal marker.
3. The terminal marker is fully flushed through the modeled UART. The QEMU
   capture and RTL transcript each record the final UART transaction and the
   retirement that caused it.
4. The QEMU plugin and RTL testbench stop capture because the terminal marker
   was observed. A watchdog expiry, process kill before the marker, simulator
   timeout, record cap, or byte cap is `INCOMPLETE`.
5. The comparator checks every complete record from the declared kernel-entry
   handoff through the terminal retirement. `--allow-golden-prefix`,
   `--truncate-golden-to-rtl`, and arbitrary `--limit` are forbidden for the
   final run.

The terminal marker is a test-workload protocol, not a claim that the Linux
kernel itself has exited. PID 1 remains alive until the harness has captured
the terminal retirement and then the harness may terminate the model cleanly.

## 3. Required implementation changes

### Phase 0: freeze exact inputs

Create a fresh run root under `/data/disk/tmp/mips32-soc` and record hashes for
the kernel, DTB, initramfs contents, Boot ROM, DDR image, QEMU binary/source,
plugin, RTL simulator, RTL source identity, command line, machine properties,
entropy seed, and tool versions. The image manifest must identify the one DTB
consumed by both producers. Any mismatch must fail before simulation.

### Phase 1: add a terminal marker and UART protocol

Add `MIPS32_SOC_LINUX_TERMINAL` to the guest after all existing required
markers. Extend the marker validator with exact-count and ordering checks.
Record the final UART byte index and the architectural retire sequence that
performed the final UART transaction.

### Phase 2: make both producers marker-terminated

Update the QEMU plugin/capture runner to detect the complete terminal byte
sequence, flush the final event/state record, and terminate the QEMU process
group only after the terminal record is durable. Update the RTL testbench to
finish on the same complete UART marker. Keep a large explicit watchdog for
deadlock protection, but classify watchdog termination as failure.

The producer reports must distinguish:

- `TERMINAL_PASS`: marker-triggered stop with clean flush and complete trace;
- `INCOMPLETE`: watchdog, timeout, cap, process kill, malformed record, or
  missing terminal marker;
- `FAIL`: panic, Oops, assertion, nonzero producer status, or marker-order
  violation.

### Phase 3: prove lifecycle and negative paths

Run lifecycle tests for normal terminal completion, missing terminal marker,
truncated marker, wrong marker order, forced plugin failure, and watchdog
expiry. Every negative case must fail closed before a comparison result is
published. Sequence numbers must be contiguous and unique; partial JSONL
records are invalid.

### Phase 4: run the full same-manifest differential

Run QEMU and RTL from the same manifest and compare the complete traces from
the exact kernel-entry handoff through the terminal retirement. Retain at
least 64 records before and after the first mismatch. Classify the first owner
before changing RTL, QEMU, image construction, CP0, MMU, cache, or peripheral
behavior. A matching bounded prefix without a terminal marker is diagnostic
only.

Run the blocking default and opt-in nonblocking configuration separately. The
full-run result must include equal complete-record counts, equal terminal
marker byte streams, equal input hashes, and clean producer lifecycles.

### Phase 5: final closure evidence

After the full run passes, rerun the affected CPU/Linux gates and publish one
compact report containing the manifest digest, producer exit reasons, marker
offsets, terminal retire sequence, compared record count, first-mismatch result,
and residual risks. Required final commands include:

```bash
make focus-differential-checker-test
make linux-differential-contract-test
make linux-image-identity-test
make rtl-frontend-compile
make phase3-complete
```

`make current-contract-signoff` remains a separate RTL contract gate; its
coverage threshold result must be reported honestly and cannot be replaced by
the Linux differential.

## 4. Acceptance checklist

- [ ] v21 manifest contains exact image, tool, source, and entropy hashes.
- [ ] Guest emits the terminal marker after every required marker.
- [ ] QEMU stops only after a flushed terminal UART/retire event.
- [ ] RTL stops only after the same terminal UART/retire event.
- [ ] Missing-marker, truncation, order, plugin-failure, and watchdog tests
      fail closed.
- [ ] Full traces are contiguous, complete, and equal in count through the
      terminal retirement.
- [ ] No prefix truncation or arbitrary record-limit option is used for the
      final comparison.
- [ ] First mismatch is absent or classified with owner-scoped evidence.
- [ ] Blocking and nonblocking results are reported independently.
- [ ] Final reports and hashes are retained under one `/data/disk/tmp` run
      root, with only compact evidence referenced from the repository.

## 5. Explicit non-claims

This plan does not close unrestricted Linux, complete MIPS32/privileged/FPU or
IEEE-754 compliance, arbitrary VM/page-table ownership, SMP shootdown, physical
DDR/QSPI/PHY behavior, U-Boot board support, CDC/RDC/lint/formal signoff,
synthesis timing, or ASIC release readiness.
