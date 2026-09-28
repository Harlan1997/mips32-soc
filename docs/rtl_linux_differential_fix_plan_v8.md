# RTL Linux Differential Fix Plan v8

Plan date: 2026-09-21  
Status: `OPEN / POST-FIX REVIEW`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v7.md`

## 1. Review conclusion

The current worktree contains a useful diagnostic expansion, but the Linux
failure is not closed. The first strict architectural mismatch remains:

```text
PC   = 0x8886cebc
inst = 0x8e62ea9c       # lw v0,-5476(s3)
VA   = 0x88c4ea9c
PA   = 0x08c4ea9c
line = 0x08c4ea80
QEMU = 0x0df62201
RTL  = 0x28e6de6b
```

The short cold-refill run shows zero data in the target line before the late
failure, so the bad value is not explained by the initial static DDR image.
The late owner trace reaches the target load and shows the wrong value at the
L1 response boundary, but some L2/DDR fields are malformed (`<NIL>` or
zero-filled) and cannot establish where the value first became wrong.

Therefore the current fix is classified as `DIAGNOSTIC INFRASTRUCTURE`, not
as an RTL root-cause fix. Timer, `WAIT`, `lpj`, CP0 Compare, interrupt, and
Linux command-line changes remain out of scope until the memory owner is
proven.

## 2. Current status and claims

| Boundary | Status | Allowed claim |
| --- | --- | --- |
| RTL frontend compile | `PASS` | The current source passes the recorded frontend gate. |
| Focus differential checker tests | `PASS` where recorded | Parser/checker behavior is covered; this is not Linux equivalence. |
| Cold target-line refill | `PASS` diagnostic | The initial refill does not contain the late wrong value. |
| Late memory owner | `OPEN` | L1, L2, DDR, and earlier committed store remain candidates. |
| First architectural mismatch | `REPRODUCED` | The target `lw` returns different data at a committed architectural boundary. |
| Generic RTL `/init` and userspace | `OPEN` | The stack-protector panic occurs before accepted generic userspace evidence. |
| Full system-mode QEMU/RTL differential | `OPEN` | No unrestricted, full-ISA, or generic Linux equivalence claim is allowed. |

The dirty worktree must be identified in every new artifact. A base commit
alone is not sufficient evidence for the current source.

## 3. Review findings

### P0: memory-owner trace is not yet trustworthy

The current display combines too many values into one record. Unknown values,
packed strings, and simulator formatting make `DDR`, `L2`, and target-array
ownership ambiguous. A trace that cannot distinguish `0`, `X`, `Z`, and an
absent transaction must not drive an RTL change.

### P0: the owner boundary is still unclassified

The target value can be introduced by one of these boundaries:

```text
committed store
  -> DDR backing array / response
  -> L2 refill or cached line
  -> L1 refill buffer / install
  -> L1 hit word extraction
  -> architectural load result
