# RTL Linux Differential Fix Plan v19

Plan date: 2026-09-22  
Status: `OPEN / FIRST-ARCHITECTURAL-DIVERGENCE REQUIRED`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v18.md`

## 1. Purpose

Close the remaining generic Linux system-mode gap between the current RTL and
the QEMU `mips32-soc-ref` reference. The next implementation change must be
selected from joined architectural evidence, not from the terminal label alone.

This plan is narrower than full ISA, MMU, FPU, Linux, or product signoff. It
closes the currently observable blocker first and preserves the existing
blocking-cache default and opt-in feature boundaries.

## 2. Evidence baseline

| Boundary | Current result | Meaning |
| --- | --- | --- |
| RTL frontend | `PASS`, 8/8 configurations | RTL compiles and elaborates under the current source |
| Direct JAL | `PASS` | The known mismatch was retire `next_pc` metadata after a stalled delay slot |
| CPU/CP0 and IRQ delay-slot gates | `PASS` | Existing directed CPU/CP0 contracts remain green |
| Phase 3A | `PASS` | Existing UVM/directed scope is green |
| QEMU/RTL bounded differential | `PASS` at 10k and 20k records | Capture, manifest, and comparator work for the bounded pre-Linux target |
| Generic RTL Linux | `OPEN` | Current 30M-cycle replay reaches `devtmpfs`, but no `/init` marker |
| QEMU generic Linux | `PASS` for declared markers | QEMU reaches `/init` and the userspace workload |
| Full Linux differential | `OPEN` | RTL and QEMU are not yet joined through the userspace boundary |

The latest RTL terminal record is diagnostic only:

```text
classification=WAIT_FUTURE_TIMER
cycle=30000000
pc=88a55d98
resume=88002380
count=00e4e1c0
compare=00e5409f
timer_ip=0
interrupt_accept=0
```

This does not prove a timer implementation defect. It may represent a later
scheduler/task-state or memory-visibility divergence. Do not change Count,
Compare, interrupt priority, cache policy, or MMU behavior until the first
joined mismatch identifies that owner.

## 3. Closure target

The immediate target is a reproducible generic Linux checkpoint gate that:

1. uses one manifest-matched guest/kernel/image/configuration for QEMU and RTL;
2. captures comparable architectural state around the first post-`devtmpfs`
   divergence;
3. identifies the first mismatch as PC/instruction, GPR, exception metadata,
   memory/translation, or peripheral transaction;
4. applies one owner-scoped RTL or model fix with a focused regression; and
5. reaches `/init` and the declared userspace markers in RTL.

Only after this target passes may the full bounded Linux differential be called
`PASS`. It must remain `OPEN` while RTL does not reach `/init`.

## 4. Work phases

### Phase 0: freeze a reproducible run

Create a new run root below `/data/disk/tmp/mips32-soc/repo-build-20260905`
and record:

- `git status --short`, source dirty hash, RTL defines, and simulator version;
- QEMU binary, custom-machine source, and plugin hashes;
- kernel, DTB, Boot ROM, DDR image, command line, seed, RAM size, and image
  manifest hashes;
- exact commands, cycle/retire/host bounds, filesystem free space, and exit
  statuses.

Reuse an image only when its manifest matches the run inputs. Keep full traces
in `/data/disk/tmp`; retain only summaries and hashes in the repository.

Acceptance: a second run with the same manifest reproduces the same terminal
classification and last active PC. A missing marker, timeout, truncated trace,
or stale artifact is `INCOMPLETE`, never `PASS`.

### Phase 1: capture the RTL root-cause checkpoint

Run the existing diagnostic gate with current kernel/image and bounded tracing:

```bash
RUN_DIR=/data/disk/tmp/mips32-soc/repo-build-20260905/v19-root-cause \
KERNEL=<manifest-kernel> LINUX_IMAGE_DIR=<manifest-image> \
REUSE_LINUX_IMAGE=1 RTL_CYCLE_LIMIT=30000000 \
LINUX_WAIT_TRACE=1 LINUX_TIMER_HEARTBEAT=1 \
LINUX_CP0_TRACE_LIMIT=1024 LINUX_CP0_READ_TRACE_LIMIT=2048 \
tb/linux_boot/run_rtl_linux_root_cause_checkpoint_gate.sh
```

Review `timer_wait_analysis.md`, the last progress/WB records, Count reads,
CP0 writes, accepted interrupts, and the first `WAIT` transition together.
The result is a diagnostic capture, not a behavior pass.

Required classification outcomes:

- `PRE_WAIT_*`: compare the scheduler/clock loop and memory reads first;
- `WAIT_WITHOUT_ACCEPTED_INTERRUPT`: compare Count/Compare and interrupt state;
- `WAIT_WAKEUP_*`: compare the post-ERET task state and resumed instruction;
- malformed or absent evidence: repair the capture infrastructure first.

### Phase 2: capture matching QEMU architectural state

Use the QEMU focus plugin on the same guest and manifest. Focus on:

```text
0x88a55d98  0x88002380
```

and the scheduler/WAIT PCs discovered by Phase 1. Capture at least `pc`,
instruction, sequence/occurrence, `r2-r5`, `r8-r15`, `r25`, `r29`, `r31`,
CP0 Count/Compare/Status/Cause/EPC, and the relevant memory/peripheral
transactions. The plugin must label whether samples are before execution,
after execution, or at the next instruction boundary.

Acceptance: QEMU and RTL records can be joined by architectural sequence and
occurrence, not by wall-clock cycle. Missing target PCs or ambiguous sampling
phase is an invalid input.

### Phase 3: join traces and name the first owner

Add or use a bounded comparator that reports the first mismatch and compact
context. Classify exactly one first owner:

| First mismatch | Owner to investigate | Required focused proof |
| --- | --- | --- |
| PC/instruction or delay-slot metadata | fetch/redirect/flush/exception | branch, interrupt, and ERET regression |
| GPR before WAIT or after ERET | writeback/forwarding/replay | dependent-register and exception-replay test |
| Count/Compare/Status/Cause | CP0 or interrupt contract | CP0 timer/WAIT directed test and trace assertion |
| same CP0 state, different task flag/load | D-cache/memory visibility | load/store transaction and cache-owner comparison |
| same CPU state, different UART/VIC result | peripheral model/RTL APB | normalized APB/UART/VIC transaction comparison |
| fault address/translation metadata | MMU/fault ownership | precise fault/replay and BadVAddr test |

The comparator must stop at the first mismatch and must not infer ownership
from `WAIT_FUTURE_TIMER` alone.

### Phase 4: implement one owner-scoped fix

Change only the module named by Phase 3. Keep the fix diagnostic or opt-in when
it changes behavior outside the existing default contract. Add a minimal
reproducer that fails before the fix and passes after it. Do not combine timer,
cache, MMU, interrupt, and QEMU changes in one iteration.

Every fix iteration must pass:

```bash
git diff --check
make rtl-frontend-compile
make direct-jal-gate
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
```

Run the owner-specific gate as well, and preserve all prior reports.

### Phase 5: close generic RTL Linux

Re-run with the same manifest and require, in order:

1. `devtmpfs: initialized`;
2. `Run /init as init process`;
3. the declared GPIO, sleep, mmap, exec, yield, wait-status, and fork/wait
   userspace markers;
4. no simulator fatal, kernel panic, malformed trace, or unbounded run.

A QEMU panic after the test init exits is expected for the current workload and
must be distinguished from failure to start `/init`. The RTL gate must still
return nonzero when `LINUX_REQUIRE_USERSPACE=1` and any marker is absent.

### Phase 6: final differential and regression gates

After Phase 5 passes, run:

```bash
make phase3-complete
make current-contract-signoff
```

Then run the bounded Linux differential with a declared target and both
producers complete. The final report must include record counts, hashes,
first-mismatch result, marker counts, and residual risks. A producer-only trace,
partial timeout, or reused artifact cannot satisfy closure.

## 5. Tracking checklist

- [ ] v19 manifest and storage audit recorded
- [ ] Current RTL root-cause checkpoint reproduced
- [ ] QEMU focus trace captured with explicit sampling semantics
- [ ] First joined architectural mismatch identified
- [ ] Owner-specific reproducer added
- [ ] One owner-scoped fix implemented
- [ ] Frontend, direct-JAL, CPU/CP0, and IRQ gates rerun
- [ ] Generic RTL reaches `/init`
- [ ] All declared RTL userspace markers pass
- [ ] Phase 3 and current-contract gates pass
- [ ] Full bounded Linux differential reaches its declared target
- [ ] Compact evidence report and residual-risk list published

## 6. Explicit non-claims

Passing this plan does not by itself claim complete MIPS32 ISA compliance,
FPU support, complete Linux/MMU demand paging or SMP shootdown semantics,
unrestricted QEMU equivalence, physical DDR/QSPI/PHY correctness, or ASIC
signoff. Those require separate contracts and evidence.
