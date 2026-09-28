# RTL Linux System-Mode Differential Fix Plan

Plan date: 2026-09-20  
Status: `SUPERSEDED BY v21 / FULL TERMINAL-MARKER CLOSURE REQUIRED`  
Scope: current-source RTL, QEMU `mips32-soc-ref`, and the bounded Linux
system-mode differential boundary

The authoritative current plan is
`docs/rtl_linux_differential_fix_plan_v21.md`. This document is retained as
historical execution context; its bounded-prefix target is not full closure.

This is the current execution plan for the largest remaining gap. The earlier
`docs/rtl_linux_differential_remediation_plan.md` remains the detailed baseline
and evidence history; this document reorders the work around the fixes that
must land next.

## 1. Closure target

Close a reproducible, current-source, bounded system-mode differential gate
that starts from one identical Linux image and compares complete architectural
retire records from QEMU and RTL through a declared terminal marker.

The first milestone is not unrestricted Linux or full ISA compliance. It is:

1. the RTL reaches the same generic Linux boot and userspace markers as the
   reference workload;
2. the first divergent committed instruction is identified with strict records;
3. the repaired blocking and opt-in nonblocking paths pass the same bounded
   differential contract; and
4. UART/VIC effects needed by that workload are compared independently of CPU
   cycle timing.

Until all four conditions pass, the project must describe the result as
`BOUNDED / OPEN`, not as full Linux, full MMU, full ISA, or product signoff.

## 2. Current baseline

| Area | Evidence/status | Remaining action |
| --- | --- | --- |
| RTL frontend | Fresh 8-configuration compile passes | Re-run after each RTL owner or delay-slot change |
| Strict focus comparator | Adversarial checker test passes | Use it in every fresh differential run |
| QEMU focus plugin | Lifecycle fix is present; exit callback no longer reads live registers | Run direct system-mode smoke and retain exit status |
| RTL retire capture | Uses RF commit signals for the selected writeback path | Extend the common record contract and self-checks |
| BadVAddr owner gate | Current bounded capture/commit trace passes | Fix flush ordering and add the older-exception/younger-fault negative case |
| Delay-slot IRQ | Existing directed gate passes | Directly observe WB-to-EX and WB-to-ID recovery terms |
| Generic RTL Linux | Open | Reach `ttyS0`, `/init`, and guest userspace markers |
| UART/VIC equivalence | Open | Add normalized transaction comparison |
| Full system-mode differential | Open | Compare complete bounded retire streams from one manifest |

Known evidence is retained under `/data/disk/tmp/mips32-soc`. No retained
artifact is authoritative when its source, simulator, plugin, image, or tool
identity does not match the current run manifest.

## 3. Execution order

### Step 0: freeze the run contract

Before changing behavior, make every run reproducible and auditable.

- Use a fresh run root under `/data/disk/tmp/mips32-soc/`.
- Record branch, commit, dirty status, source hash, RTL defines, plusargs,
  QEMU binary and plugin hashes, kernel/DTB/Boot ROM/DDR hashes, tool versions,
  command lines, timeout, and unmasked exit statuses.
- Make fresh compilation the default. Permit reuse only with
  `REUSE_ARTIFACTS=1` and an exact manifest match.
- Reject stale logs, incomplete QEMU records, simulator crashes, and unexpected
  nonzero statuses even when a marker was printed.

Acceptance:

- Mutating any RTL source, plugin source, image, define, or tool identity
  invalidates reuse.
- A timeout is accepted only when it is the declared contract, the expected
  status is returned, all required records are flushed, and no assertion,
  signal, abort, or fatal signature exists.

### Step 1: correct BadVAddr owner-token ordering

The owner-token sequential block currently gives new D-fault capture priority
over a generic exception flush. That can preserve a younger fault when an
older exception flushes the pipeline in the same cycle.

Change the decision order in `rtl/cpu/mips_cpu.v` to:

1. clear a matching owner commit;
2. clear on `ERET` or context restore;
3. clear on an unmatched exception flush;
4. capture a new D translation fault only when no owner is pending.

Preserve the current owner identity fields: PC, instruction, exception code,
and virtual address. Add or retain a generation/squash identity if the
directed negative test can demonstrate that PC/instruction/code are not
unique enough for a replay in the current pipeline.

Required checks:

```text
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
```

The gate must cover matching replay, older-exception plus younger-fault
squash, later unrelated data fault, IRQ coincidence, back-to-back faults,
reset, `ERET`, and context restore. It must fail on owner, exception-code,
address, or CP0 identity mismatch, not merely on `BadVAddr=0xffffffff`.

### Step 2: close direct delay-slot coverage

Extend `tb/soc_test/run_cpu_irq_delay_slot_gate.sh` and its firmware/testbench
so the gate requires direct observations of both signals:

- `interrupt_wb_branch_delay_from_ex`;
- `interrupt_wb_branch_delay_from_id`.

Add positive and negative cases for taken/not-taken branches and supported
`jr`/`jalr` paths. Each positive case checks interrupt acceptance, EPC,
`Cause.BD`, ERET resume PC, and a post-return canary write. Negative adjacency
and stale-stage/replay cases must not assert `Cause.BD`.

