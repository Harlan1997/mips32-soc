# RTL Linux Differential Closure Plan v2

Plan date: 2026-09-21  
Status: `OPEN / EXECUTION REQUIRED`  
Owner: RTL, testbench, QEMU reference-model integration

This is the replacement execution plan for the current RTL Linux/QEMU
blocker. The previous plans remain useful evidence and history, but this
document is the active order of work. It is intentionally narrower than a
claim of full MIPS32/Linux compliance.

## 1. Current diagnosis

The largest gap is not the absence of a QEMU machine or the absence of small
RTL regressions. The project has those pieces. The gap is that the generic
Linux system-mode path still lacks a current-source, end-to-end proof of the
first architectural divergence and therefore cannot distinguish among:

- CPU delay-slot/interrupt recovery;
- exception flush and replay ownership;
- register writeback or forwarding;
- MMU/TLB state and memory translation; and
- UART/VIC side effects.

The existing focus runner compares selected PCs and registers. It is useful
for diagnosis, but it is not a complete retire differential gate. A passing
QEMU boot, a passing reduced userspace image, or a passing selected retire
corpus must not be reported as generic RTL Linux closure.

Known current evidence:

| Boundary | State | Interpretation |
| --- | --- | --- |
| RTL frontend | Available | Re-run after every RTL change |
| BadVAddr owner trace | Bounded pass after owner-order fix | Needs fresh negative/replay evidence |
| Delay-slot WB-to-EX/WB-to-ID | Directed coverage implemented | Needs clean rerun and report retention |
| QEMU `mips32-soc-ref` | System-mode boot exists | Lifecycle and record completeness still need a dedicated gate |
| Focus differential | Comparator and runner exist | Selected checkpoints only; not full differential |
| Generic RTL Linux | Open | `ttyS0`, `/init`, and userspace completion are not current signoff evidence |
| UART/VIC equivalence | Open | No independent normalized transaction gate |
| Full bounded retire differential | Open | No complete three-way current-source gate |

## 2. Closure definition

The target for this plan is a reproducible bounded contract with:

1. one immutable kernel, DTB, Boot ROM, DDR image, command line, CPU feature
   set, and peripheral map;
2. current-source blocking RTL, opt-in nonblocking RTL, and QEMU system-mode
   runs;
3. complete architectural retire records until a declared record limit or
   guest terminal marker;
4. separately compared UART and VIC transaction streams; and
5. reports that preserve exit status, first mismatch, input hashes, and
   residual risk.

This closes a bounded system-mode differential boundary only. It does not
close unrestricted Linux, arbitrary demand paging/shootdown, complete
privileged ISA, complete FPU/IEEE-754 behavior, physical DDR/QSPI timing,
formal/CDC/RDC/lint signoff, or product release readiness.

## 3. Execution sequence

### Phase 0: establish a clean evidence root

Create a fresh run root under `/data/disk/tmp/mips32-soc/` for every attempt.
Generate `manifest.json` containing:

- git commit and complete dirty-worktree listing;
- hashes of RTL, testbench, scripts, QEMU binary/plugin, kernel, DTB,
  Boot ROM, DDR image, and command line;
- simulator, compiler, QEMU, and module versions;
- all defines, plusargs, timeouts, cycle/record bounds, and command lines;
- exit status for every child process.

Reuse is allowed only with an exact manifest match. A timeout is valid only
when it is the declared termination mode, the trace is complete, and no
assertion, abort, crash, or fatal diagnostic occurred.

Acceptance commands:

```text
make rtl-frontend-compile
make focus-differential-checker-test
```

### Phase 1: finish local CPU exception evidence

Re-run the existing current-source gates after the recent cleanup:

```text
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make cpu-cp0-gate
```

The reports must show:

- owner capture, matching commit, squash, reset, `ERET`, context restore,
  back-to-back fault, and older-exception/younger-fault negative cases;
- direct WB-to-EX and WB-to-ID delay-slot recovery hits;
- zero unowned `Cause.BD` events;
- correct EPC, resume PC, post-return canary, and no duplicate retirement.

Do not accept a summary based only on interrupt count or on the absence of
`BadVAddr=0xffffffff`.

### Phase 2: harden QEMU system-mode capture

Add a small QEMU lifecycle gate before Linux comparison. It must exercise:

1. normal guest terminal exit;
2. expected timeout;
3. record-limit termination;
4. missing target-PC handling; and
5. forced plugin failure.

The gate must prove that the plugin never reads live vCPU registers from an
invalid exit callback, does not mask a child crash as a timeout, and does not
accept a partial final record. Each record must contain a monotonic sequence,
PC, instruction, phase/occurrence identity, selected architectural state,
writeback information, and exception metadata when applicable.

Required output:

```text
<run-root>/qemu_smoke/{manifest.json,run.log,trace.log,report.md}
```

