# RTL Linux Differential Fix Plan v7

Plan date: 2026-09-21  
Status: `OPEN / MEMORY-PATH ROOT CAUSE`  
Owner: RTL D-cache/L2/DDR path, CPU retirement trace, Linux verification

## 1. Purpose

This document supersedes v6 as the execution authority for the next fix
cycle. The current blocker is no longer an unclassified timer or `WAIT`
problem. A fresh focused QEMU-versus-RTL comparison has identified a committed
load-value divergence before the generic Linux stack-protector panic.

The target instruction is:

```text
PC       = 0x8886cebc
instruction = 0x8e62ea9c       # lw v0,-5476(s3)
VA       = 0x88c4ea9c
PA       = 0x08c4ea9c
line     = 0x00462754           # physical line base 0x08c4ea80
QEMU     = 0x0df62201
RTL      = 0x28e6de6b
```

This is the first proven architectural mismatch in the current bounded
window. The generic RTL run later reports a stack-protector panic and remains
in a pre-`WAIT` delay loop, but that later symptom is not the current owner.
Do not modify timer, `WAIT`, `lpj`, CP0 Compare, interrupt, or Linux command
line behavior until the memory mismatch is classified.

## 2. Current claims and non-claims

| Boundary | Status | Permitted claim |
| --- | --- | --- |
| RTL frontend compile | `PASS` | Current source has passed the reported 8/8 frontend set |
| QEMU custom machine UART boot | `BOUNDED PASS` | QEMU system mode reaches its declared UART boot boundary |
| Bounded early retire differential | `PASS` | The named prefix through the explicit handoff is equal |
| Generic RTL Linux `/init` | `OPEN` | A 65M-cycle run still fails before valid `/init` evidence |
| First architectural mismatch | `CLASSIFIED` | A committed `lw` result differs at the target PC |
| Memory owner | `OPEN` | L1, L2, DDR, or earlier committed store is not yet distinguished |
| Full QEMU/RTL differential | `OPEN` | No unrestricted or generic Linux equivalence claim is allowed |

The bounded differential pass must not be described as full ISA, full MMU,
generic Linux userspace, or product signoff.

## 3. Evidence baseline

The relevant fresh artifacts are under:

```text
/data/disk/tmp/mips32-soc/plan-v6-20260921/linux-retire-diff-complete
/data/disk/tmp/mips32-soc/plan-v6-20260921/generic-init-65m
/data/disk/tmp/mips32-soc/plan-v6-20260921/stack-focus-exact
/data/disk/tmp/mips32-soc/plan-v6-20260921/memory-owner-late-20260921
```

The bounded differential produced complete traces (`200000` RTL records and
`200000` QEMU events) and `TRACE_COMPARE_PASS`. The generic init run produced
`Kernel panic - not syncing: stack-protector` and no accepted `WAIT` or timer
interrupt evidence. The target RTL trace shows the value returned as an L1
hit after a refill/miss sequence; the initial DDR image does not contain
`0x28e6de6b` at the target word.

The default cache contract relevant to this investigation is:

- L1 D-cache line: 32 bytes, 8 words.
- L2 default: `l2_cache_wt`, direct-mapped, 32-byte lines.
- DDR base: `0x08000000`.
- DDR word index: `(address - SOC_DDR_BASE) >> 2`.
- Expected refill line base: `0x08c4ea80`.
- Expected target beat: `0x08c4ea9c`, the seventh word in that line.

## 4. Execution rules

All large output stays under `/data/disk/tmp/mips32-soc`. Every run receives a
new directory and a manifest containing source identity, image hashes, RTL
defines, plusargs, QEMU command, tool versions, limits, child exit codes, and
terminal reason. A timeout, simulator crash, truncated trace, nonzero child
status, or partial final record is a failure.

Preserve the default blocking cache path. Any nonblocking-L1 experiment is
opt-in and must be reported separately. Do not accept a fix that only moves
the panic, changes the Linux image, masks the target line, or changes the
comparison policy.

Before EDA execution:

```bash
source /etc/profile.d/modules.sh
module load vcs
```

## 5. Ordered implementation plan

### Phase 0: freeze and reproduce the owner window

Run the existing prerequisite gates from current source:

```text
git diff --check
bash -n tb/isa_ref/run_qemu_linux_differential_gate.sh
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
make linux-timer-clock-comparison-test
make focus-differential-checker-test
make peripheral-differential-checker-test
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
```

Reproduce the target window with the same frozen image and explicit trace
options. The run must retain the exact first divergence record, not only a
summary line. If reproduction changes, stop and explain the input or source
identity difference before editing RTL.

**Exit:** a fresh manifest reproduces the `lw` mismatch at `0x8886cebc`, or
the report proves why the prior artifact was not comparable.

### Phase 1: capture the complete refill transaction

Enable the existing cache-owner and D-side traces around cycle `22,000,000`
with target line `0x00462754`. For the first request to the line, capture:

1. CPU effective VA, translated PA, read/write, byte enable, and owner PC.
2. L1 lookup tag/index/word, hit/miss result, replacement way, and request
   buffer contents.
3. L1 `AR` address/length and every returned `R` beat with `RID`, `RRESP`,
   `RLAST`, and acceptance cycle.
