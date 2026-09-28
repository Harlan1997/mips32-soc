# RTL Linux Differential Remediation Plan

Plan date: 2026-09-20

Status: `GENERIC RTL LINUX DECLARED USERSPACE CLOSED / FULL DIFFERENTIAL OPEN`

## 1. Objective and current non-claims

This plan replaces the unsupported closure interpretation in
`docs/rtl_linux_userspace_blocker_review.md`. The delay-slot interrupt diagnosis
is useful evidence, but the current focus gate is not sufficient to sign off
generic RTL Linux, BadVAddr replay, UART/VIC equivalence, or a full QEMU/RTL
architectural differential.

Until the acceptance criteria in this document pass from current source, the
project status is:

| Capability | Current status | Maximum supported claim |
| --- | --- | --- |
| Delay-slot interrupt root cause | `BLOCK_REDUCED` | A plausible fix exists and existing directed gates pass, but the new WB-to-EX and WB-to-ID cases lack direct coverage. |
| Generic RTL Linux declared userspace workload | `CLOSED` | The current-source seeded terminal gate reaches `/init` and all declared userspace markers in order with a clean simulator terminal stop. Unrestricted Linux and full RTL/QEMU differential remain separate open contracts. |
| BadVAddr fault/replay | `OPEN` | Literal `0xffffffff` is absent in one focus window; instruction ownership and replay identity are not proven. |
| QEMU/RTL focus comparison | `UNTRUSTED` | Two checkpoint comparisons exist, but truncation and unselected-register mutations can falsely pass. |
| Bounded full retire differential | `OPEN` | Existing bounded differential infrastructure is useful, but this new generic Linux focus gate does not perform a complete architectural comparison. |
| UART/VIC equivalence | `OPEN` | The focus gate does not compare UART or VIC transactions. |
| Minimal RTL userspace profile | `BOUNDED_PASS` | Only the existing opt-in minimal image and its declared marker contract are covered. |

Passing a bounded gate must not be described as unrestricted Linux, complete
ISA/MMU behavior, product signoff, or a full-system differential.

## 2. Evidence baseline

The remediation starts from branch `product-boot-expansion`, base commit
`f899620`, plus the worktree changes under review. Because those changes are
not represented by the base commit, retained artifacts that identify only
`f899620` are stale for signoff purposes.

Known defects in the current implementation and gate are:

1. `d_fault_vaddr_pending_q` can outlive a younger fault that was squashed by
   an older exception, allowing unrelated later exceptions to consume stale
   fault state.
2. The focus runner reuses old logs and a precompiled nonblocking simulator by
   default, and rebuilds its plugin only when the shared object is absent.
3. The comparator accepts unequal trace lengths and checkpoint mode compares
   only a subset of the selected GPRs.
4. The QEMU plugin reads vCPU registers from its exit callback, where no current
   vCPU is guaranteed; QEMU can assert in `plugins/api.c`.
5. BadVAddr validation rejects only one literal value and does not pair a fault
   with the owning instruction and replay.
6. The RTL focus monitor bypasses WB data based on architectural-valid and
   register-write intent rather than actual commit, so an excepting or squashed
   write can be reported as retired state.
7. The WB-branch-to-EX-delay-slot and WB-branch-to-ID-delay-slot recovery terms
   are not covered by the current directed regression.

All new build and simulation artifacts must be rooted under
`/data/disk/tmp/mips32-soc` to avoid pressure on `/`.

## 3. Execution order

The phases below are ordered by dependency. A later phase may be developed in
parallel, but it cannot be accepted using evidence from an incomplete earlier
phase.

### Phase 0: correct status and freeze reproducible inputs

Update `docs/rtl_linux_userspace_blocker_review.md` and the functional evidence
registry so they use the statuses in Section 1. Preserve the old observations
as historical evidence; remove only unsupported closure language.

Add a machine-readable manifest to every differential run containing:

- Git commit, branch, dirty status, and a deterministic hash of tracked and
  untracked source inputs used by the build.
- SHA-256 for the kernel, DTB, Boot ROM, DDR image, QEMU binary, plugin source,
  plugin shared object, RTL file list, and generated simulator.
- QEMU machine, CPU, command line, plugin arguments, RTL defines, plusargs,
  cycle bounds, and host timeout.
- VCS, compiler, Python, QEMU, and host tool versions.
- Start/end timestamps and unmasked process exit statuses.

Fresh current-source compile and execution must be the default. Artifact reuse
must require an explicit `REUSE_ARTIFACTS=1` and an exact manifest match. A
missing field, dirty-source mismatch, changed tool version, changed option, or
changed input hash invalidates reuse.