Add explicit counters and a completion report. A passing summary with only an
interrupt count is insufficient if either recovery term was never observed.

Required checks:

```text
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make rtl-frontend-compile
```

### Step 3: prove the QEMU and RTL record producers

Run a short QEMU system-mode plugin test before the expensive Linux replay.
The test matrix must include normal guest exit, expected timeout, record-limit
exit, missing target PCs, and forced plugin failure.

Record semantics must be explicit and identical on both sides:

- one monotonically increasing retire sequence;
- PC, instruction, occurrence identity, phase, and complete selected GPR state;
- committed write enable/address/data;
- exception, EPC, `Cause.BD`, `BadVAddr`, delay-slot, and owner fields when
  applicable;
- no partial record can satisfy a gate.

The QEMU plugin reads registers only while a valid vCPU callback is active and
flushes cached records at exit. The exit callback must never query live vCPU
state. The RTL monitor records only `wb_commit_valid` events and must self-check
that squashed, excepting, or invalid WB writes do not alter post-state.

Required checks:

```text
make focus-differential-checker-test
```

Then run the direct QEMU system smoke and retain a valid trace-checker report.

### Step 4: add staged generic RTL Linux gates

Split the current broad Linux attempt into independently diagnosable gates.
All gates use one hashed kernel, DTB, Boot ROM, DDR image, command line, RAM
size, CPU feature set, and peripheral map.

1. `rtl-linux-root-cause-checkpoint-gate`: strict comparison around the known
   `number()`/delay-slot window; no truncated or ambiguous checkpoint passes.
2. `rtl-linux-generic-init-gate`: kernel entry, early console, serial driver,
   `ttyS0`, initramfs discovery, and `/init` execution.
3. `rtl-linux-generic-userspace-gate`: guest-generated process, VM, GPIO,
   timer/sleep, and exit markers in declared order.

Each gate must reject panic, oops, assertion, unexpected simulator termination,
and missing or reordered markers. The existing opt-in minimal userspace gate
remains a separate bounded contract and cannot substitute for generic Linux.

Run blocking and nonblocking RTL configurations independently. A nonblocking
pass does not replace the blocking baseline.

### Step 5: compare UART and VIC transactions

Add normalized transaction traces for the generic Linux workload. Compare
causal order, not host or RTL cycle number.

UART fields:

- address, width, byte lanes, read/write data, response/error, IRQ assertion,
  IRQ deassertion, and acknowledged source.

VIC fields:

- raw, mask, pending, active/source ID, priority decision, acknowledge,
  completion, and nested re-entry ordering.

Add mutation fixtures for missing, duplicated, reordered, and changed
transactions. A marker-only QEMU or RTL boot result is not sufficient.

### Step 6: run bounded full retire differential

Declare the terminal record count or guest end marker before execution. Compare
without sampled gaps and require equal complete-record counts.

At minimum compare PC, instruction, all 32 GPRs, HI/LO, committed memory
operations, LL/SC result, implemented CP0 state, exception metadata, interrupt
source/order, and TLB operations at the agreed abstraction boundary. Any
excluded field requires a written rationale and a negative checker fixture.

Run these as separate gates:

- QEMU versus blocking RTL;
- QEMU versus nonblocking RTL;
- blocking RTL versus nonblocking RTL.

The report must identify the first mismatch, owner category, record count,
terminal marker, and all input hashes. A pass is `BOUNDED_PASS` only.

## 4. Required implementation outputs

| Output | Location |
| --- | --- |
| Source/tool/image manifest | `<run-root>/manifest.json` |
| Owner-token trace and report | `<run-root>/badvaddr_owner/` |
| Delay-slot coverage summary | `<run-root>/delay_slot/` |
| QEMU lifecycle/trace report | `<run-root>/qemu_smoke/` |
| Generic boot and userspace logs | `<run-root>/linux_init/`, `<run-root>/linux_userspace/` |
| UART/VIC normalized traces | `<run-root>/peripheral_diff/` |
| Differential result | `<run-root>/retire_diff/` |
| Residual-risk report | `<run-root>/completion_report.md` |

Do not store new large simulator, waveform, or temporary compiler outputs on
`/`; use `/data/disk/tmp/mips32-soc` and retain only logs, manifests, reports,
and the minimum reproducer needed for review.

## 5. Final acceptance

This plan is complete only when:

- the owner-token squash ordering and all negative cases pass;
- both WB-to-EX and WB-to-ID delay-slot terms have direct coverage;
- QEMU lifecycle tests prove no assertion, crash masking, or incomplete final
  record;
- generic RTL reaches `ttyS0`, `/init`, and the declared guest markers;
- UART/VIC transaction comparison passes independently;
- all three bounded retire comparisons pass from one source/image manifest;
- every report states its exact bound and residual risk.

This plan does not, by itself, close unrestricted MIPS32 ISA compliance,
complete FPU/IEEE-754 behavior, arbitrary Linux demand paging and multicore
shootdown, physical DDR/QSPI timing, formal/CDC/RDC/lint signoff, or synthesis,
STA, DFT, and product release readiness. Those remain separate contracts after
the bounded system-mode differential boundary is stable.
