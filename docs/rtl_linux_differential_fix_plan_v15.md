# RTL Linux Differential Fix Plan v15

Plan date: 2026-09-22  
Status: `OPEN / POST-DEVTMPFS SCHEDULER-TASK STATE INVESTIGATION`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v14.md`

## 1. Objective

Close the next proven RTL Linux userspace boundary without making a speculative
CPU, cache, timer, or LL/SC change. The current run reaches
`devtmpfs: initialized`, accepts timer interrupts, wakes from `WAIT`, returns
through `ERET`, and executes a successful `SC` in the observed `down_write()`
window. It still does not reach `/init` or the declared generic-userspace
markers.

The immediate goal is to identify the first incorrect architectural event
after the kernel reaches the post-`devtmpfs` scheduler/init handoff, assign it
to one RTL owner, and close it with a minimal reproducer and one owner-scoped
fix. This remains a bounded RTL Linux progress and differential plan; it is
not a claim of full MIPS32, full Linux, or unrestricted QEMU equivalence.

## 2. Evidence baseline

| Boundary | Current result | Interpretation |
| --- | --- | --- |
| RTL frontend and CPU/CP0 regressions | Existing gates pass in the retained baseline | Re-run from current source before signoff |
| Count/Compare readback | 0 mismatches, 0 unexpected backsteps | No current evidence that Count is the blocker |
| Timer interrupt delivery | 102 accepted interrupts in the 30M-cycle diagnostic | Timer delivery is active |
| `WAIT`/`ERET` | Repeated wake and return observed | A generic WAIT deadlock is not demonstrated |
| Observed `down_write()` `SC` | Reservation match, write enabled, retired result `1` | Do not patch SC failure or reservation lifetime speculatively |
| Generic RTL Linux | Reaches `devtmpfs: initialized`; no `/init` | Primary open boundary |
| Bounded end state | `WAIT_FUTURE_TIMER`, PC `0x88a55d98`, resume `0x88002380` at 15M cycles | Scheduler/task-state or later memory visibility remains open |
| QEMU system reference | Binary/source available under `/data/disk/tmp/mips32-soc/qemu-9.2.0` | Run only with fresh identity and complete logs |
| Strict RTL/QEMU differential | No valid terminal-marker pair | Open |

The current focused cache-owner evidence for physical line `0x08c38000`
contains a refill with words `0=0x88c53200` and `1=0x00100000`, followed by
stores to offsets `0x10` and `0x14`. Repeated reads of offset `0x04` return
`0x00100000`, but no first cache-to-DDR mismatch has yet been established.
This is a lead, not a root-cause claim.

## 3. Invariants and non-goals

- Preserve default `MMU=0`, blocking L1/D-cache behavior, x1 QSPI, and current
  firmware/image contracts.
- Keep nonblocking L1, expanded Linux options, and diagnostic entropy modes
  opt-in unless a separate contract is approved.
- Do not change timer frequency, `lpj`, Count/Compare tolerance, WAIT policy,
  host timeout, or marker rules to manufacture progress.
- Do not change LL/SC reservation matching or clearing unless a new trace proves
  an LL/SC mismatch before the first scheduler/task-state mismatch.
- Do not call a timeout, UART silence, or a bounded PC heartbeat a userspace
  pass. The guest must emit the declared markers.
- Keep simulator, QEMU, and large trace artifacts under
  `/data/disk/tmp/mips32-soc`; retain hashes and compact reports in the run
  directory.

## 4. Execution phases

### Phase 0: freeze the current post-fix baseline

Create a fresh run root and record:

- git commit and complete dirty-worktree identity;
- RTL defines, VCS version, compile/run commands, seed, and cycle bound;
- kernel, DTB, boot ROM, DDR image, QEMU binary, and plugin hashes;
- exact UART transcript, progress trace, terminal classification, and exit code;
- the `devtmpfs` line, first `WAIT_FUTURE_TIMER` state, and the surrounding
  PC/CP0/interrupt records.

Run without changing RTL:

```bash
git diff --check
source /etc/profile.d/modules.sh
module load vcs
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Acceptance: the report reproduces the post-`devtmpfs` terminal boundary or
explains an input/configuration mismatch. Every unrun check is recorded as
`NOT_RUN`, never inferred as pass.

### Phase 1: make the first post-`devtmpfs` divergence observable

Extend the existing RTL progress/retirement trace for a bounded window from
the final `devtmpfs` message through the first two scheduler idle transitions.
Record, at architectural retirement or an explicitly identified commit edge:

```text
cycle, retire_seq, pc, instruction,
interrupt_accept, exception_flush, epc, cause_bd, status,
wait_enter, wait_resume,
gpr r2/r3/r4/r5/r25/r29/r31,
load/store virtual address, physical address, byte enable, data,
cache hit/miss/refill/writeback/ownership event,
timer count/compare and pending/active interrupt bits
```

For the task-state line at `0x08c38000`, normalize all records by physical
line, word offset, byte enable, and architectural sequence. The parser must
reject duplicate sequence numbers, missing address/data fields, ambiguous
cache ownership, and a read reported without a response or committed value.

Acceptance: one fresh run identifies the last retired instruction before the
first idle entry and the first instruction after wakeup, plus every read,
store, refill, and writeback touching offsets `0x04`, `0x10`, and `0x14`.