4. L1 line buffer before and after each beat, plus the exact install word.
5. L2 lookup tag/index, downstream `AR`, every downstream beat, and its cache
   array writes.
6. DDR selected word index, returned data, and response timing.

Use the target-line trace controls rather than an unbounded full Linux log:

```text
LINUX_CACHE_OWNER_TRACE=1
LINUX_TARGET_DSIDE_TRACE=1
LINUX_TARGET_TRACE_LINE=00462754
LINUX_TARGET_TRACE_CYCLE_START=22000000
```

The trace must distinguish a refill response from an L1 hit response. It must
also show whether the target word is already wrong when it leaves DDR/L2 or
becomes wrong during L1 buffering/install/word selection.

**Exit:** a transaction table exists for line base `0x08c4ea80`, including the
expected seventh beat and the first cycle where `0x28e6de6b` appears.

### Phase 2: compare memory effects before the target load

If the refill data is correct, compare all committed stores to the target
physical line from the last known-good checkpoint through the target load.
The comparison must include QEMU and RTL store PC, PA, data, byte enable,
sequence, and exception/squash status. A speculative pipeline store or an
uncached bus request that never commits must not be treated as an architectural
store.

Classify the evidence:

| Evidence | Owner | Next action |
| --- | --- | --- |
| DDR returns wrong seventh beat | DDR address/index or image mapping | Fix address/beat mapping and add burst test |
| DDR correct, L2 stores wrong data | L2 refill beat counter/array write | Fix L2 miss/refill and add line-fill test |
| L2 correct, L1 installs wrong data | L1 line buffer/word select/install | Fix L1 refill/install and add unaligned-offset test |
| Refill correct, prior committed store differs | CPU store, byte lane, write-through path | Fix store retirement/AXI write path |
| All memory effects equal, load differs | MMU/cache lookup or load extraction | Fix translation/tag/byte-lane path |
| No architectural store or refill explains value | Trace incompleteness or earlier divergence | Extend the join window; do not guess |

**Exit:** one owner is supported by transaction-level evidence and the first
wrong value has a module and state-machine boundary.

### Phase 3: apply one owner-scoped RTL fix

Change only the identified owner. The fix must preserve the default blocking
configuration and include:

- a minimal positive test for the failing beat/word/transaction;
- a negative or reset/backpressure/error case;
- a focused target-line trace showing the corrected value;
- `make rtl-frontend-compile` and the affected directed gate; and
- a fresh focused QEMU/RTL comparison with the same manifest inputs.

Likely fix boundaries include:

- `rtl/cache/dcache.v`: refill beat ordering, line-buffer indexing, install,
  replacement, or returned-word selection;
- `rtl/cache/l2_cache_wt.v`: downstream burst address/beat counter, refill
  array write, or hit data selection;
- `rtl/perips/axi_ddr4_controller.v`: DDR-base subtraction, word index,
  burst address, or response beat handling;
- CPU store/retirement logic: committed write enable, byte enables, physical
  address, or write-through handoff.

Do not fix the symptom by invalidating the line, disabling L2, disabling the
MMU, changing the image, or widening the comparator tolerance.

**Exit:** the original target load returns `0x0df62201` in RTL, or the new
first mismatch is independently classified with fresh evidence.

### Phase 4: re-run Linux gates

After the memory owner gate passes, run:

```text
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

Then run the generic userspace gate with the existing declared timeout and
image. The gate must reject kernel panic/oops, missing or reordered markers,
APB/AXI errors, incomplete trace records, simulator failures, and nonzero
child exit status.

**Exit:** fresh `RTL_GENERIC_INIT_PASS` and the declared RTL userspace marker
set, with no claim beyond that exact image and configuration.

### Phase 5: close the bounded three-way differential

Run separate comparisons for:

```text
QEMU vs default blocking RTL
QEMU vs opt-in nonblocking-L1 RTL
default blocking RTL vs opt-in nonblocking-L1 RTL
```

Compare architectural retire sequence, PC/instruction, selected GPRs, CP0
changes, exception metadata, and committed memory effects. Reject unequal
complete-record counts, duplicate sequence numbers, partial records, hidden
child failures, unpaired stores/loads, and unexpected termination.

**Exit:** `BOUNDED_PASS` for the explicitly named image, prefix, CPU model,
cache configuration, and terminal boundary.

### Phase 6: update closure evidence

Write a run report containing the manifest, first mismatch before/after,
transaction table, owner decision, diff, directed tests, Linux init/userspace
results, three-way comparison, and residual risks. Update this document's
status only after all required evidence is fresh. Keep unsupported claims
explicitly listed.

## 6. Definition of done

This plan is complete only when all of the following exist under a fresh run
directory:

1. Current-source prerequisites and a reproducible target-line manifest.
2. A complete L1/L2/DDR or committed-store transaction trace.
3. A single owner-scoped fix with positive and negative evidence.
4. The target load matches and the generic RTL init gate passes.
5. The declared userspace gate and bounded three-way differential pass.
6. A residual-risk report that does not claim full ISA/FPU, unrestricted MMU
   demand paging, Linux/SMP shootdown, physical PHY timing, formal/CDC/RDC,
   synthesis/STA/DFT, board validation, or unbounded QEMU/RTL equivalence.

Until these conditions pass, the status remains `OPEN`.
