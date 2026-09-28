# RTL Linux Differential Fix Plan v5

Plan date: 2026-09-21  
Status: `OPEN / EXECUTION REQUIRED`  
Owner: RTL CPU/CP0, Linux boot verification, QEMU system-mode reference

This plan supersedes v4 as the execution order for the current blocker. It is
based on fresh current-source evidence. It is a fix plan, not a closure report.

## 1. Current decision

The largest unresolved gap is not yet a proven timer, cache, or MMU RTL bug.
The current generic RTL Linux run stops before `WAIT`, in the pre-`WAIT`
`__udelay` path. QEMU reaches `/init` with the same frozen Linux image, but
the first comparison is not yet architectural because QEMU Count samples are
sparse and wall-clock driven while RTL evidence is cycle/retirement driven.

The next implementation must therefore establish a deterministic architectural
time/retirement comparison before changing RTL timing or increasing Linux
timeouts indefinitely.

| Boundary | Current evidence | Status |
| --- | --- | --- |
| RTL frontend | Current compile checks pass | `PASS` |
| Timer comparator | Positive and mutation tests pass | `INFRASTRUCTURE_PASS` |
| QEMU CP0 trace | Custom machine trace and sparse interval work; QEMU boots `/init` | `CAPTURE_PASS` |
| RTL diagnostic run | 65M-cycle fresh run, `LINUX_TIMER_WAIT_ANALYSIS_PASS` | `OBSERVED` |
| RTL `WAIT` boundary | Zero `WAIT` records in the fresh run | `NOT_REACHED` |
| RTL dominant path | `0x88a436d0/0x88a436d4`, kernel `__udelay` | `OPEN` |
| QEMU/RTL Count comparison | 1,902 matched records but 8,197 mismatches; sparse Count/PC alignment is not causal proof | `DIAGNOSTIC_FAIL` |
| Generic RTL `/init` | Not reached | `OPEN` |
| Complete system-mode retire differential | No complete generic Linux gate | `OPEN` |

The QEMU `-icount` experiment is not an RTL failure: the custom CP0 timer
reads QEMU virtual time while TCG `can_do_io=false`, producing QEMU `Bad icount
read`. Keep this as a reference-model limitation until a supported deterministic
clock mode or a retirement-based normalization is implemented.

## 2. Scope and non-claims

This plan targets a bounded, reproducible generic Linux checkpoint and a
bounded QEMU-versus-RTL system-mode differential. It does not claim unrestricted
Linux, complete MIPS32 privileged ISA, complete FPU/ABI behavior, arbitrary
demand paging or SMP shootdown, physical DDR/QSPI timing, or commercial
formal/CDC/RDC/lint/product signoff.

The default blocking CPU/cache path remains the baseline. Nonblocking L1/L2
paths remain opt-in and require separate evidence. No default configuration,
Linux delay calibration, interrupt mask, or timeout may be changed merely to
make a marker appear.

## 3. Execution order

### Phase 0: freeze one reproducible run

Create a new run root under `/data/disk/tmp/mips32-soc/`. Write a manifest
before launching either model containing:

- kernel, DTB, Boot ROM, DDR image, command line, and SHA-256 values;
- RTL source/file-list/defines, simulator and module versions, and worktree
  state;
- QEMU binary, custom-machine source, CPU model, plugin, and machine
  properties;
- RTL cycle bound, QEMU timeout, trace limits, Count sampling interval, and
  all plusargs/environment variables;
- process exit codes and explicit terminal reason for every child process.

Run the static/unit prerequisites from a clean output location:

```text
make rtl-frontend-compile
make focus-differential-checker-test
make peripheral-differential-checker-test
make linux-timer-clock-comparison-test
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
```

Acceptance: the manifest is complete, artifacts are fresh, and a timeout,
simulator crash, assertion, or truncated trace cannot be mislabeled as a
bounded pass.

### Phase 1: make QEMU time comparable

Implement one of these explicitly documented comparison modes:

1. a diagnostic QEMU CP0 clock mode whose Count advances from a declared
   retired-instruction or deterministic virtual-tick source without calling
   `qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL)` from an icount-prohibited context; or
2. a retirement-normalized comparison that does not claim Count equality until
   QEMU and RTL records are aligned by architectural retire sequence and the
   Count contract is stated in that sequence.

Do not silently combine both modes. The report must identify the selected mode,
Count divisor, reset value, Compare reset, wrap policy, and sampling rule.

Extend the checker fixtures to reject or diagnose:

- missing or duplicated sequence numbers;
- Count backsteps except for declared wraparound;
- malformed Count/Compare fields;
- invalid sparse-sample step;
- partial final records and hidden child failures; and
- a mutated reset/divisor configuration.

Acceptance: a synthetic trace with the declared clock mode compares exactly,
and a Count/PC mutation fails with the intended first-mismatch classification.
The real QEMU-vs-RTL report may still be `OPEN`, but it must no longer confuse
sparse sampling with an architectural Count mismatch.