Acceptance:

- A run from a dirty worktree cannot claim the base commit alone.
- A deliberately changed RTL file, plugin source, define, or image causes reuse
  to be rejected.
- Completion reports link to the manifest and label fresh versus reused steps.

### Phase 1: make BadVAddr ownership precise

Replace the untagged pending-address latch with fault ownership metadata. The
minimum token contains:

- valid bit and monotonically distinguishable instruction/flush generation;
- faulting PC and instruction word;
- effective virtual address and exception code;
- data access type and, where relevant, ASID/context identity;
- pipeline or ROB owner identity used to match the eventual WB exception.

Required behavior:

- Capture the first accepted data translation fault for its owner and hold it
  across stalls or replay of that same instruction.
- Use the saved address only when the committing data exception matches the
  saved owner.
- Clear the token when that exact fault commits, or when an older exception,
  ERET, reset, context restore, or explicit squash proves the owner cannot
  commit.
- Do not let a younger fault overwrite a live older owner.
- Do not let a squashed younger fault supply BadVAddr to a later instruction.
- Give synchronous translation faults documented priority over asynchronous
  interrupts without retaining metadata for instructions the interrupt or an
  older exception actually squashes.

Add assertions for capture stability, owner-match consumption, squash clear,
single-owner behavior, and `BadVAddr == owner.virtual_address` at CP0 commit.

Required directed tests:

- First fault, refill/replay, then matching exception commit.
- Older WB exception with a younger MEM translation fault in the same window;
  prove the younger token is discarded.
- A later unrelated data exception after that squash; prove stale state is not
  consumed.
- Interrupt coincident with a data translation fault.
- Back-to-back faults from different PCs and addresses.
- Reset, ERET, and context restore while a token is live.

Create `make cpu-badvaddr-owner-gate`. It must fail on PC, instruction, address,
exception-code, or owner-token mismatch, not only on a prohibited address
literal.

### Phase 2: close delay-slot bubble coverage

Extend `cpu-irq-delay-slot-gate` with explicit pipeline-placement tests for:

- A control transfer in WB, invalid MEM bubble, and its architectural delay
  slot in EX.
- A control transfer in WB, invalid MEM and EX bubbles, and its delay slot in
  ID.
- Taken and not-taken conditional branches, plus `jr`/`jalr` where supported.
- Positive cases with an interrupt accepted at each placement.
- Negative adjacency: sequential PCs that are not a branch/delay-slot pair.
- Replay and stale-stage cases that must not manufacture `Cause.BD`.
- An older synchronous exception that must beat the asynchronous interrupt.

Each positive test must check interrupt acceptance, `except_pc`, `Cause.BD`,
EPC, ERET resume PC, and one canary write after return. Functional coverage
must directly hit `interrupt_wb_branch_delay_from_ex` and
`interrupt_wb_branch_delay_from_id`; line or expression coverage alone is not
sufficient.

Acceptance:

- Both recovery terms are observed in the directed coverage report.
- Every negative case leaves the recovery term deasserted.
- `make cpu-cp0-gate`, `make cpu-irq-delay-slot-gate`, and frontend compile pass
  from the same source manifest.

### Phase 3: repair the QEMU plugin lifecycle

Do not call `qemu_plugin_read_register()` from `plugin_exit`. Read registers
only in callbacks with a valid current vCPU and cache the last complete record
per vCPU. The exit callback may flush cached bytes and summary counters, but it
must not query live vCPU state.

Define record semantics explicitly:

- `phase=pre` means state immediately before the named instruction.
- `phase=post` means state after that instruction has executed and before the
  next architectural instruction.
- Every record has vCPU ID, sequence, occurrence index, PC, instruction, and
  all selected GPRs.
- Partial records are marked incomplete and cannot satisfy a gate.

The runner must preserve QEMU's status. Accept a timeout only when the gate
declares a bounded timeout contract, the status is the expected timeout code,
all required records were flushed before termination, and logs contain no
assertion, signal, abort, or fatal error. Other nonzero statuses fail.

Add plugin unit/integration tests for normal guest exit, expected timeout,
record-limit exit, missing target PCs, and forced plugin failure. Rebuild the
plugin whenever its source, QEMU headers, compiler identity, or flags change.

Acceptance: no `current_cpu` assertion appears, crash statuses cannot be
masked, and a clean run has an internally consistent final sequence count.

### Phase 4: make RTL focus records represent real retirement

Generate focus records only from the actual architectural commit event. Use
`wb_commit_valid` and the real RF write enable/data path rather than
`wb_arch_valid && wb_reg_write` as a speculative bypass condition.

