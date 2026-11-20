# RTL Linux Differential Fix Plan v4

Plan date: 2026-09-21  
Status: `OPEN / EXECUTION REQUIRED`  
Owner: RTL CPU/CP0, Linux boot verification, QEMU system-mode reference

This is the next execution plan after the v3 timer/WAIT investigation. It is
an implementation plan, not a closure report. The first owner is the boundary
before Linux reaches `r4k_wait`; no change to `WAIT`, CP0 Count semantics,
cache defaults, or MMU defaults is justified until the comparison in Phase 1
classifies the first mismatch.

## 1. Current decision boundary

Fresh current-source evidence is:

| Boundary | Evidence | Status |
| --- | --- | --- |
| RTL frontend | 8/8 compile checks pass | `PASS` |
| RTL diagnostic run | 65,000,000-cycle bounded run, 669 progress records | `OBSERVED` |
| CP0 Count reads | 963 reads, zero read/internal mismatches, zero backsteps | `NOT_YET_OWNER` |
| Timer/interrupt trace | 126 accepted interrupt records | `OBSERVED` |
| `WAIT` boundary | No `WAIT_TRACE` record in the current run | `NOT_REACHED` |
| Dominant RTL PCs | `0x88a436d0` and `0x88a436d4`, the `__udelay` loop | `OPEN` |
| QEMU system machine | Boots the reference Linux image and emits UART markers | `REFERENCE_ONLY` |
| QEMU CP0 trace | Count advances using `cpu_mips_get_count()`; smoke trace is stable | `CAPTURE_PASS` |
| Complete QEMU/RTL retire differential | No complete generic Linux gate | `OPEN` |

The immediate question is whether the RTL and QEMU implement the same
architectural Count/Compare and delay-loop progress contract. The current
Count read consistency rules out a simple internal RTL readback bug, but does
not rule out clock scale, interrupt side effects, memory/cache divergence, or
an incorrectly bounded workload.

## 2. Scope and non-claims

This plan covers the generic Linux pre-`WAIT` blocker and the evidence needed
to progress to generic init and architectural differential. It does not claim
full MIPS32 privileged ISA, FPU compliance, unrestricted Linux, full demand
paging/shootdown stress, physical DDR/QSPI timing, or commercial EDA signoff.

The default blocking CPU/cache path remains unchanged. Nonblocking L1/L2
paths remain opt-in and are tested separately. A QEMU boot pass is never used
as proof that RTL boot passed.

## 3. Execution plan

### Phase 0: freeze one reproducible input set

Create a new run root under `/data/disk/tmp/mips32-soc/` and record a
manifest before either model starts. The manifest must include:

- kernel, DTB, Boot ROM, DDR image, command line, and their SHA-256 values;
- RTL source/define/file-list identity, simulator identity, and dirty-worktree
  status;
- QEMU binary, custom-machine source, plugin binary/source, CPU model, and
  machine properties;
- timeout, RTL cycle bound, QEMU record bound, trace limits, and all plusargs;
- process exit codes, tool versions, and the exact output paths.

Do not reuse an old simulator or log unless its manifest matches exactly.
Keep large logs and binaries outside the repository. Commit only compact
plans and reports.

Required preliminary checks:

```text
make rtl-frontend-compile
make focus-differential-checker-test
make peripheral-differential-checker-test
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
```

If an entry point is missing or has a different name, add the smallest
project-local wrapper and document it in the manifest; do not silently skip
the check.

Exit criteria: a fresh manifest exists, source/image hashes are recorded, and
the run can distinguish a model failure from an expected bounded timeout.

### Phase 1: implement the CP0 timer/clock comparison

Add a strict utility, for example
`scripts/compare_linux_timer_clock.py`, with two adapters:

- QEMU JSONL `cp0-trace` records: retirement sequence, PC, Count, Compare,
  Cause, Status, and any available timer event;
- RTL records: `LINUX_TIMER_HEARTBEAT`, `LINUX_CP0_READ_TRACE`, CP0 writes,
  accepted interrupt records, progress records, and bounded-end state.

