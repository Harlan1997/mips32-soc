# RTL Linux Differential Fix Plan v11

Plan date: 2026-09-21  
Status: `OPEN / DETERMINISTIC GUEST ENTROPY CONTRACT`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v10.md`

## 1. Objective

Restore validity to the bounded QEMU system-mode versus RTL Linux
differential comparison, then fix the first real RTL divergence exposed by
that comparison.

The current target mismatch is not yet an RTL cache or DDR defect. The first
identified difference is the operand produced by Linux
`get_random_u32()` before the later store at `PC=0x88cecc58`. Repeated QEMU
runs produce different values for the same apparent inputs, and QEMU's
generic `-seed` does not make the guest result deterministic. Until guest
entropy is controlled and recorded, a QEMU/RTL data mismatch is not a valid
CPU/cache differential failure.

This plan preserves the default blocking-cache path and existing default
Linux behavior. Any deterministic entropy mechanism is opt-in and must not
be used to claim generic Linux entropy semantics, full ISA compliance, or
unrestricted QEMU/RTL equivalence.

## 2. Current evidence and boundary

The observed downstream mismatch is:

```text
PC   = 0x8886cebc
inst = 0x8e62ea9c       # lw v0,-5476(s3)
VA   = 0x88c4ea9c
PA   = 0x08c4ea9c
QEMU = 0x0df62201
RTL  = 0x28e6de6b
```

The actual preceding dependency is:

```text
0x88cecc4c: jal get_random_u32
0x88cecc54: lw  a0,0(gp)
0x88cecc58: sw  v0,960(a0)
0x88cecc5c: lw  v0,0(gp)
0x88cecc60: lw  v1,960(v0)
0x88cecc6c: sw  v1,-5476(v0)
```

QEMU and RTL disagree at the first store operand, before the later L1 hit
store and before the target load. The existing memory-owner checker passes its
declared input, so the checker does not establish that the guest values are
comparable.

Repeated QEMU observations include different `get_random_u32()` results even
when the command line is unchanged. Therefore the current status is:

| Boundary | Status | Meaning |
| --- | --- | --- |
| L1 hit-store mutation | `DOWNSTREAM` | It receives the already divergent CPU store data. |
| DDR backing/read response | `NOT OWNER` | No evidence currently makes DDR the first wrong boundary. |
| CPU/RTL functional bug | `UNPROVEN` | Must be re-evaluated after valid deterministic comparison. |
| QEMU/RTL Linux differential | `INVALID INPUTS` | Guest entropy is not controlled and recorded. |

## 3. Definition of done

This plan is complete only when all of the following are true:

1. Every differential run records a complete immutable manifest, including
   the entropy mode, seed/material identifier, DTB/image hashes, and tool
   versions.
2. Repeated QEMU runs with the opt-in deterministic profile produce identical
   entropy-dependent retire and memory records.
3. Repeated RTL runs with the same profile produce identical relevant records.
4. QEMU and RTL consume the same declared kernel, DTB, boot image, workload,
   and entropy contract; a missing or mismatched contract fails the gate.
5. A fresh comparison identifies the first wrong architectural boundary. If
   it is RTL, exactly one owner-scoped fix is applied and tested. If it is
   still an input/model mismatch, the gate reports that boundary and remains
   open.
6. The report states the exact bounded scope and retains residual claims for
   full ISA/FPU, unrestricted MMU demand paging and shootdown, generic Linux
   userspace, real DDR/QSPI devices, and unbounded system-mode equivalence.

## 4. Execution phases

### Phase 0: freeze source and artifact identity

Create a fresh run directory below `/data/disk/tmp/mips32-soc`, for example:

```text
/data/disk/tmp/mips32-soc/plan-v11-entropy-contract-20260921
```

Record:

- commit, branch, dirty-worktree status, and hashes of tracked and untracked
  source files used by the run;
- kernel, initramfs/root image, DTB, Boot ROM, DDR image, QEMU binary,
  plugin source/shared object, RTL file list, and generated simulator hashes;
- QEMU machine/CPU, RTL defines/plusargs, simulator seed, timeout, cycle and
  retire bounds;
- compiler, Python, QEMU, VCS, and host versions;
- entropy mode, seed identifier, and all child exit statuses.

Use fresh artifacts by default. Reuse must require an exact manifest match and
an explicit opt-in. A dirty source mismatch or missing manifest field rejects
the result rather than silently reusing an old simulator or trace.

Acceptance:

```text
git diff --check
bash -n tb/linux_boot/run_rtl_linux_focus_differential_gate.sh
bash -n tb/isa_ref/run_qemu_linux_differential_gate.sh
make linux-memory-owner-trace-checker-test
make rtl-frontend-compile
```

### Phase 1: inventory the guest entropy sources

Trace and classify every entropy input that can affect `get_random_u32()` in
the selected Linux image. At minimum inspect:

- kernel boot-time random seed and `random.c` initialization;
- device-tree `rng-seed` or equivalent properties, if consumed by this kernel;
- hardware RNG, if present in the machine model or RTL address map;
- CP0 count/compare, timer, interrupt, UART, and boot ordering only as
  observable entropy inputs, not as tunable workarounds;
- QEMU machine initialization and any host-time or host-random input;
- initramfs or `/init` writes that seed or consume random state.

The inventory must identify the source, read path, architectural visibility,
and whether it is deterministic under repeated runs. Do not assume a DTB
property works until a trace proves the kernel consumes it.

Acceptance: a source-to-consumer table and a focused trace show which input
first changes the result of `get_random_u32()`. If the source cannot be
observed, the result is `ENTROPY_UNOBSERVED`, not a differential pass.

### Phase 2: implement an opt-in deterministic entropy contract

Select the smallest contract supported by both environments. Preferred order:

1. a documented, shared DTB seed property consumed by the guest kernel;
2. an explicitly modeled SoC RNG register with a deterministic seed stream;
3. a test-only boot handoff that the kernel image demonstrably consumes.

The selected contract must be implemented symmetrically in QEMU and RTL (or
in the shared boot artifact), and must preserve default behavior when the
opt-in switch is absent. It must define:

- seed width and byte order;
- stream generation/repetition behavior;
- reset and reread behavior;
- whether reads consume state and how read ordering is recorded;
- behavior when the seed is missing, malformed, or used with an incompatible
  image/DTB;
- explicit prohibition on using timing knobs to force matching values.

Add a machine-readable entropy manifest and fail-fast validation. The runner
must reject a comparison when the QEMU and RTL seed IDs, DTB hash, kernel hash,
or entropy mode differ.

Required tests:

- same seed, repeated QEMU runs: exact identical entropy-dependent records;
- same seed, repeated RTL runs: exact identical entropy-dependent records;
- different seeds: at least one intentional entropy-dependent difference;
- missing/malformed seed: explicit failure or documented default behavior;
- reset and repeated RNG reads: contract-defined sequence;
- default profile without the opt-in switch: existing behavior unchanged.

No QEMU/RTL differential result may be labeled valid before these tests pass.

### Phase 3: make the differential gate reject invalid inputs

Extend the comparison runner and checker to validate before comparing retire
records. Reject:

- missing entropy metadata;
- unequal seed IDs or entropy modes;
- unequal kernel/DTB/root-image/Boot ROM hashes;
- partial or truncated QEMU or RTL traces;
- unequal record counts where exact comparison is requested;
- duplicate, missing, or non-monotonic retire sequence numbers;
- child processes that exit by timeout, signal, or nonzero status;
- unbounded or undeclared comparison ranges.

Keep the first-mismatch report separate from the input-validity report. An
`INVALID_INPUTS` result must never be converted into a CPU/cache failure by
the comparator.

Add positive and adversarial checker tests for each rejection condition,
including a changed seed, changed DTB, truncated trace, reordered record, and
mutated unselected GPR.

### Phase 4: reclassify the first wrong architectural owner

After Phases 1-3 pass, rerun the same bounded Linux workload and compare the
first store at `PC=0x88cecc58` and the target load. Use the existing opt-in
`LINUX_FORWARD_POST` fields plus the focused CPU trace to capture:

```text
retire sequence, PC, instruction, delay-slot metadata
source register values and forwarding selections
EX/MEM address and store operand
mem_val_rt, aligned data, byte enables
core-to-cache valid/write/address/data
L1 request and array-write event
exceptions, flush/replay, reset, and stall state
```

Classify the first mismatch exactly once:

| First wrong boundary | Action |
| --- | --- |
| QEMU/RTL entropy state still differs | Stop; repair the contract or artifact identity. |
| RTL committed GPR/source state | Fix CPU writeback, retire, or state restore; add dependency coverage. |
| RTL forwarding value | Fix hazard/forwarding valid lifetime; add load-use/store-data tests. |
| EX/MEM or MEM-stage value | Fix stall, flush, replay, or delay-slot ownership. |
| `mem_val_rt` correct but aligned data wrong | Fix store alignment/byte-enable logic; add SB/SH/SW tests. |
| Core request wrong while internal value is correct | Fix core/cache valid-hold and backpressure contract. |
| Cache request correct but array write wrong | Fix L1 merge/index/tag ownership; add exact-line test. |
| No observable owner | Extend observability and mark the run `OWNER_UNOBSERVED`. |

The later target load, backing DDR word, panic, or first visible cache array
mutation is not an owner by itself.

### Phase 5: apply one owner-scoped RTL fix

Only after a valid comparison identifies an RTL boundary, modify that one
module or pipeline contract. The fix requires:

- an exact reproducer for the first wrong instruction;
- a positive directed test;
- a reset-in-flight, backpressure, error, or negative test;
- an assertion/checker tying instruction validity, address, data, byte
  enables, and acceptance to one owner;
- frontend compile and affected CPU/cache/AXI gates;
- a fresh QEMU/RTL comparison using the same entropy manifest.

Do not repair this issue by changing timer/`WAIT`/`lpj`/CP0 timing, interrupt
policy, MMU policy, Linux command line, cache invalidation, cache mode, AXI ID
behavior, or comparison tolerance. Do not hard-code the expected random value.

### Phase 6: bounded closure and residual scope

Run, from the same manifest:

```text
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
make rtl-linux-focus-differential-gate
```

The exact available gate names may be recorded as skipped only with an
explicit reason and nonzero residual-risk entry. A bounded pass must state
the image, entropy profile, CPU/cache/MMU configuration, record bound, and
terminal condition.

Write a completion report under the run directory containing the manifest,
entropy inventory, determinism results, validity-checker results, first-wrong
owner trace, RTL diff/test logs, and residual risks.

Keep these capabilities open unless independently evidenced: full
MIPS32/privileged ISA and FPU, unrestricted demand paging and OS page-table
management/shootdown, generic Linux userspace, real DDR/QSPI PHY/device
timing, formal/CDC/RDC, synthesis/STA/DFT, board validation, and unbounded
QEMU/RTL system equivalence.

## 5. Status ledger

| Item | Status |
| --- | --- |
| Memory owner checker | `PASS`, declared input only |
| CPU store trace | `ADDED`, compiled and used |
| Later L1 hit-store classification | `DOWNSTREAM` |
| First divergence source | `GUEST ENTROPY`, currently nondeterministic |
| Deterministic entropy contract | `NOT STARTED` |
| Differential input-validity gate | `OPEN` |
| Valid post-contract owner classification | `NOT STARTED` |
| Owner-scoped functional RTL fix | `NOT STARTED` |
| Generic RTL `/init` and userspace | `OPEN` |
| Bounded QEMU/RTL closure | `BLOCKED BY ENTROPY CONTRACT` |

