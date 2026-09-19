# RTL Linux Userspace Blocker Review

Review date: 2026-09-20

Status: `BLOCK_VERIFIED / ROOT_CAUSE_OPEN`

## Executive conclusion

The largest unresolved capability gap is the generic RTL Linux system-mode
differential boundary. The current evidence proves a reproducible failure
around Linux `number()`, but it does not yet identify the first incorrect
architectural state. The next fix must therefore close the state-observation
boundary before changing RTL behavior.

The current evidence is precise enough to rule out the original simple
hypotheses:

- The RTL `addu` at `0x88a3897c` computes the correct 32-bit result for the
  operands it receives:
  `0x89425ad4 + 0x76bda52b = 0xffffffff`.
- The existing QEMU focus plugin records only `r30`, so it cannot establish
  whether QEMU has the same `a0`, `t9`, `t5`, and `v0` values at the relevant
  instructions.
- The first observed `BadVAddr` and the replayed `BadVAddr` differ, which is a
  separate precise-exception/replay contract issue even if the register-state
  divergence is fixed.

The project must not claim generic RTL Linux userspace, unrestricted
RTL/QEMU differential, or full ISA/MMU/OS closure until both issues have
direct evidence and passing regressions.

## Current status by boundary

| Boundary | Status | Evidence-based assessment |
| --- | --- | --- |
| QEMU `mips32-soc-ref` system boot | Bounded pass | QEMU reaches serial binding, `/init`, and userspace markers. |
| RTL `rtl-minimal` opt-in userspace contract | Bounded pass | The reduced image reaches the existing boot, GPIO, VM, and sleep/yield markers. |
| Generic RTL Linux boot | Open | The generic image reaches a reproducible fault in `gpiolib_sysfs_init`. |
| RTL/QEMU first architectural divergence | Open, highest priority | QEMU has no focused capture for the registers that determine the failing address. |
| Exception `BadVAddr` across fault/replay | Open, independent | The recorded address changes from the initial fault to replay. |
| Full RTL/QEMU system differential | Open | Existing bounded/selected gates do not cover this generic Linux boundary. |
| UART/VIC model equivalence | Conditional | Still worth testing if the architectural trace reaches the serial probe; it is not the current proven owner. |

## Reproduced failure

The retained RTL run is:

```text
/data/disk/tmp/mips32-soc/rtl-linux-number-operands-20260919/
sim_rc = 0
```

The relevant sequence is:

```text
PC 0x88a3897c: addu a1,t9,a0
RTL t9 = 0x89425ad4
RTL a0 = 0x76bda52b
RTL exout = 0xffffffff
```

The arithmetic is correct. The later load is:

```text
PC          = 0x88a38998
instruction = 0x90a20000       # lbu v0,0(a1)
```

The retained trace shows the following architectural and pipeline boundary:

```text
cycle 23503117: pc=0x88a38c24, addiu a0,v1,-1, data=0x76bda52b
cycle 23503231: EX pc=0x88a3897c, exout=0xffffffff
cycle 23503234: GPR write pc=0x88a3897c, rd=5, data=0xffffffff
cycle 23503236: ID pc=0x88a38998, idrs=0xffffffff
```

This establishes that the `lbu` consumes the value produced by the preceding
`addu`; it does not establish whether `a0`, `t9`, or an earlier control-flow
and replay event is wrong.

The same run also records the exception-address problem:

```text
first observed BadVA = 0xc0002020
replay BadVA         = 0xffffffff
```

The first value must be treated as the faulting instruction's candidate
address. The second value must not be accepted as a legitimate replacement
without proving that the instruction and address both changed architecturally.

## What is and is not proven

### Proven

- The generic RTL run is deterministic enough to reproduce the failure at the
  `number()` instruction window.
- The relevant RTL instruction bytes and PCs are known.
- The RTL ALU result for the observed `addu` operands is correct.
- QEMU executes the same `number()` PC sequence, including
  `0x88a3897c` and `0x88a38998`, in the retained focus run.
- QEMU completes `gpiolib_sysfs_init`, binds `ttyS0`, runs `/init`, and emits
  the userspace markers for its retained generic Linux image.

### Not proven

- Whether QEMU's `a0` or `t9` differs from RTL at `0x88a3897c`.
- Whether `a0=0x76bda52b` was produced incorrectly, was restored incorrectly,
  or is a legitimate value for this exact call path.