Define whether a record is pre-retire or post-retire. For post-retire records,
apply the committing write exactly once to the reported register snapshot. An
exception, rollback, killed ROB entry, or invalid WB slot must not modify the
reported post-state.

Every RTL record must include:

- global retire sequence and target-PC occurrence index;
- PC, instruction, phase, and selected GPR snapshot;
- actual committed GPR write enable/address/data;
- delay-slot, exception, EPC, Cause.BD, BadVAddr, and fault-owner token when
  those fields are valid;
- RTL cycle for diagnostics only, never for QEMU alignment.

Add monitor self-checks for contiguous sequences, exactly one record per
commit, no record on rollback/exception-only bubbles, `$zero == 0`, and correct
pre/post behavior on a write to every selected GPR class.

Acceptance: injected squashed and excepting writes do not alter the trace, and
the trace agrees with direct register-file state after committed writes.

### Phase 5: make comparison strict and test the checker

Refactor `scripts/compare_focus_differential.py` so malformed lines, missing
fields, and ambiguous alignment are errors rather than silently skipped data.

Full-trace mode must:

- Require equal complete-record counts unless a declared prefix boundary is
  present in both traces.
- Require unique, contiguous sequence numbers and valid phases.
- Compare PC, instruction, occurrence identity, all selected GPRs, and every
  architectural metadata field available on both sides.
- Reject missing required target PCs, unexpected duplicate occurrences,
  reordered occurrences, trailing records, and premature end of either trace.
- Report the first mismatch with both records and a classified owner area.

Checkpoint mode must:

- Require an explicit occurrence selector when a PC occurs more than once.
- Compare PC, instruction, phase, all selected GPRs, occurrence identity, and
  common metadata.
- Fail if the checkpoint is absent, duplicated ambiguously, malformed, or
  incomplete.

Add automated positive and negative fixtures. At minimum, prove failure for:

- one-record DUT versus a longer reference;
- mutation of each selected GPR, including `a0`;
- changed PC or instruction;
- missing target PC;
- duplicate or non-contiguous sequence number;
- reordered occurrences;
- pre/post phase mismatch;
- missing final record and extra trailing record;
- exception, EPC, BD, BadVAddr, and writeback metadata mutation when present on
  both sides.

Create `make focus-differential-checker-test`. The test is accepted only when
every negative fixture fails for the intended reason.

### Phase 6: rebuild the focus gate around fresh evidence

Change `rtl-linux-focus-differential-gate` into an aggregate of independently
reportable sub-gates:

1. `rtl-linux-root-cause-checkpoint-gate`: proves the repaired instruction
   window with strict QEMU, blocking RTL, and nonblocking RTL records.
2. `cpu-badvaddr-owner-gate`: proves fault/replay ownership independently of
   Linux console progress.
3. `rtl-linux-generic-init-gate`: requires generic RTL to bind `ttyS0` and
   execute `/init`.
4. `rtl-linux-generic-userspace-gate`: requires the declared userspace marker
   set from the same generic image.
5. `qemu-system-uart-vic-transaction-differential-gate`: compares the declared
   UART/VIC transaction contract.
6. `qemu-system-linux-bounded-retire-differential-gate`: compares every retire
   record through a bound fixed before execution.

The aggregate must compile blocking and nonblocking simulators from current
source by default. It must never select a precompiled simulator merely because
one exists. Each sub-gate writes its own log, manifest, status, and report; the
aggregate propagates the first nonzero status and summarizes all results.

Reports must use scope-specific language. For example, a strict match through
two target PCs is a root-cause checkpoint pass, not a full architectural
differential or generic Linux userspace pass.

Acceptance: stale logs, stale simulators, stale plugins, and incomplete QEMU
runs are rejected by tests, and a clean fresh run is reproducible from its
manifest.

### Phase 7: close generic Linux and peripheral behavior separately

Use one hashed generic kernel/DTB/Boot ROM/DDR set for QEMU and RTL. The image,
command line, RAM size, CPU features, timer frequency, and peripheral address
map must match or be listed as an intentional modeled difference.

The generic init gate requires ordered evidence for:

1. kernel entry and early console;
2. serial driver registration and `ttyS0` binding;
3. initramfs discovery and `/init` execution;
4. transition to the expected user mode;
5. no panic, oops, assertion, or unexpected watchdog termination.

The userspace gate adds deterministic process, VM, GPIO, timer/sleep, and exit
markers. Each marker must be emitted by guest behavior, not injected by the
testbench.