The forced-failure case must fail the gate. This prevents a broken plugin or
QEMU process from being mistaken for a successful bounded run.

### Phase 3: isolate generic RTL Linux progress

Split the broad Linux attempt into three independent gates. All three use the
same frozen image manifest and run blocking and nonblocking RTL separately.

#### 3.1 Root-cause checkpoint gate

`rtl-linux-root-cause-checkpoint-gate` stops at the known `number()` and
delay-slot window. It captures all 32 GPRs, HI/LO, CP0 state relevant to the
exception, memory accesses, and the last committed control transfer. It must
report the first mismatch rather than only a later crash.

#### 3.2 Generic init gate

`rtl-linux-generic-init-gate` requires, in order:

```text
kernel entry -> early console -> ttyS0 probe -> initramfs -> /init
```

It rejects panic, oops, assertion, simulator termination, missing markers,
and reordered markers. QEMU success cannot substitute for RTL success.

#### 3.3 Generic userspace gate

`rtl-linux-generic-userspace-gate` requires guest-generated markers for a
process start, VM/page fault activity, GPIO access, timer/sleep, and clean
exit. This is a bounded contract; it must declare its image and terminal
bound, and it must not be labeled arbitrary Linux userspace support.

Until these gates exist and pass, the status remains `GENERIC_LINUX_OPEN`.

### Phase 4: close peripheral causality

Instrument both models with normalized transaction records. Compare causal
order and architectural effect, not host-cycle numbers.

UART records must include address, width, byte enables, read/write data,
response/error, IRQ assertion/deassertion, and source acknowledgement.

VIC records must include raw, mask, pending, active/source ID, priority
choice, acknowledge, completion, and nested re-entry order.

Add negative fixtures for missing, duplicated, reordered, and modified
transactions. A matching console string alone is insufficient.

Required outputs:

```text
<run-root>/peripheral_diff/{rtl_uart.jsonl,qemu_uart.jsonl,rtl_vic.jsonl,qemu_vic.jsonl,report.md}
```

### Phase 5: bounded complete retire differential

Implement one common schema and compare without sampled gaps. At minimum the
schema covers PC, instruction, all 32 GPRs, HI/LO, committed memory effects,
LL/SC result, implemented CP0 state, exception/interrupt metadata, and TLB
operations at the declared abstraction boundary.

Run three independent comparisons:

```text
QEMU              vs blocking RTL
QEMU              vs nonblocking RTL
blocking RTL      vs nonblocking RTL
```

Each run must have equal complete-record counts or the same declared guest
terminal marker. The report must identify first mismatch, category, record
number, PC, input manifest, and whether the mismatch is architectural,
peripheral, or termination-related.

The result name is `BOUNDED_PASS`, never `FULL_ISA_PASS` or
`FULL_LINUX_PASS`.

## 4. Implementation backlog

| Priority | Work item | Done when |
| --- | --- | --- |
| P0 | Re-run cleaned BadVAddr and delay-slot gates | Fresh reports pass with direct coverage |
| P0 | QEMU lifecycle/record-integrity gate | All five lifecycle cases classify correctly |
| P0 | Root-cause checkpoint producer for both RTL modes | First mismatch is reproducible and classified |
| P1 | Generic init and userspace progress gates | Required markers pass from current source |
| P1 | Common retire schema and complete-count checks | No sampled-gap or partial-record acceptance |
| P1 | UART/VIC normalized traces | Positive and mutation fixtures pass/fail correctly |
| P2 | Three-way bounded retire differential | All three comparisons return `BOUNDED_PASS` |
| P2 | Residual-risk and release report | Bounds and non-goals are explicit |

## 5. Required reports and locations

Every phase writes only compact evidence to the run root:

```text
manifest.json
cpu_exception/report.md
qemu_smoke/report.md
linux_root_cause/report.md
linux_init/report.md
linux_userspace/report.md
peripheral_diff/report.md
retire_diff/report.md
completion_report.md
```

Large VCS objects, waveforms, compiler intermediates, and temporary QEMU
build output stay under `/data/disk/tmp/mips32-soc`; they must not be placed
under `/` or committed to the repository.

## 6. Stop conditions and reporting language

Stop and classify the run as open when any of these occurs:

- a trace is truncated, non-monotonic, or missing its terminal condition;
- a child exits unexpectedly, even if a marker was printed;
- QEMU and RTL use different image or tool manifests;
- the first mismatch cannot be localized to an architectural or peripheral
  record;
- only the blocking or only the nonblocking path was tested;
- a gate passes by weakening exclusions or changing the default configuration.

Until Phase 5 is complete, reports may say `bounded evidence` or
`diagnostic progress`, but must say `OPEN` for generic RTL Linux and full
system differential. After Phase 5, reports must continue to state the exact
record/image bound and all excluded architectural behavior.

