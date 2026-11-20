# RTL Linux Differential Fix Plan v6

Plan date: 2026-09-21  
Status: `OPEN / EXECUTION REQUIRED`  
Owner: RTL CPU/CP0, Linux boot verification, QEMU system-mode reference

## 1. Review conclusion

The latest work contains substantive fixes and diagnostic infrastructure, but
it does not yet close the generic RTL Linux or QEMU/RTL differential boundary.
The current source now includes:

- delay-slot interrupt detection through WB, EX, and ID pipeline placement;
- suppression of the erroneous sequential EPC path for a WB control transfer;
- BadVAddr fault ownership metadata and assertions;
- QEMU focused architectural-register capture;
- an opt-in QEMU retire-clock mode and RTL retire counter; and
- strict checker/unit-test entry points for focus, peripheral, and timer traces.

Those changes are implementation progress, not closure evidence. The most
important remaining gap is that the first architectural divergence has not
been established from a fresh, complete, current-source QEMU-versus-RTL
retire trace. The sparse retire-clock comparison currently reaches an
approximate boundary near retire sequence 190,000, but reports both matches
and mismatches and cannot identify the exact first bad instruction.

The project must therefore remain `OPEN`. No report may claim generic RTL
Linux userspace, unrestricted system differential, full ISA compliance, or
full MMU/OS closure until the gates in this plan pass.

## 2. Current status

| Area | Current assessment | Next proof |
| --- | --- | --- |
| RTL frontend compile | Fresh `8/8 PASS` reported | Repeat after any RTL edit |
| QEMU custom machine boot | QEMU reaches Linux boot and GPIO marker | Fresh manifest with exit status |
| QEMU retire-clock | Implemented as diagnostic opt-in | Verify trace schema and reset/offset contract |
| RTL Linux checkpoint | Pre-`WAIT` progress observed; no `WAIT` records | Exact retire comparison and targeted fix |
| Delay-slot repair | Candidate RTL fix present | Direct WB-to-EX and WB-to-ID coverage |
| BadVAddr repair | Owner metadata and SVA present | Fault/replay owner gate from current source |
| Focus differential | Checker tests pass; real run is incomplete | Complete bounded prefix with first mismatch |
| Generic RTL `/init` | Not proven | `rtl-linux-generic-init-gate` |
| Generic RTL userspace | Not proven | `rtl-linux-generic-userspace-gate` |
| Full QEMU/RTL system differential | Not proven | Strict complete-record gate |

The old blocker review and v5 plan remain historical evidence. This document
is the execution authority for the next fix cycle.

## 3. Non-negotiable run rules

All large artifacts go below `/data/disk/tmp/mips32-soc`. Every run must use a
new run directory and write a manifest before simulation. The manifest must
include:

- Git commit, dirty-worktree status, and hashes of all source inputs used;
- kernel, DTB, Boot ROM, DDR image, QEMU binary, plugin source and plugin
  binary SHA-256 values;
- RTL defines, QEMU machine properties, CPU model, command line and plusargs;
- cycle, record, byte, and wall-clock limits;
- tool versions and module environment;
- child process exit codes and an explicit terminal reason; and
- whether each artifact was freshly built or intentionally reused.

Artifact reuse is invalid unless an exact manifest match is proven. A timeout,
truncated trace, simulator crash, QEMU assertion, or hidden child failure is a
failure, not a bounded pass.

The default blocking CPU/cache path remains the reference baseline. The
nonblocking L1 path is tested separately and must not change the default
configuration to make Linux progress.

## 4. Execution plan

### Phase 0: freeze and validate the current implementation

Run the static and directed prerequisites from the current worktree:

```text
git diff --check
bash -n tb/isa_ref/run_qemu_linux_differential_gate.sh
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
make linux-timer-clock-comparison-test
make focus-differential-checker-test
make peripheral-differential-checker-test
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-frontend-compile
```

Before VCS commands, load the EDA environment:

```text
source /etc/profile.d/modules.sh
module load vcs
```

Acceptance: all prerequisites pass from current source, logs are fresh, and
the manifest records the exact source state. A pass from `f899620` alone is
not sufficient while the worktree is dirty.

### Phase 1: produce an exact bounded retire prefix

Fix the existing Linux differential runner so that it cannot fail before
capture without identifying the failing child command. Preserve stdout,
stderr, exit code, and terminal reason for the RTL runner, QEMU runner, and
comparator separately.

Run QEMU and blocking RTL with the same kernel, DTB, Boot ROM, DDR image, and
architectural options. Use the diagnostic retire-clock mode only as the
declared Count normalization; do not compare its artificial Count value as
if it were physical RTL cycle time.

Capture at least 200,000 complete records or stop at an explicit architectural
boundary. Each record must contain:

```text
sequence, PC, instruction, phase, selected GPRs, HI/LO,
committed writeback, CP0 fields when changed, exception metadata,
memory effect when committed, and terminal state
```