### Phase 2: establish the first architectural divergence

Run the frozen QEMU and RTL workload using the same image and declared mode.
Capture, at minimum:

- retire sequence, PC, instruction, and terminal reason;
- Count reads and writes, Compare writes, Status/IM/IE and Cause/IP;
- exception entry, EPC, `Cause.BD`, vector, `ERET`, and first post-return PC;
- Linux progress markers around BSS clear, initcalls, `__udelay`, and `WAIT`;
- committed memory effects for the delay path; and
- cache/MMU/TLB/refill events only when the first mismatch points there.

Classify the first difference using this decision table:

| First difference | Next owner | Required proof |
| --- | --- | --- |
| Count reset/divisor/scale | CP0 clock/prescaler or QEMU mode | directed wrap/Compare test and fresh Linux checkpoint |
| Count read value differs at equal retire point | CP0 read/commit path | GPR/CP0 retire record and Count regression |
| Compare/IP/mask differs | timer interrupt composition | masked/expired/periodic timer gate |
| EPC/BD/vector/ERET differs | precise exception and delay-slot recovery | CP0 entry/return regression |
| Timer state equal but PC progress differs | fetch, retire, memory, cache, or MMU | first mismatching retire record and transaction trace |
| No architectural mismatch within bound | workload estimate or missing marker instrumentation | declared bound analysis; status remains `OPEN` |

No RTL fix is allowed before this classification. In particular, do not alter
`WAIT`, Count semantics, `lpj`, cache defaults, UART, or MMU based only on the
fact that QEMU reaches userspace sooner.

### Phase 3: apply one targeted fix and rerun

Change only the owner selected by Phase 2. Each change requires:

- one minimal directed regression;
- one negative or reset/backpressure case where applicable;
- one fresh generic Linux checkpoint using the same manifest; and
- a report showing the old and new first-mismatch classification.

If the evidence selects the pre-`WAIT` path, instrument the RTL retirement
boundary and BSS/`__udelay` memory progress before touching cache or CP0 logic.
If it selects CP0 or exception handling, preserve the existing delay-slot and
BadVAddr ownership contracts and rerun their gates. If it selects memory/cache
or MMU, compare committed transactions and fault ownership before changing
microarchitecture.

### Phase 4: close generic RTL Linux init

After the targeted fix passes, run:

```text
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

The init gate must observe these markers in order:

```text
kernel entry -> early console -> ttyS0 probe -> initramfs -> /init
```

It must fail on panic, oops, assertion, simulator failure, missing/reordered
markers, incomplete trace, or a hidden child failure. QEMU success is only a
reference result and cannot satisfy this gate.

### Phase 5: close bounded userspace and system differential

Only after generic RTL `/init` passes:

```text
make rtl-linux-generic-userspace-gate
make qemu-system-linux-differential-gate
```

The common retire schema must include sequence, PC, instruction, GPR state,
HI/LO, committed memory effects, LL/SC result, implemented CP0 state,
exception metadata, and terminal reason. Compare separately:

```text
QEMU vs blocking RTL
QEMU vs opt-in nonblocking RTL
blocking RTL vs nonblocking RTL
```

Reject unequal lengths, missing records, duplicate/reordered sequence numbers,
partial terminal records, and unexplained termination. The accepted result is
`BOUNDED_PASS`; it must not be called full ISA, full Linux, or unrestricted
equivalence.

### Phase 6: publish evidence and residual risks

Write a compact completion report linking the manifest, timer calibration,
first-mismatch report, directed regressions, generic init/userspace logs, and
retire differential reports. Keep all large logs and binaries under
`/data/disk/tmp/mips32-soc`; commit only source, scripts, plans, and compact
reports.

The report must retain these open risks unless separately proven:

- full demand paging, page-table management, and SMP shootdown stress;
- complete privileged ISA and FPU/IEEE-754/Linux ABI behavior;
- physical DDR/QSPI PHY, JEDEC timing, training, endurance, and board tests;
- formal, CDC/RDC, lint, synthesis, STA, DFT, and product signoff; and
- unbounded QEMU/RTL equivalence.

## 4. Definition of done

This plan is complete only when a fresh report links:

1. a declared, deterministic QEMU/RTL Count or retirement comparison mode;
2. a classified first architectural mismatch or a justified bound result;
3. a targeted fix with directed regression evidence;
4. generic RTL `/init` and declared userspace markers;
5. a complete bounded retire differential for the declared configuration; and
6. manifests, exit statuses, checker results, and residual risks.

Until all six are present, the project status remains `OPEN`.

## 5. Immediate next commands

The next implementation slice is limited to clock/retirement calibration and
fresh evidence generation:

```text
make linux-timer-clock-comparison-test
make rtl-frontend-compile
```

Then create a fresh manifest/run root, run QEMU with the declared sparse CP0
trace mode, run the RTL root-cause checkpoint with the same image, and update
the report before modifying RTL. Do not promote the old v4 comparison failure
to an RTL bug without this calibration.