### Phase 2: classify ownership before changing RTL

Compare the RTL window against a fresh QEMU system-mode run using the same
kernel, DTB, command line, seed, and machine configuration. Join by retired
PC and occurrence index, not cycle number. Use this decision table:

| First mismatch | Owner to investigate | Required proof |
| --- | --- | --- |
| PC/instruction stream | branch delay slot, exception replay, fetch flush | Matching retire trace and a directed control-flow/interrupt test |
| `WAIT`/resume or EPC/BD differs | interrupt priority, CP0 entry, or ERET metadata | CP0 record at entry and return, including BD and pending bits |
| Task-state load differs | D-cache response, byte lane, translation, or DDR contents | Request, response, cache line, writeback, and committed GPR value |
| CPU store differs or never reaches DDR | store operand, byte enable, D-cache ownership/writeback | One-line memory-owner trace from CPU request to DDR commit |
| Cache and DDR agree but scheduler diverges | exception replay, memory ordering, or Linux-visible CPU state | Retired state plus all relevant barriers/interrupt boundaries |
| RTL and QEMU agree through idle but no `/init` | image/DTB/device model or an unobserved later boundary | Extend the window; do not relabel the timeout as success |

The `0x08c38000` line is only the first candidate because it is already
observable. It becomes the owner only if the first divergence is a cache or
memory visibility mismatch. A successful `SC` must remain classified as
successful unless a later complete trace disproves the retirement record.

### Phase 3: add a minimal reproducer

Before any RTL behavior change, add the smallest failing test for the selected
owner:

1. task-state line refill, stores to offsets `0x10`/`0x14`, and a later read of
   offset `0x04`;
2. store-to-writeback under timer interrupt and `WAIT` entry;
3. refill/writeback collision with backpressure and reset/flush-in-flight;
4. precise interrupt during a control transfer and subsequent `ERET`, if the
   first mismatch is control flow or CP0;
5. the exact successful LL/SC sequence only as a regression guard, not as a
   presumed failure.

Each reproducer checks the committed PC, register value, memory effect,
cache/DDR ownership, and terminal state. It must fail before the fix when the
diagnosed RTL owner is exercised.

### Phase 4: apply one owner-scoped fix

Change only the proven owner. Candidate fixes include a missing writeback,
store byte-enable/merge error, stale cache-line ownership transition, fault or
interrupt replay metadata error, or CP0 wake/return metadata error. Do not
combine cache, CPU, CP0, MMU, and device changes in one patch.

Required regression after the fix:

```bash
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Then run the minimal reproducer, the exact frozen generic Linux image, and the
focused QEMU comparison. A unit pass without a later `/init` marker is not
closure.

### Phase 5: close the generic RTL Linux gate

Run the default blocking baseline first. The gate must verify, in order:

1. kernel initialization through `devtmpfs`;
2. serial and init-task handoff;
3. `/init` execution;
4. declared process, timer/sleep, GPIO, and entropy userspace markers;
5. no panic, oops, unresolved transaction, or simulator error.

Run the opt-in nonblocking L1 configuration separately and report it as a
compatibility result. It cannot substitute for the blocking baseline.

### Phase 6: rerun the bounded system-mode differential

Use the available official QEMU 9.2.0 system binary/source and record its
provenance. Require matching manifests, complete retire records, valid exit
status, and guest terminal markers. The result vocabulary is:

```text
BOUNDED_PASS | MISMATCH | INVALID_INPUTS | OWNER_UNOBSERVED | NOT_RUN
```

The gate must fail closed on incomplete traces, stale artifact identity,
missing markers, QEMU/plugin failure, RTL timeout, or unsupported state. It
must not claim full ISA/MMU/Linux equivalence.

## 5. Required artifacts

- immutable run manifest and SHA-256 artifact list;
- compact post-`devtmpfs` RTL and QEMU retire traces;
- normalized `0x08c38000` cache/DDR ownership report;
- first-divergence and owner-classification report;
- minimal reproducer source, compile log, and simulation log;
- frontend, CPU/CP0, delay-slot, Phase 3, and generic-userspace reports;
- QEMU provenance and system-mode terminal report;
- residual-risk and explicitly unrun-check list.

## 6. Tracking checklist

- [ ] Fresh post-fix baseline and manifest captured
- [ ] Post-`devtmpfs` retirement/CP0/cache observability complete
- [ ] `0x08c38000` read/store/refill/writeback ownership classified
- [ ] First mismatch joined against fresh QEMU state
- [ ] Minimal reproducer fails for the selected owner
- [ ] One owner-scoped RTL fix implemented, if required
- [ ] Frontend, CPU/CP0, delay-slot, and Phase 3 gates pass
- [ ] Blocking RTL reaches `/init` and all declared userspace markers
- [ ] Nonblocking result separately classified
- [ ] Bounded QEMU/system differential is fail-closed and valid
- [ ] Residual scope and unrun checks recorded without overclaiming

## 7. Residual scope

This plan does not close full MIPS32/FPU or privileged-ISA coverage, complete
demand paging and SMP shootdown stress, full ISA/MMU/QEMU differential, Linux
device-model breadth, production DDR PHY/JEDEC timing, QSPI device timing,
STA/DFT, CDC/RDC signoff, or board-level validation.