The RTL record must originate at architectural commit. A cycle number is
diagnostic only and must not be used as the QEMU alignment key.

Acceptance: both traces have a complete terminal record, unique contiguous
sequences, no malformed or partial lines, and an identical declared prefix
length or boundary. The run report must distinguish build failure, simulator
failure, timeout, record-limit stop, and architectural mismatch.

### Phase 2: classify the first divergence

Compare the exact prefix with strict ordering and full selected-state checks.
The first mismatch is classified as follows:

| First mismatch | Implementation owner | Required targeted test |
| --- | --- | --- |
| PC or instruction | fetch, branch redirect, delay slot, flush, replay | branch/exception recovery gate |
| `a0`, `t9`, `sp`, or call/return state | forwarding, writeback, stack access, replay | dependent-register and call/return test |
| ALU result with equal operands | execute/retire datapath | directed ALU and Linux checkpoint |
| load value or memory effect | byte lane, cache, MMU, memory image | committed memory transaction comparison |
| Count/Compare/IP | CP0 clock, timer or interrupt composition | timer Compare/mask/periodic test |
| EPC/BD/vector/ERET | precise exception and delay-slot recovery | CP0 entry/return regression |
| BadVAddr owner | fault token, replay, exception priority | owner identity and fault/replay gate |
| no mismatch within bound | workload or bound is insufficient | extend bound; retain `OPEN` |

Do not change Linux `lpj`, timeout constants, UART behavior, cache defaults,
or MMU policy before this classification. A QEMU userspace marker is not
evidence that RTL has reached the same architectural state.

### Phase 3: apply one owner-scoped fix

Change only the module selected by Phase 2. Every fix must include:

1. a minimal positive directed test;
2. a negative, reset, replay, or backpressure case as applicable;
3. the focused differential prefix rerun; and
4. the root-cause checkpoint rerun from the same manifest inputs.

For the currently most likely branches:

- If the first difference is at the branch/exception boundary, directly cover
  `interrupt_wb_branch_delay_from_ex` and
  `interrupt_wb_branch_delay_from_id`, including taken, not-taken, `jr`, and
  stale-stage negative cases.
- If the first difference is a data fault, prove the owner PC, instruction,
  exception code, and virtual address remain paired through refill/replay and
  are cleared on squash.
- If the first difference is a register producer, compare the actual commit
  write enable/address/data and the post-commit register snapshot; do not use
  speculative WB intent as retirement evidence.

Acceptance: the original first mismatch moves past the repaired boundary or
the report proves it was not owned by the changed module. No fix is accepted
because a marker merely appears earlier.

### Phase 4: close generic RTL Linux init

After the exact prefix is clean through the selected boundary, run:

```text
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

The init gate must observe, in order:

```text
kernel entry -> early console -> ttyS0 probe -> initramfs -> /init
```

It must fail on panic, oops, assertion, APB error, simulator failure,
reordered/missing markers, incomplete traces, or nonzero child status.

Acceptance is `RTL_GENERIC_INIT_PASS` from current source with a fresh
manifest. QEMU reaching `/init` does not satisfy this phase.

### Phase 5: close bounded userspace and three-way differential

Only after Phase 4 passes, run:

```text
make rtl-linux-generic-userspace-gate
make qemu-system-linux-differential-gate
```

The declared bounded window must compare separately:

```text
QEMU vs blocking RTL
QEMU vs opt-in nonblocking-L1 RTL
blocking RTL vs nonblocking-L1 RTL
```

The gate must reject unequal complete-record counts, duplicate or reordered
sequences, missing target PCs, ambiguous repeated occurrences, partial final
records, unexpected termination, and unpaired exception or memory effects.

Acceptance is `BOUNDED_PASS` only for the explicitly named image, CPU model,
configuration, trace prefix, and terminal boundary.

### Phase 6: publish the closure report

Write a compact report under the run directory and link it from the docs. It
must include:

- manifest and source identity;
- prerequisite and directed-gate results;
- first-divergence records and owner classification;
- targeted fix and before/after evidence;
- generic init and userspace logs;
- all three differential comparisons; and
- residual risks and unsupported claims.

## 5. Definition of done

This plan is complete only when all of the following are present in fresh
artifacts:

1. a reproducible manifest and clean prerequisite results;
2. a strict complete retire prefix with a classified first difference;
3. one owner-scoped fix with positive and negative regression evidence;
4. generic RTL `/init` and declared userspace markers;
5. a bounded three-way system differential; and
6. a residual-risk report that does not overstate ISA, MMU, Linux, or product
   signoff.

Until then, status remains `OPEN`.

## 6. Explicit residual risks

This plan does not close full MIPS32 privileged ISA, FPU/IEEE-754/Linux ABI,
unrestricted demand paging or SMP shootdown, physical DDR/QSPI PHY timing,
formal/CDC/RDC/lint, synthesis/STA/DFT, board validation, or unbounded
QEMU/RTL equivalence. Those require separate product-level plans and evidence.