- Whether delay-slot handling, exception flush, replay, or nonblocking
  retirement reordered or duplicated an architectural write.
- Whether the input image, DTB, memory contents, and CPU configuration are
  byte-for-byte identical for the two runs at the failing boundary.
- Whether the UART/VIC probe is the owner of the generic boot failure.
- Whether the `BadVAddr` change is caused by the latch, exception priority,
  retry address generation, or a different later fault.

## Root-cause ranking

### P0: missing first-divergence proof

The current QEMU plugin only records `r30`. The RTL trace contains selected
pipeline and GPR records, but there is no common retired-instruction record
that compares the required architectural registers at the same PC. This is
the primary blocker because every candidate RTL fix remains speculative until
the first mismatch is classified.

Candidate owners, in order of evidence to gather, are:

1. A producer/writeback difference for `a0` near `0x88a38c1c` and
   `0x88a38c24`.
2. An incorrect `t9` or stack-derived value entering `number()`.
3. Delay-slot, exception-flush, or replay ordering that changes the state
   between the caller and `0x88a3897c`.
4. A memory/translation mismatch after the operands are proven equal.

The trace must not label any one of these as the root cause yet.

### P1: `BadVAddr` is not stable across fault/replay

The first address fault and the replay address are different. This can corrupt
the kernel's page-fault or TLB-refill decision independently of the register
divergence. The fix requires a directed fault/replay test and an assertion
around the owner of the faulting virtual address, not a log-only workaround.

### P2: generic Linux and full system differential are separate gates

The passing `rtl-minimal` userspace contract and selected QEMU aggregate are
useful bounded evidence, but they do not cover the generic kernel's
`gpiolib_sysfs_init` path or unrestricted post-userspace state. They must
remain separately named and separately accepted.

### P3: UART/VIC is a conditional follow-up

QEMU's UART model is intentionally permissive, and the generic QEMU run
reaches the full 8250 probe. A transaction-level UART/VIC comparison is
required if the state trace reaches that probe, but the current RTL failure
occurs earlier in a CPU architectural-state comparison window. Treating UART
as the primary blocker now would mix a plausible lead with an unproven cause.

## Remediation plan: close the biggest gap first

### Phase 0: freeze a single reproducible comparison [required first]

Create a run directory under `/data/disk/tmp/mips32-soc` containing:

- the exact `vmlinux`, DTB, Boot ROM image, DDR image, config, and command
  line;
- SHA-256 records before and after both runs;
- the RTL source commit/worktree identifier and all feature defines;
- the QEMU binary, machine name, and plugin binary hash;
- the current RTL log and the current QEMU log.

Use the same image and architectural configuration for QEMU and RTL. Keep the
existing generic image and the existing failing bound; do not shorten the
workload or alter the default blocking path to make the comparison pass.

Acceptance: a clean rerun reproduces the same PC window and the same initial
fault classification, or the report explains an input mismatch before any
RTL change is considered.

### Phase 1: add the missing QEMU architectural-state capture

Extend `tb/isa_ref/qemu_gpr_focus_plugin.c` from its current `r30`-only
diagnostic to a focused record for:

```text
PCs: 0x88a38c1c, 0x88a38c24,
     0x88a38978, 0x88a3897c, 0x88a38980, 0x88a38984,
     0x88a3898c, 0x88a38998
GPRs: a0 (r4), a1 (r5), t5 (r13), t9 (r25), v0 (r2), v1 (r3), sp (r29), ra (r31)
```

Each record must include a sequence number, PC, instruction word, the selected
GPR values, and enough before/after context to distinguish an instruction
execution from a repeated TB callback. The plugin must explicitly document
whether a value is sampled before execution, after execution, or at the next
instruction boundary; do not infer retirement ordering from a TB callback.

Add a small parser/test that rejects missing target PCs, duplicate sequence
numbers, and ambiguous before/after labels.

Acceptance: QEMU produces a stable focused trace for all listed architectural
checkpoints and the trace proves the values of `a0` and `t9` at
`0x88a3897c`.

### Phase 2: emit a matching RTL retirement record

Add a diagnostic-only RTL record at the architectural retirement boundary,
not merely at ID, EX, or a writeback pipeline register. For each target PC,
emit:

- retire sequence, PC, instruction, and delay-slot/exception metadata;
- `a0`, `a1`, `t5`, `t9`, `v0`, `v1`, `sp`, and `ra`;
- the committed GPR write, if any;
- exception request, EPC, Cause.BD, and the fault virtual address when
  applicable;