The utility must normalize field names and event types, but must not compare
host cycle numbers directly. It must report:

1. Count monotonicity and wrap handling;
2. Count read values against the model's architectural Count value;
3. Compare writes and the next Count crossing/equality window;
4. Status/IM/IE and Cause timer-IP transitions;
5. the first occurrence of the `__udelay` PC pair;
6. interrupt entry, EPC, `Cause.BD`, `ERET`, and first post-return PC when
   those records exist; and
7. incomplete, reordered, duplicated, or prematurely terminated records.

The report must classify the first difference as one of:

| Classification | Owner to inspect next |
| --- | --- |
| Count scale/value mismatch | CP0 Count clock/prescaler or QEMU model configuration |
| Compare/write mismatch | CP0 write retirement or Linux timer setup |
| Count equal but delay progress differs | instruction retirement, memory/cache, or workload bound |
| IP/mask mismatch | CP0/PIC interrupt composition |
| EPC/BD/ERET mismatch | precise exception and delay-slot recovery |
| Same timer trace, no progress | Linux memory/cache/MMU or instrumentation boundary |

Add parser fixtures for missing fields, duplicate sequence, Count backstep,
partial final records, and a mutated Compare write. The checker must fail for
each mutation for the intended reason.

Exit criteria: a report compares both models using the same image manifest and
identifies either a first architectural mismatch or a defensible workload
bound explanation. A stable Count readback alone is not a pass.

### Phase 2: run the same frozen workload in QEMU and RTL

Run QEMU `mips32-soc-ref` and the RTL with the same kernel, DTB, Boot ROM,
DDR image, command line, CPU configuration, and declared trace bounds.
Generate at minimum:

```text
manifest.json
qemu/cp0_trace.jsonl
qemu/uart.log
rtl/sim_runtime.log
rtl/timer_wait_analysis.md
timer_clock_comparison/report.md
```

Use the existing diagnostic runner and analyzer first. Do not increase the
RTL bound indefinitely before checking whether Count progresses at the same
architectural scale. Do not change Linux `lpj`, replace `__udelay`, or mask
interrupts to force an init marker.

Exit criteria: QEMU and RTL results are fresh, independently terminated, and
their logs have no hidden child crash, assertion, truncated trace, or masked
nonzero exit status.

### Phase 3: fix exactly the classified owner

Apply one targeted RTL or reference-configuration change based on the Phase 1
classification:

- Count scale mismatch: inspect CP0 clock/prescaler and its integration with
  the configured clock; preserve the architectural Count contract and add a
  directed wrap/compare test.
- Compare or timer-IP mismatch: inspect CP0 write commit and interrupt
  composition; add masked/unmasked and expired-before-`WAIT` tests.
- EPC/BD/ERET mismatch: inspect precise exception priority and delay-slot
  metadata; rerun the WB/EX and WB/ID delay-slot gates.
- Equal timer state with divergent progress: inspect committed retire order,
  memory response, cache, MMU, and fault ownership; use the retire and
  BadVAddr traces before changing RTL.
- No mismatch within the declared bound: extend the bound only with a
  written workload estimate and retain status `OPEN` until the first init
  boundary is observed.

Every change must have one directed regression and one fresh Linux checkpoint.
No speculative multi-module refactor is allowed in this phase.

### Phase 4: close generic RTL init

After Phase 3, run:

