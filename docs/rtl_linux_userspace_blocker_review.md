# RTL Linux Userspace Blocker Review

Review date: 2026-09-20

Status: `HISTORICAL DIAGNOSTIC / NOT SIGNOFF`

## Superseding closure update

The current-source generic RTL Linux terminal gate is now closed for its
declared userspace workload. See
`docs/rtl_linux_generic_userspace_closure_20260929.md` and the evidence
registry for the fresh seeded run, marker order, image hashes, and clean
terminal-stop exit. This supersedes the generic-userspace boundary statements
below; the older root-cause analysis remains historical, and full
RTL/QEMU architectural differential and unrestricted Linux remain open.

## Executive conclusion

The generic RTL Linux system-mode boot failure around `number()` is
reproducible and has a plausible delay-slot interrupt diagnosis. The retained
evidence is not signoff: the old focus runner allowed stale artifacts, masked
QEMU failures, accepted incomplete traces, and compared only selected
checkpoint state. Current-source remediation is tracked in
`docs/rtl_linux_differential_remediation_plan.md`.

The root cause was an asynchronous timer interrupt firing when a control-transfer
instruction (`0x88a378d8: jr ra` in `put_dec_trunc8`) was in the Writeback (WB)
stage while its architectural branch delay slot (`0x88a378dc: sh v1, 0(a0)`)
was in the Execute (EX) stage separated by an invalid MEM pipeline bubble.
Because the CPU interrupt decoder previously only inspected the adjacent MEM
stage (`mem_pc == wb_pc + 4`), it missed the delay slot in EX. Furthermore,
`interrupt_wb_sequential_epc` erroneously fired (lacking `!wb_is_control_transfer`),
manufacturing an erroneous resumption at `EPC = 0x88a378dc` with `Cause.BD = 0`.
Upon `eret`, the CPU resumed sequentially without a jump target, falling
through into `put_dec_helper4` (`0x88a378e0`) and clobbering `v0` to 0.
This caused the subsequent `subu v1, v0, t9` at `0x88a38c1c` to compute a negative
buffer length (`0x76bda52c`), leading to `addu` producing address `0xffffffff`
and crashing in the following `lbu` loop.

Additionally, `d_fault_vaddr_pending_q` was previously cleared on any generic
`exception_flush`, allowing intermediate pipeline flushes/interrupts to discard
a pending data fault virtual address before CP0 could commit it, corrupting
`BadVAddr` to `0xffffffff`.

Candidate repairs were added in `rtl/cpu/mips_cpu.v`:
1. Delay-slot detection was expanded to inspect EX and ID stages across bubbles
   (`interrupt_wb_branch_delay_from_ex/id`).
2. Control-transfer instructions in WB were barred from triggering sequential EPC.
3. Fault address persistence was qualified so that only committed data exceptions,
   `ERET`, or context restores clear pending fault metadata.

The retained focus-gate result is bounded historical evidence only. It does
not prove full trace completeness, current-source freshness, BadVAddr owner
identity, generic Linux userspace progress, or UART/VIC equivalence. The core
regressions listed above must be rerun from current source after the directed
coverage and ownership gates are implemented.

## Current status by boundary

| Boundary | Status | Evidence-based assessment |
| --- | --- | --- |
| QEMU `mips32-soc-ref` system boot | Bounded historical evidence | QEMU has a retained boot log, but plugin lifecycle and exit status require fresh validation. |
| RTL `rtl-minimal` opt-in userspace contract | Bounded pass | The reduced image has a separate declared marker contract; this is not generic Linux signoff. |
| Generic RTL Linux declared userspace workload | Closed | Current-source RTL reaches `/init` and all required process, VM, GPIO, timer, exec, wait, fork, and terminal markers in order with a clean terminal stop. |
| RTL/QEMU first architectural divergence | Block reduced | A delay-slot diagnosis exists, but strict current-source retire evidence is still required. |
| Exception `BadVAddr` across fault/replay | Open | Absence of literal `0xffffffff` is not ownership or replay proof. |
| Full RTL/QEMU system differential | Open | The old gate compared two checkpoints and cannot claim a full differential. |
| UART/VIC model equivalence | Open | No transaction-level UART/VIC differential gate is represented here. |

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