- image/configuration identity and RTL cycle.

Prefer an existing retire-trace interface if it can provide these fields. If
it cannot, add a bounded Linux diagnostic trace in the testbench and keep it
disabled by default. Do not use a cycle-number comparison against QEMU;
compare the retired instruction/state sequence and explicitly account for
delay slots and exceptions.

Acceptance: the two traces can be joined by target PC plus occurrence index,
and the report identifies the first mismatch as one of `PC/inst`, selected
GPR, exception metadata, or memory/translation result.

### Phase 3: classify and fix the first mismatch

Apply exactly one branch of this decision tree:

| First mismatch | Next implementation boundary | Required proof |
| --- | --- | --- |
| PC/instruction stream | fetch, branch delay slot, flush, or replay | A focused branch/exception regression plus the same Linux window passing |
| `a0` at `0x88a38c24` or entry to `number()` | producer writeback/forwarding or replay | Producer retire trace and a minimal dependent-register test |
| `t9`/stack values | call/return, stack memory, or prior store/load | Memory transaction trace and a minimal call/return test |
| Equal operands but different `a1` | ALU/retirement path | Directed `addu` test and Linux checkpoint |
| Equal `a1` but different load/fault | MMU, memory image, byte lane, or cache | Translation/memory transaction comparison and fault test |
| Exception metadata first differs | precise exception/interrupt priority | CP0 exception-entry regression with EPC/BD/BadVAddr assertions |

Do not change UART, CP0 timer, cache, or MMU defaults based only on the
current `addu` result. The arithmetic evidence rules out that specific ALU
claim but does not select a replacement root cause.

### Phase 4: independently close `BadVAddr` fault/replay semantics

Instrument the first translation/data-fault event and the CP0 consumption edge
with a fault token. The token must carry the faulting virtual address through
any MEM wait, replay, exception flush, and refill boundary. Add assertions for:

- a faulting data request latches its own virtual address;
- a younger request cannot overwrite the pending address;
- exception entry consumes the address belonging to the faulting instruction;
- replay either uses the same instruction/address or is explicitly a new
  architectural access;
- `BadVAddr` is not replaced by a bubble or an untranslated retry address.

Acceptance: the focused Linux fault reports the same address on first fault
and replay when it is the same instruction, and the existing CPU/CP0/MMU
regressions remain green. A different address is acceptable only when the
trace proves a different architectural instruction caused it.

### Phase 5: promote the result into the generic differential gate

After Phases 1-4 pass, add a strict gate that runs the same generic image on:

- the default blocking RTL path;
- the opt-in nonblocking-L1 path;
- QEMU `mips32-soc-ref`.

The gate must compare the repaired checkpoint through `gpiolib_sysfs_init`,
the 8250/`ttyS0` boundary, `/init`, and the existing userspace markers. It
must fail on an Oops, panic, unexpected exception, APB error, unresolved
transaction, or missing checkpoint. Retain bounded chunking and hashes to keep
disk and memory use controlled, but do not call a bounded checkpoint pass
"unrestricted Linux".

Acceptance for this blocker:

- first-divergence report is empty through the selected generic Linux window;
- initial and replay fault metadata is coherent;
- default blocking RTL reaches `ttyS0`, `/init`, and required markers;
- opt-in nonblocking L1 reaches the same checkpoints with the same image;
- the report names the exact bounded scope and residual risks.

## Verification commands and artifacts

Before implementation changes:

```bash
git diff --check
bash -n tb/isa_ref/run_qemu_linux_differential_gate.sh
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
```

For RTL changes, initialize the EDA environment before VCS work:

```bash
source /etc/profile.d/modules.sh
module load vcs
```

Store large simulator output under `/data/disk/tmp/mips32-soc`. At minimum,
retain the focused QEMU trace, focused RTL trace, normalized comparison,
first-divergence report, fault/replay report, image hashes, compile log, and
simulation log.

## Explicit non-claims

This review does not claim completion of:

- generic RTL Linux userspace;
- unrestricted RTL/QEMU system-mode differential;
- full MIPS32 ISA or privileged ISA compliance;
- unrestricted demand paging, ASID/shootdown, or OS memory-management
  semantics;
- full FPU/Linux boot semantics;
- formal, CDC, RDC, lint, physical DDR/QSPI timing, or product signoff.