```

The next implementation task is observability, not another speculative cache
or timer modification.

### P1: Linux progress is downstream evidence

The generic run's stack-protector panic and later pre-`WAIT` behavior are
effects after the committed load mismatch. They cannot be used to justify a
timer or interrupt fix while the load owner is unresolved.

### P1: existing pass labels need strict boundaries

The bounded retire comparison, cold refill run, and RTL frontend compile are
valid evidence only for their declared configurations. None proves complete
ISA, demand paging, Linux userspace, or unbounded QEMU/RTL equivalence.

## 4. Ordered execution plan

### Phase 0: freeze current source and reproduce

Create a fresh run directory under `/data/disk/tmp/mips32-soc` with:

- git commit, branch, dirty status, and patch hash;
- hashes of kernel, DTB, Boot ROM, DDR image, simulator, QEMU, and plugin;
- RTL defines, plusargs, cycle limit, target line, trace window, and timeout;
- tool versions and child exit statuses;
- exact first divergence record and trace byte counts.

Run the non-mutating checks first:

```text
git diff --check
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
bash -n tb/soc_test/run.sh
make rtl-frontend-compile
make focus-differential-checker-test
make peripheral-differential-checker-test
```

Acceptance: the fresh run reproduces the target PC and both load values, or
the report identifies an input/source mismatch before any RTL edit.

### Phase 1: replace the malformed owner record

Split the large diagnostic display in `tb/soc_test/tb_mips_soc.v` into
independent, short records with decimal cycle and fixed-width hexadecimal
fields. Use separate record types:

```text
LINUX_MEMORY_OWNER_L1
LINUX_MEMORY_OWNER_L2
LINUX_MEMORY_OWNER_DDR
LINUX_MEMORY_OWNER_STORE
```

Each record must print a `valid` bit and only values that are valid for that
channel. Required fields:

- cycle, transaction ordinal, target physical line, and target word index;
- L1 request/response, refill beat, line-buffer word, install word, and hit
  extraction;
- L2 lookup valid/tag/state, downstream address, response beat, and array
  write;
- backing-array read/write address, byte enable, and target word;
- CPU committed store PC, PA, data, byte enable, and cache/bus acceptance.

Do not print a string placeholder for an unavailable signal. Encode unavailable
as `valid=0`; preserve four-state values with `%h` in a dedicated field when
the simulator supports it. Add a parser fixture that rejects malformed,
truncated, or ambiguous owner records.

Acceptance: one late-window run yields a transaction table for line
`0x08c4ea80`, and the first cycle containing `0x28e6de6b` is unambiguous.

### Phase 2: classify the owner before changing functional RTL

Run the late window with:

```text
RTL_CYCLE_LIMIT=22005000
LINUX_TARGET_TRACE_LINE=00462754
LINUX_TARGET_TRACE_CYCLE_START=22000000
LINUX_TARGET_TRACE_CYCLE_END=22005000
LINUX_MEMORY_OWNER_TRACE=1
```

Classify exactly one first-wrong boundary:

| First wrong boundary | Required next action |
| --- | --- |
| DDR backing array or response | Fix address/index/beat mapping and add burst/backpressure coverage. |
| L2 response or array write | Fix L2 refill beat counter, line indexing, or hit selection. |
| L1 buffer/install/extraction | Fix L1 refill ordering, word select, or install path. |
| Earlier committed store | Fix CPU store retirement, byte lane, or write-through handoff. |
| All memory data equal | Investigate MMU/tag/byte extraction and extend the join window. |

No owner classification may be based only on the final L1 `rdata` or on a
later kernel panic.

### Phase 3: apply one owner-scoped fix

Modify only the module and state-machine boundary identified in Phase 2. The
change must include:

- a directed positive test for the failing line/beat/word;
- a reset, backpressure, error, or negative test for the same path;
- a target-line trace proving the original value and its provenance;
- frontend compile and the affected cache/store gate;
- a fresh focused QEMU/RTL comparison using the same frozen inputs.

Do not fix this failure by invalidating the line, disabling L2 or MMU,
changing the Linux image, widening comparator tolerance, or modifying timer
behavior.

Acceptance: the original load returns `0x0df62201`, or a new first mismatch is
created and independently classified with complete evidence.

### Phase 4: restore Linux progress gates

After Phase 3, run from current source:

```text
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

Then run the declared generic userspace gate. It must reject kernel panic,
oops, missing or reordered markers, AXI/APB errors, incomplete trace records,
simulator failures, and nonzero child status.

Acceptance: fresh generic `/init` and userspace markers pass with a manifest;
otherwise retain the exact next blocker and do not relabel the gate.

### Phase 5: bounded differential closure

Only after Linux progress passes, run separately:

1. QEMU versus default blocking RTL.
2. QEMU versus opt-in nonblocking-L1 RTL.
3. Blocking RTL versus nonblocking-L1 RTL.

Compare complete retire records, PC/instruction, selected architectural GPRs,
CP0 exception metadata, and committed memory effects. Reject unequal record
counts, duplicate sequence numbers, partial records, hidden child failures,
unpaired stores/loads, and unexpected termination.

Acceptance: `BOUNDED_PASS` names the exact image, CPU model, cache mode, record
bound, and terminal condition. It does not become a full ISA or unrestricted
Linux claim.

### Phase 6: evidence and status update

Write one report under the fresh run directory containing the manifest,
owner transaction table, first-wrong boundary, RTL diff, directed tests,
Linux results, differential results, and residual risks. Update this plan only
after the report is complete. Keep open all unsupported scope: full ISA/FPU,
unrestricted MMU demand paging and shootdown, real PHY/device timing,
formal/CDC/RDC, synthesis/STA/DFT, board validation, and unbounded
QEMU/RTL equivalence.

## 5. Definition of done

This plan is closed only when all are fresh and current-source based:

1. The target-line owner trace is parseable and identifies the first wrong
   boundary.
2. One owner-scoped RTL fix has positive and negative/reset evidence.
3. The original target load matches QEMU.
4. Generic RTL `/init` and the declared userspace gate pass.
5. The bounded three-way differential passes with complete records.
6. A residual-risk report preserves all remaining non-claims.

