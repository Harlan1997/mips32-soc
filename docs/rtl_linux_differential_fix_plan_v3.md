# RTL Linux Differential Fix Plan v3

Plan date: 2026-09-21  
Status: `OPEN / EXECUTION REQUIRED`  
Owner: RTL CPU/CP0, Linux boot verification, QEMU reference integration

This is the current execution plan after the first diagnostic and lifecycle
fixes. `docs/rtl_linux_differential_fix_plan_v2.md` remains the historical
record of the earlier work. This document defines the next fix order and the
evidence required before changing the status of generic RTL Linux or full
system differential.

## 1. Current boundary

The following items have fresh implementation or checker coverage, but are
not by themselves generic Linux closure:

| Area | Current evidence | Status |
| --- | --- | --- |
| RTL frontend | 8/8 frontend compile pass | `PASS` |
| BadVAddr owner | 12 captures, 12 commits, 0 squashes | `BOUNDED_PASS` |
| Delay-slot recovery | WB-to-EX and WB-to-ID directed cases pass | `BOUNDED_PASS` |
| QEMU system retire capture | Capture works; complete RTL differential is absent | `CAPTURE_ONLY` |
| QEMU lifecycle | terminal, timeout, record-limit, missing-PC, and forced-failure cases pass | `PASS` |
| Peripheral checker | Positive and mutation tests pass | `CHECKER_PASS` |
| Generic RTL Linux | reaches idle `WAIT`, later timer interrupt wakes it, no `/init` marker | `OPEN` |
| Complete QEMU/RTL retire differential | no current-source full-record gate | `OPEN` |

The current generic Linux failure is centered around the CP0 Count/Compare,
interrupt acceptance, `WAIT` wakeup, and return-to-idle sequence:

1. RTL reaches the idle path near `r4k_wait`.
2. `WAIT` retires around cycle `51,953,211`.
3. A timer interrupt is accepted around cycle `52,120,311`.
4. RTL returns to the idle `WAIT` path and does not reach the generic `/init`
   userspace markers.
5. The repeated terminal PC is approximately `0x88a55d3c`.

This was the initial working hypothesis, not a proven single RTL defect. A
fresh current-source bounded run with Count/Compare and timer-heartbeat
instrumentation has now refined it:

| Observation | Fresh evidence | Consequence |
| --- | --- | --- |
| Count progression | Count advances at the expected prescaled rate | Do not change Count increment semantics yet |
| Compare programming | Linux writes Compare repeatedly and the value tracks future Count | Do not classify this as a missing Compare write |
| Timer acceptance | 126 accepted interrupt records in the 65M bounded run | Interrupt entry is observable |
| WAIT entry | 0 `WAIT_TRACE` records | The run has not reached the WAIT boundary |
| Dominant terminal PCs | `0x88a436d0`/`0x88a436d4` (`__udelay`) | Current owner is pre-WAIT delay/clock progress |
| Terminal state | `ACTIVE_OR_IDLE`, Count below Compare, no timer IP | Timer/WAIT wakeup is not the first divergence in this run |

The next change must therefore distinguish the Linux `__udelay` loop's Count
read/elapsed-time contract, interrupt-entry/return effects, and the upstream
initcall progress before changing `WAIT` RTL. The timer/WAIT path remains a
required later gate, but it is no longer the first implementation owner.

## 2. Closure definition

The target of this plan is a bounded, reproducible contract:

- the same kernel, DTB, Boot ROM, DDR image, command line, CPU model, and
  peripheral map are used by QEMU and RTL;
- the blocking RTL path and the opt-in nonblocking path are run separately;
- every compared architectural record is complete and ordered through a
  declared terminal marker or record bound;
- UART and VIC effects are compared as normalized transactions; and
- every result has an input/tool manifest, first mismatch, exit status, and
  residual-risk statement.

This does not claim unrestricted Linux, complete MIPS32 privileged ISA/FPU,
arbitrary demand paging or shootdown, physical DDR/QSPI timing, or commercial
formal/CDC/RDC/lint/product signoff.

## 3. Execution order

### Phase 0: freeze and validate evidence

Create a fresh run root under `/data/disk/tmp/mips32-soc/` and record hashes
for the worktree inputs, simulator, QEMU binary/plugin, kernel, DTB, Boot ROM,
DDR image, defines, plusargs, command line, timeout, and cycle/record limits.
Do not reuse old logs as current evidence.

Run first:

```text
make rtl-frontend-compile
make focus-differential-checker-test
make peripheral-differential-checker-test
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
```

Acceptance is a fresh manifest and fresh reports. A timeout or simulator exit
is accepted only when it is the declared termination mode and no assertion,
crash, fatal message, or truncated trace is present.

### Phase 1: close the pre-WAIT delay/clock boundary

The current run must first prove why `__udelay` continues for the declared
bound. Capture and compare:

- every Count read used by the delay loop and the returned GPR value;
- the loop start/end values and the expected elapsed Count delta;
- timer interrupt entry, EPC, `ERET`, and the first post-return PC;
- the current kernel task-load and initcall markers around the loop; and
- QEMU system-mode Count/Compare behavior for the same kernel image.

Add a bounded firmware test for Count reads across a delay loop and a Linux
diagnostic assertion that a Count read is monotonic except for documented
wraparound. The required result is either an RTL/QEMU Count-read mismatch or
proof that the generic image's expected delay is longer than the current
cycle bound. Do not replace `__udelay` with a shortcut or alter `lpj` merely to
make the marker appear.

Acceptance:

- `scripts/analyze_linux_timer_wait.py` reports `PRE_WAIT_UDELAY_LOOP` or a
  later classified boundary from a fresh manifest;
- the first mismatch is tied to Count read data, interrupt return, memory,
  or the declared workload bound; and