```text
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

The init gate must observe, in order:

```text
kernel entry -> early console -> ttyS0 probe -> initramfs -> /init
```

It must fail on missing or reordered markers, panic/oops/assertion, simulator
failure, incomplete trace, or a child failure hidden by timeout. The report
must link the exact Phase 1 comparison and current manifest.

### Phase 5: close bounded userspace and retire differential

Only after generic init is passing:

```text
make rtl-linux-generic-userspace-gate
make qemu-system-linux-differential-gate
```

Complete the common retire schema for QEMU and RTL: sequence, PC,
instruction, GPR state, HI/LO, committed memory effects, LL/SC outcome,
implemented CP0 state, exception metadata, TLB operations at the declared
abstraction boundary, and terminal reason. Compare independently:

```text
QEMU vs blocking RTL
QEMU vs nonblocking RTL
blocking RTL vs nonblocking RTL
```

The comparator must reject unequal lengths, missing records, duplicate or
reordered sequence numbers, partial terminal records, and unexplained
termination. The accepted result is `BOUNDED_PASS`, never `FULL_ISA_PASS` or
`FULL_LINUX_PASS`.

### Phase 6: final evidence and residual risk

Produce a compact `completion_report.md` linking the manifest and every child
report. Promote only boundaries with fresh passing evidence. Keep the
following explicit residual risks until separately proven:

- full Linux demand paging, page-table management, and SMP shootdown stress;
- complete privileged ISA and FPU behavior;
- physical DDR/QSPI PHY, JEDEC timing, training, endurance, and board tests;
- commercial synthesis, STA, DFT, CDC/RDC, and formal signoff;
- unrestricted Linux/userspace and unbounded QEMU/RTL equivalence.

## 4. Definition of done

This v4 plan is complete only when all of the following are linked from a
fresh report:

- strict QEMU-vs-RTL timer/clock comparison with a classified first boundary;
- targeted fix and directed regression for that boundary;
- generic RTL `/init` marker gate;
- bounded userspace gate, if its declared markers are reached;
- complete bounded retire differential for the declared configuration;
- manifest, exit statuses, coverage/checker results, and residual risks.

Until then, the correct project status is `OPEN`, even if QEMU boots and the
RTL simulator exits cleanly at its cycle bound.

## 5. Current execution evidence

The first implementation slice is now present in the repository:

- `scripts/compare_linux_timer_clock.py` strictly parses QEMU CP0 JSONL and
  RTL timer/CP0 text records, supports an explicit Linux handoff PC and a
  declared QEMU sampling step, and rejects malformed or reordered input.
- `scripts/test_compare_linux_timer_clock.py` covers a clean comparison,
  Count mutation, PC mutation, malformed Count, and sequence-step mutation.
- `make linux-timer-clock-comparison-test` passes.
- The QEMU `mips32-soc-ref` overlay has a diagnostic-only
  `cp0-trace-interval` property. Sparse tracing avoids changing guest progress
  through per-retire I/O, and the QEMU build was rebuilt successfully.

Fresh run root:

```text
/data/disk/tmp/mips32-soc/plan-v4-timer-compare-20260921-run4
```

Inputs were the frozen `vmlinux` and `mips32_soc_ref_rtl.dtb` from the RTL
checkpoint artifact, with QEMU `rtl-cp0-identity=on` and
`cp0-trace-interval=1000`. QEMU reached `/init`, `BOOT_SUCCESS`,
`GPIO_SUCCESS`, and mprotect markers. The strict comparison remains `FAIL`
and is diagnostic evidence, not a closure result:

- first Count-window difference is in the sparse sampling alignment, not an
  RTL Count readback mismatch;
- by approximately RTL cycle `300000` / Count `0x249ef`, RTL is still in the
  `kernel_entry` BSS-clear loop while QEMU is in `online_css`/kernel setup;
- the RTL trace later reaches the pre-`WAIT` `__udelay` window, while the QEMU
  reference has already reached userspace in the same wall-clock run.

This does not yet select a cache or CP0 RTL fix. QEMU's default virtual clock
is wall-clock driven, and `-icount` currently terminates with `Bad icount read`
in the custom MIPS CP0 timer path. The next owner is therefore to establish a
deterministic retired-instruction/Count calibration or an equivalent QEMU
architectural timer mode before treating the BSS-clear progress difference as
an RTL performance defect.

## 6. Stop conditions

Stop promotion and keep the relevant boundary open when inputs differ, traces
are incomplete, the first mismatch is not localized, a child crash is labeled
as timeout, a checker is weakened to pass, or a default blocking behavior is
changed to bypass regression. Any such condition must be recorded in the
current report rather than converted into a pass claim.