The UART/VIC differential must compare normalized transactions rather than
wall-clock cycles:

- UART address, width, byte lanes, read/write data, response, IRQ assertion and
  deassertion, and acknowledged source;
- VIC raw, mask, pending, active/source ID, priority decision, acknowledge, and
  completion/re-entry ordering;
- occurrence ordering and causal relationships, with documented normalization
  for implementation-specific idle polling.

Run blocking and nonblocking configurations independently. A nonblocking pass
does not replace the default blocking baseline, and vice versa.

### Phase 8: bounded full architectural differential

After Phases 0-7 pass, run a strict retire differential over a bound declared
before the run. The comparison begins from an agreed reset state or a fully
described architectural handoff and continues without sampled gaps to the
declared end marker.

The compared state includes, where architecturally observable:

- PC, instruction, all 32 GPRs, HI/LO, and FPU state when enabled;
- CP0 state affected by the implemented ISA contract;
- exception code, EPC, ErrorEPC, Cause.BD, BadVAddr, and mode transitions;
- committed memory operations and LL/SC outcome;
- interrupt acceptance/source ordering;
- TLB operations and translation outcomes at the agreed abstraction boundary.

Any field intentionally excluded needs a written rationale and a checker test
showing the exclusion cannot hide sequence truncation or misalignment. The
report must state the exact record count and terminal marker. This remains a
`BOUNDED_PASS`; only an explicitly defined longer-running campaign can expand
the bound.

## 4. Required regression matrix

| Area | Directed/negative gate | Integration gate | Required artifact |
| --- | --- | --- | --- |
| Source identity/reuse | manifest mutation tests | fresh focus aggregate | source/tool/input manifest |
| BadVAddr ownership | `cpu-badvaddr-owner-gate` | MMU-enabled Linux checkpoint | token and CP0 commit trace |
| Delay-slot IRQ | expanded `cpu-irq-delay-slot-gate` | generic Linux root-cause checkpoint | functional and code coverage |
| QEMU plugin | lifecycle/status tests | QEMU generic boot capture | plugin log and exit-status record |
| RTL retire monitor | squash/exception/write tests | blocking and nonblocking capture | retire trace and monitor summary |
| Comparator | `focus-differential-checker-test` | checkpoint and bounded full compare | positive/negative test report |
| Generic init | panic/timeout/missing-marker negatives | `rtl-linux-generic-init-gate` | serial log and ordered markers |
| Generic userspace | missing/reordered marker negatives | `rtl-linux-generic-userspace-gate` | guest marker report |
| UART/VIC | transaction mutation fixtures | UART/VIC transaction differential | normalized transaction traces |
| Full bounded state | truncate/reorder/mutate fixtures | bounded retire differential | first-mismatch or exact-match report |

After the focused gates pass, rerun at minimum:

```sh
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make cpu-badvaddr-owner-gate
make focus-differential-checker-test
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
make rtl-linux-generic-userspace-gate
make qemu-system-uart-vic-transaction-differential-gate
make qemu-system-linux-bounded-retire-differential-gate
```

VCS commands must load the module environment first and preserve the configured
license setting. Resource-heavy output belongs under `/data/disk/tmp/mips32-soc`.

## 5. Final acceptance criteria

The remediation is complete only when all of the following are true:

- Unsupported closure statements are downgraded and no report broadens a
  bounded result.
- Current-source fresh builds are the default and content-addressed reuse tests
  pass.
- BadVAddr is consumed only by its owning fault, including the older-exception
  and younger-fault negative case.
- Both new WB-to-EX and WB-to-ID delay-slot cases have direct functional
  coverage and precise EPC/BD/ERET checks.
- QEMU exits or times out according to an explicit contract without plugin
  assertions or masked failures.
- RTL records represent actual commits and cannot include rolled-back writes.
- Comparator adversarial tests all fail closed.
- Generic RTL reaches `ttyS0`, `/init`, and the declared userspace markers in
  separately reported gates.
- UART/VIC transaction equivalence passes independently.
- Blocking and nonblocking bounded retire streams compare strictly through the
  predeclared terminal marker with equal complete-record counts.
- All reports, logs, coverage, manifests, and residual risks are retained under
  one run root.

## 6. Residual risks after closure

Even after this plan passes, QEMU remains a software reference model rather
than an independent proof of all implementation-defined CP0, timing, cache, or
peripheral behavior. A bounded Linux run does not establish indefinite runtime
stability, complete ISA compliance, physical DDR/QSPI behavior, CDC/RDC
signoff, synthesis timing, or product release readiness. Those claims require
their own contracts and evidence.
