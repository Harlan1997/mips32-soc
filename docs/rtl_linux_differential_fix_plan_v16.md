# RTL Linux Differential Fix Plan v16

Plan date: 2026-09-22  
Status: `OPEN / FIRST POST-DEVTMPFS ARCHITECTURAL DIVERGENCE`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v15.md`

## 1. Objective

Close the current generic RTL Linux blocker with one evidence-backed owner
fix. The exact v14 guest, rerun from current source, reaches
`devtmpfs: initialized`, accepts timer interrupts, wakes from `WAIT`, and
returns through `ERET`, but terminates at:

```text
classification=WAIT_FUTURE_TIMER
pc=88a55d98
resume=88002380
epc=88002380
badv=c0000010
```

It does not yet reach `/init` or the generic userspace markers. The next
milestone is not a timeout adjustment or another broad RTL change. It is a
fresh, joined RTL/QEMU retirement window that identifies the first incorrect
architectural event after `devtmpfs`, then validates exactly one owner-scoped
repair.

This plan covers bounded generic Linux progress and bounded system-mode
differential evidence. It does not claim full MIPS32, full privileged ISA,
FPU, unrestricted Linux, or production SoC signoff.

## 2. Frozen evidence and constraints

The canonical guest identity for the next investigation is:

```text
kernel: /data/disk/tmp/mips32-soc/plan-v12-deterministic-differential-20260922/kernel-random/kernel/vmlinux
image:  /data/disk/tmp/mips32-soc/plan-v13-rtl-wait-timer-20260922/baseline-diagnostic/image
seed:   00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff
```

The current exact rerun is retained under:

```text
/data/disk/tmp/mips32-soc/v15-exact-v14-current-20260922
```

Known constraints:

- Preserve default `MMU=0`, blocking L1/D-cache behavior, x1 QSPI, and the
  existing boot-image contract.
- Keep nonblocking L1 and other expanded modes opt-in.
- Do not modify timer frequency, `lpj`, Count/Compare semantics, WAIT policy,
  host timeout, marker rules, or QEMU comparison tolerance to manufacture
  progress.
- Do not change LL/SC reservation behavior: the observed `down_write()` SC
  succeeds with a matching reservation and architectural result `1`.
- Do not change cache/DDR behavior unless a complete request-to-commit trace
  proves a first memory-visibility mismatch. The observed line at
  `0x08c38000` currently has no proven lost write.
- Keep large logs and simulator outputs under `/data/disk/tmp/mips32-soc`; keep
  only manifests, compact reports, and links in the repository.

## 3. Closure definition

The current blocker is closed only when all of the following are true:

1. A fresh current-source RTL run and fresh QEMU system-mode run use identical
   guest/configuration manifests.
2. Both produce complete, sequence-validated architectural windows covering
   the first post-`devtmpfs` idle entry, wakeup, interrupt entry, and `ERET`.
3. A comparator identifies the first mismatch by retired PC and occurrence,
   with explicit classification as control flow, CP0/exception metadata,
   register state, memory response, or device transaction.
4. A minimal reproducer fails before the selected fix and passes after it.
5. The fix changes one owner boundary only and preserves existing directed
   regressions.
6. The blocking RTL Linux run reaches `/init` and all declared markers, or the
   result remains `OPEN` with the unobserved boundary named.
7. The bounded QEMU differential is fail-closed: incomplete traces, stale
   artifacts, missing markers, simulator/QEMU errors, and unsupported state
   cannot be reported as pass.

## 4. Execution plan

### Phase 0: freeze and validate the baseline

Create a new run directory with:

- git commit plus dirty-worktree hash;
- RTL defines, VCS version, seed, cycle bound, and exact command lines;
- SHA-256 for kernel, DDR image, boot ROM, DTB, QEMU binary, plugins, and
  scripts used by the run;
- complete RTL UART/progress log and QEMU UART/progress log;
- exit status, timeout classification, and terminal-marker status.

Run the retained source gates without changing RTL:

```bash
git diff --check
source /etc/profile.d/modules.sh
module load vcs
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Any unrun check is recorded as `NOT_RUN`; no result is inferred from a prior
commit or a stale build directory.

### Phase 1: instrument the first interrupt/delay-slot boundary

The suspected boundary is around the current run's records near cycles
`13089585` and `13304963`, where WB contains a control transfer and EX/ID may
contain its architectural delay slot. Before changing RTL, add a bounded
diagnostic record for every candidate event containing:

```text
cycle, retire_seq, pc, instruction
wb_pc, ex_pc, id_pc, mem_pc
interrupt_delay_slot, interrupt_except_bd, exception_bd
except_pc, epc, cause, status, exception_flush, eret
wait_enter, wait_resume
```

Capture the record at the architectural exception/retirement decision edge,
not only at an earlier pipeline stage. The diagnostic must distinguish:

- branch in WB with delay slot in MEM, EX, or ID across a bubble;
- sequential instruction with no control-transfer relation;
- asynchronous interrupt versus synchronous exception;
- exception entry versus replay and subsequent `ERET`.

Acceptance: one fresh RTL trace identifies the first interrupt event after
`devtmpfs` and reports the values of `except_pc`, `exception_bd`, CP0 EPC, and
Cause.BD from the same event.

### Phase 2: produce a common QEMU architectural window

Run QEMU system mode with the same canonical guest and machine configuration.
Extend the existing state/retire capture so the comparison window includes:

- retired PC, instruction, sequence number, and exception/interrupt events;
- EPC, Cause.BD, status, pending/active interrupt state, WAIT and ERET;
- `r2`, `r3`, `r4`, `r5`, `r25`, `r29`, and `r31` at matching checkpoints;
- memory request/response information where the QEMU model exposes it;
- terminal markers and clean plugin/QEMU exit status.

The comparator joins by retired PC plus occurrence index, never by cycle.
Malformed records, duplicate sequence numbers, missing event fields, stale
artifact hashes, or an incomplete prefix produce `INVALID_INPUTS`, not pass.

Acceptance: the first mismatch is named in a compact report and is reproducible
with the same manifest on a second run.

### Phase 3: classify the owner

Use this decision table before editing RTL:

| First mismatch | Owner boundary | Required proof |
| --- | --- | --- |
| PC or instruction stream | fetch, branch target, delay-slot recognition, flush/replay | matched retire records plus a control-flow reproducer |
| `except_pc` or `Cause.BD` | interrupt delay-slot metadata or exception entry | same-event pipeline and CP0 record |
| CP0 EPC/Cause differs but pipeline relation is correct | CP0 sampling/priority or ERET metadata | exception-entry/return reproducer |
| GPR differs before the interrupt | forwarding, writeback, replay, or memory response | producer retire record and dependency reproducer |
| load/store value differs with equal CPU state | D-cache, translation, byte lane, or DDR visibility | request, response, line ownership, writeback, and commit trace |
| RTL and QEMU agree through idle but RTL lacks `/init` | later scheduler/device/image boundary | extend the same joined window; do not relabel timeout |

The interrupt/delay-slot path is the leading hypothesis because the current
trace shows a WB control transfer near the first suspect event, but it remains
unproven until `except_pc`, `exception_bd`, EPC, and Cause.BD are correlated.

### Phase 4: add one minimal reproducer

Add only the reproducer for the selected owner:

- control transfer in WB with delay slot in EX/ID and asynchronous interrupt;
- interrupt entry followed by `ERET` and exact resume target;
- synchronous exception in a delay slot as a negative case;
- task-state cache/refill sequence only if the first mismatch is proven to be
  memory visibility;
- successful LL/SC as a regression guard, never as a presumed fix target.

The reproducer must check retired PC, EPC, Cause.BD, committed registers,
memory effects, and terminal state. It must fail before the fix for the exact
diagnosed condition.

### Phase 5: apply one owner-scoped fix and regress

Modify only the proven owner. Candidate changes may be limited to delay-slot
classification, exception metadata propagation, CP0 entry sampling, ERET
resume state, or a proven cache/DDR ownership transition. Do not combine CPU,
CP0, cache, MMU, timer, and device changes in one patch.

After the fix, run:

```bash
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Then rerun the minimal reproducer, the exact canonical Linux guest, and the
fresh QEMU comparison. A directed pass without `/init` and the declared
markers is not generic Linux closure.

### Phase 6: close or reclassify the Linux boundary

The blocking Linux gate must observe, in order:

1. `devtmpfs: initialized`;
2. serial and init-task handoff;
3. `/init` execution;
4. declared process, timer/sleep, GPIO, and entropy markers;
5. no panic, oops, unresolved transaction, or simulator error.

The opt-in nonblocking L1 result is reported separately and cannot substitute
for the blocking baseline.

### Phase 7: bounded differential signoff

Use the available QEMU 9.2.0 `mips32-soc-ref` system binary and record its
provenance. Require complete manifests, valid lifecycle/exit status, matching
terminal markers, and a sequence-validated architectural comparison.

Allowed result values:

```text
BOUNDED_PASS | MISMATCH | INVALID_INPUTS | OWNER_UNOBSERVED | NOT_RUN
```

The report must list residual gaps explicitly. It must not claim full
ISA/MMU/Linux equivalence from checkpoint-only, stale, or timeout-only data.

## 5. Required artifacts

- immutable run manifest and SHA-256 artifact list;
- current-source RTL baseline report and all gate logs;
- post-`devtmpfs` RTL/QEMU joined retirement window;
- interrupt/CP0 boundary report with `except_pc`, EPC, BD, and Cause;
- owner-classification report and minimal reproducer;
- before/after simulation logs for the one owner-scoped fix;
- generic Linux marker report;
- QEMU provenance, lifecycle, and bounded differential report;
- residual-risk and explicitly unrun-check list.

## 6. Tracking checklist

- [ ] Current-source baseline frozen with canonical manifest
- [ ] First post-`devtmpfs` interrupt event captured at decision edge
- [ ] `except_pc`/EPC/`exception_bd`/Cause.BD correlated
- [ ] Fresh QEMU system window generated from identical inputs
- [ ] First mismatch joined by PC and occurrence
- [ ] Owner classified before RTL modification
- [ ] Minimal reproducer fails before the selected fix
- [ ] One owner-scoped fix implemented and all required gates pass
- [ ] Blocking RTL reaches `/init` and declared userspace markers
- [ ] Nonblocking result separately classified
- [ ] Bounded QEMU differential passes fail-closed criteria
- [ ] Residual scope and unrun checks recorded without overclaiming

## 7. Explicitly out of scope for this plan

Full MIPS32/FPU and privileged-ISA compliance, unrestricted demand paging and
SMP shootdown stress, full ISA/MMU/QEMU differential, complete Linux device
model breadth, production DDR PHY/JEDEC timing, QSPI device timing, STA/DFT,
CDC/RDC signoff, and board-level validation remain separate work.
