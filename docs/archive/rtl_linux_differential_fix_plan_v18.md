# RTL Linux Differential Closure Plan v18

Plan date: 2026-09-22  
Status: `OPEN / DIRECT-JAL FIX VERIFIED, SYSTEM DIFFERENTIAL INCOMPLETE`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v17.md`

## 1. Objective

Close the largest remaining architecture-level gap: a reproducible system-mode
QEMU versus RTL retire differential gate for the Linux guest. The gate must
produce complete, bounded, comparable artifacts and fail closed when either
side is truncated, stale, or built from incompatible inputs.

This is an execution plan, not a claim of full ISA, MMU, Linux, or product
signoff. The v17 direct-JAL issue is treated as fixed based on the focused RTL
evidence and passing directed gate. The next result must come from a fresh
post-fix run.

## 2. Current state

### Closed or substantially closed

- Direct-JAL reproducer and target/delay-slot diagnostics exist.
- The proven issue was retire `next_pc` metadata after a stalled delay slot,
  not an IF redirect failure.
- The RTL retire-side fix is present in `rtl/cpu/mips_cpu.v`.
- `direct-jal-gate`, `cpu-cp0-gate`, `cpu-irq-delay-slot-gate`, and
  `rtl-frontend-compile` passed in the v17 evidence set.
- QEMU system-mode custom machine and retire capture infrastructure exist.

### Open blockers

- `phase3-complete` stopped at `ENOSPC` during VCS/DPI archive creation.
- The bounded Linux differential did not produce a complete
  `qemu_retire.jsonl`; the parent comparator correctly did not declare pass.
- Large temporary captures consumed the available space.
- No fresh post-fix system-mode differential proves that the former Linux
  mismatch is absent.
- The worktree contains unrelated dirty changes; every run must record source
  identity and must not silently mix changes into its evidence.

## 3. Non-goals

Do not expand this repair into physical DDR/QSPI validation, Linux SMP,
demand-paging ownership, complete privileged-ISA compliance, FPU compliance,
CDC/RDC/STA/DFT signoff, or board validation. Do not change IF redirect logic,
cache policy, MMU behavior, timer behavior, or QEMU semantics unless a fresh
joined trace proves that owner is the first mismatch.

## 4. Execution phases

### Phase 0: storage-safe baseline

1. Record `git status --short`, `git diff --stat`, tool versions, source
   identity, and the current dirty-state hash in a compact manifest.
2. Audit and remove only explicitly identified campaign captures. Preserve
   build outputs belonging to unrelated user changes.
3. Use a dedicated run root under `/data/disk/tmp` when it has capacity;
   otherwise use only bounded small captures under `/tmp`.
4. Record free space and hard limits for RTL cycles, QEMU retires, trace bytes,
   and wall-clock time. A limit hit is `INCOMPLETE`, never `PASS`.
5. Run `git diff --check` before any code change.

Record these manifest fields:

```text
source tree identity and dirty-state hash
RTL defines and simulator/tool versions
QEMU binary, machine, CPU model, and plugin hashes
guest/kernel/ROM/image SHA-256 values
run directory and filesystem free space
cycle, retire, byte, and wall-clock limits
producer and comparator exit statuses
```

### Phase 1: revalidate the repaired contract

Run from a fresh run directory:

```bash
make rtl-frontend-compile
make direct-jal-gate
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
```

The direct-JAL report must show exactly `JAL`, one delay-slot retirement, and
target retirement. It must reject fall-through retirement, a duplicated delay
slot, target-before-delay-slot, or an unbounded trace. If this phase fails,
stop and repair only the direct-JAL/retire contract.

### Phase 2: make capture and comparison fail closed

Audit the QEMU and RTL capture scripts so they:

- honor the caller-provided run directory and selected filesystem;
- publish JSONL only after successful producer completion;
- write record counts, byte counts, hashes, configuration identity, and a
  completion marker;
- reject timeout, signal termination, malformed final records, missing
  markers, and mismatched guest/image/configuration identities;
- return nonzero for incomplete QEMU or RTL output.

The comparator must stream or use bounded chunks. It must not retain two
unbounded full traces in memory or create an unnecessary second full-size
artifact. Keep only compact mismatch context and summary evidence in the repo.

### Phase 3: fresh bounded system differential

Increase the bound only after each preceding run completes:

1. reset and early firmware;
2. the former direct-JAL window;
3. 5,000 retire records;
4. 20,000 retire records;
5. the first Linux userspace marker;
6. the declared full bounded Linux target.

Every bound requires complete QEMU and RTL producer artifacts plus a comparator
report. Allowed results are:

```text
BOUNDED_PASS | MISMATCH | INVALID_INPUTS | INCOMPLETE | OWNER_UNOBSERVED
```

The first post-fix mismatch becomes a new owner-specific checkpoint. Classify
it from joined evidence before editing RTL; never call a missing file or
timeout an architectural mismatch.

### Phase 4: Linux progress and Phase 3 regression

After the old mismatch window passes:

1. run the Linux focus/progress gate and verify `/init` and declared markers;
2. run `make phase3-complete` from the approved storage location;
3. preserve blocking, I-cache, CP0, interrupt, and coherency gates;
4. record `NOT_RUN` with the exact license or storage reason when blocked.

Phase 3 closes only when all required subtests, logs, coverage checks, and
error scan complete under the same run identity.

### Phase 5: publish compact evidence

Produce a report containing source/tool/guest/image identities, direct-JAL
status, both producer statuses and record counts, comparator result and first
mismatch, Linux marker status, Phase 3 status, resource limits, residual risks,
and explicit `NOT_RUN` items. Keep large traces in approved scratch storage;
record their paths, sizes, and hashes in the report.

## 5. Exit criteria

The plan is complete only when:

- fresh direct-JAL and CPU gates pass;
- QEMU and RTL traces are complete, bounded, and identity-matched;
- the comparator reaches its declared target without malformed or missing
  records;
- the former JAL mismatch is absent in a fresh run;
- Linux reaches the selected marker set;
- `phase3-complete` passes, or its residual failure is explicitly documented
  as a separate accepted blocker;
- no report labels this result full ISA/MMU/Linux signoff beyond the tested
  contract.

## 6. Tracking checklist

- [ ] Storage-safe run root and free-space manifest captured
- [ ] Temporary v17 captures audited and scoped cleanup completed
- [ ] Fresh baseline and `git diff --check` recorded
- [ ] Direct-JAL and CPU gates pass freshly
- [ ] Capture completion markers and identity checks verified
- [ ] 5k differential completes
- [ ] 20k differential completes
- [ ] Former JAL window passes post-fix
- [ ] Linux marker/progress gate completes
- [ ] `phase3-complete` completes
- [ ] Compact closure report and residual-risk list published

## 7. Immediate next command sequence

```bash
RUN_ROOT=/data/disk/tmp/mips32-soc/v18-linux-differential
mkdir -p "$RUN_ROOT"
git diff --check
df -h / /data/disk
make rtl-frontend-compile
make direct-jal-gate
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
```

Only after these complete should the bounded QEMU/RTL Linux differential start.
Do not claim closure from a producer-only trace or an older v17 run.