- a fix is made only in the identified owner and is covered by a directed
  Count/delay regression.

### Phase 2: close the CP0 timer/WAIT boundary

Add a diagnostic-only trace and assertions covering, in one ordered stream:

- CP0 Count reads/writes and Compare writes;
- Count/Compare equality and timer interrupt source assertion;
- Status/IM/IE and Cause/IP transitions;
- `WAIT` decode, retirement, wakeup reason, and the first instruction after
  wakeup;
- exception entry EPC, `Cause.BD`, vector, and saved mode;
- `ERET` retirement and the resumed PC; and
- the next scheduler/idle transition.

The trace must identify the architectural instruction and not only a pipeline
cycle. Add directed tests for:

- Compare programmed before `WAIT` and timer wakeup;
- Compare already expired before `WAIT`;
- masked timer interrupt while waiting, followed by unmask;
- non-timer interrupt waking `WAIT`;
- `WAIT` in a branch delay-slot-adjacent pipeline placement;
- interrupt entry followed by `ERET` to the correct post-`WAIT` PC; and
- repeated timer periods without losing or duplicating wakeups.

Use the first divergent event to select the fix:

| First divergence | Fix boundary | Required proof |
| --- | --- | --- |
| Count/Compare value | CP0 timer state/update | directed Count/Compare regression and Linux checkpoint |
| IP assertion or masking | PIC/CP0 interrupt composition | priority/mask test and exact Cause/IP trace |
| `WAIT` does not wake | CPU wait-state exit logic | wakeup reason, one wakeup, no repeated idle loop |
| wrong EPC/BD/vector | precise exception entry | CP0 entry/ERET gate with delay-slot coverage |
| correct return but same idle PC | scheduler timer ack or kernel progress | timer acknowledgement and subsequent retired kernel records |

Acceptance:

- the root-cause checkpoint gate identifies the first mismatch or proves the
  timer/WAIT sequence matches the reference;
- no speculative change is made to cache/MMU/UART behavior before this
  classification; and
- `make rtl-linux-root-cause-checkpoint-gate` produces a fresh report for
  both blocking and nonblocking configurations.

### Phase 3: generic Linux init gate

After Phase 1, run the immutable generic image and require ordered markers:

```text
kernel entry -> early console -> ttyS0 probe -> initramfs -> /init
```

The gate must fail on panic, oops, assertion, unexpected simulator exit,
missing marker, reordered marker, or child failure masked as timeout. QEMU
success is a reference result only and cannot satisfy the RTL gate.

Commands:

```text
make rtl-linux-generic-init-gate
make rtl-linux-generic-userspace-gate
```

The userspace gate remains separate and requires declared markers for process
start, VM/page-fault activity, GPIO access, timer/sleep, and clean exit. A
minimal image pass must not be relabeled as generic Linux.

### Phase 4: complete architectural differential

Define one common JSONL schema for QEMU and RTL containing, at the declared
retirement boundary:

- sequence, PC, instruction, and occurrence identity;
- all 32 GPRs, HI/LO, and committed writeback;
- committed memory effects and LL/SC result;
- implemented CP0 state, exception/interrupt metadata, EPC, BD, BadVAddr;
- TLB operations at the declared abstraction boundary; and
- terminal reason and completeness state.

Compare these pairs independently:

```text
QEMU vs blocking RTL
QEMU vs nonblocking RTL
blocking RTL vs nonblocking RTL
```

The comparator must reject missing records, duplicate or non-contiguous
sequences, reordered occurrences, partial final records, unequal lengths, and
unexplained termination. It must report the first mismatch with both records
and classify it as CPU, CP0/exception, MMU/memory, peripheral, or termination.

The accepted result name is `BOUNDED_PASS`; never use `FULL_ISA_PASS` or
`FULL_LINUX_PASS` for this gate.

### Phase 5: peripheral causality

Run the UART and VIC normalized transaction comparison using the same frozen
image manifest. UART records include address, width, byte enables, data,
response/error, IRQ state, and acknowledgement. VIC records include raw,
mask, pending, active source, priority choice, acknowledge, completion, and
nested re-entry order.

Keep mutation tests for missing, duplicated, reordered, and modified records.
A matching UART string is not sufficient evidence of peripheral equivalence.

### Phase 6: promotion and residual-risk review

Write one compact `completion_report.md` linking all child reports and
manifests. Promote only the boundaries whose gates pass from current source.
The report must retain the exact image/record/cycle bounds and list open items,
including full OS page-table/shootdown pressure, complete privileged ISA/FPU,
physical memory-device timing, and EDA signoff.

## 4. Required artifacts

Each fresh run must contain:

```text
manifest.json
linux_root_cause/report.md
linux_init/report.md
linux_userspace/report.md
qemu_smoke/report.md
retire_diff/report.md
peripheral_diff/report.md
completion_report.md
```

Large VCS objects, waveforms, compiler intermediates, and QEMU build output
stay under `/data/disk/tmp/mips32-soc`; only compact reports belong in the
repository or release evidence.

## 5. Stop conditions

Keep the relevant boundary `OPEN` when:

- the first divergence is not localized;
- a trace is incomplete, sampled, or non-monotonic;
- QEMU and RTL inputs differ;
- only blocking or only nonblocking RTL was tested;
- a child crash is classified as a timeout or marker pass;
- a gate is made to pass by weakening exclusions or changing the default
  blocking configuration; or
- a bounded result is described as unrestricted Linux or full ISA compliance.

The immediate next implementation task is therefore the pre-WAIT
`__udelay`/Count-read differential. Only after that boundary reaches the
kernel's `WAIT` path should CP0 `WAIT` wakeup/`ERET` semantics be modified or
the generic init gate be promoted.
