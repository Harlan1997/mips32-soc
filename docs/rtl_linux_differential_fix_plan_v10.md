# RTL Linux Differential Fix Plan v10

Plan date: 2026-09-21  
Status: `OPEN / CPU STORE-OPERAND OWNER CLASSIFICATION`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v9.md`

## 1. Objective

Close the current bounded RTL Linux divergence by fixing the first incorrect
CPU-visible owner. The immediate problem is no longer classified as a DDR
read corruption: the target value is introduced by a CPU-generated store
operand before the later load observes it.

The plan must preserve the default blocking-cache path and must not alter
timer, `WAIT`, `lpj`, CP0 Compare, interrupt, MMU policy, Linux command-line
behavior, or differential-comparison tolerance as a workaround.

This is an execution plan, not a closure claim. Full ISA, unrestricted Linux,
full demand paging/shootdown, and unrestricted QEMU/RTL equivalence remain
separate scopes.

## 2. Proven evidence

The stable seed-1 divergence is:

```text
PC   = 0x8886cebc
inst = 0x8e62ea9c       # lw v0,-5476(s3)
VA   = 0x88c4ea9c
PA   = 0x08c4ea9c
line = 0x08c4ea80
QEMU = 0x0df62201
RTL  = 0x28e6de6b
```

The owner checker passes its declared input:

```text
LINUX_MEMORY_OWNER_TRACE_PASS records=196 cycles=49
```

The first currently proven target-line mutation is:

```text
cycle 8567954:
DCACHE_ARRAY_TRACE kind=4 way=2 index=20 line=0462754
word=7 oldword=00000000 newword=28e6de6b
oldtag=041189d newtag=061189d
```

`kind=4` is the blocking L1 D-cache `COMPARE` hit-store update. The preceding
CPU request is:

```text
cycle 8567953:
CPU store PA=08c4ea9c data=28e6de6b be=f
PC=88cfb9c0 mempc=88cecc6c we=1 wdata=28e6de6b
```

The store data is already `0x28e6de6b` at the CPU-to-cache boundary. Therefore
the L1 array write is not yet the root cause. The next owner to classify is
the CPU pipeline state that produces the store operand, followed by the
core-to-cache interface only if the internal CPU value is correct.

The target DDR backing word also contains `0x28e6de6b`, but the late DDR
responses observed in the prior run are instruction traffic. This does not
prove DDR corruption or make DDR the owner of this occurrence.

## 3. Definition of done

This plan is complete only when all of the following are fresh and tied to
one immutable source/image manifest:

1. A narrow trace identifies the first wrong value among CPU source state,
   forwarding, MEM-stage store data, core-to-cache request, and L1 array write.
2. Exactly one owner-scoped RTL fix is applied, with a positive directed test,
   a reset/backpressure/error or negative test, and an ownership assertion or
   checker.
3. The original target load matches QEMU, or the newly exposed first mismatch
   has its own complete owner classification and a new plan entry.
4. Frontend compile, focused CPU/cache gates, Linux root-cause checkpoint, and
   generic `/init` evidence are rerun after the fix.
5. Any bounded QEMU/RTL differential result states its exact image, CPU/cache
   configuration, record bound, and terminal condition.
6. The report explicitly retains residual scope; no bounded result is called
   full ISA, generic Linux, unrestricted MMU, or unrestricted system-mode
   equivalence.

## 4. Execution phases

### Phase 0: freeze and reproduce

Create a fresh directory below `/data/disk/tmp/mips32-soc`, for example:

```text
/data/disk/tmp/mips32-soc/plan-v10-cpu-store-owner-20260921
```

Record commit, branch, dirty diff hash, kernel/image/DTB/Boot ROM/DDR hashes,
QEMU and plugin hashes, VCS version, compile defines, plusargs, simulator
seed, cycle bound, target PC/PA/line, and all child exit statuses.

Run the non-destructive preflight:

```text
git diff --check
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
bash -n tb/linux_boot/run_rtl_linux_root_cause_checkpoint_gate.sh
bash -n tb/linux_boot/run_rtl_linux_generic_init_gate.sh
make linux-memory-owner-trace-checker-test
make rtl-frontend-compile
```

Acceptance: seed 1 reproduces the target instruction and both values, or the
manifest records the exact reason the source or artifact set differs.

### Phase 1: add a narrow CPU store trace

Instrument only the opt-in diagnostic path and filter by the target PA/line
and cycle window `8567940..8567960`. Do not add an always-on Linux trace.

Capture, for every valid memory-stage store in the window:

```text
cycle, PC, instruction, delay-slot metadata
decoded rs/rt, register-file read values
forwarding select/source/value for rs and rt
EX address and MEM address
mem_val_rt, aligned store data, byte enable
core-to-cache valid/write/address/data/byte-enable
WB/retire register writes and sequence number
stall, flush, exception, replay, and reset state
```

The trace must distinguish `valid=0` from zero data and must include a
transaction/retire sequence number where one exists. Keep the output
machine-parseable and bounded.

The first comparison is the store at `PC=0x88cfb9c0`, with delay-slot context
`mempc=0x88cecc6c`, address `0x08c4ea9c`, and data `0x28e6de6b`. Compare its
source register and forwarding state with the matching QEMU retire record.

Acceptance: the trace shows whether the wrong value first appears in a
register-file read, forwarding mux, EX/MEM pipeline register, MEM-stage
alignment, or CPU-to-cache request.

### Phase 2: classify the owner before editing RTL

Use exactly one classification:

| First wrong boundary | Required fix scope |
| --- | --- |
| Register-file read or committed source register | CPU register writeback/retire ordering or state restore; add a dependency test. |
| Forwarding mux/source value | CPU hazard/forwarding selection or valid lifetime; add load-use/store-data tests. |
| EX/MEM or MEM-stage pipeline value | Pipeline hold, flush, replay, or delay-slot metadata; add stall and flush tests. |
| `mem_val_rt` correct but aligned store data wrong | `mips_mem_stage` store alignment/byte-enable contract; add SB/SH/SW tests. |
| CPU internal value correct but cache request wrong | CPU-to-cache interface timing/hold/valid contract; add backpressure and reset-in-flight tests. |
| Cache request correct but array write wrong | Blocking L1 hit-store merge/index/tag path; add the exact line/word test. |
| No first wrong boundary is observable | Extend trace coverage; classify as an observability blocker, not a functional owner. |

Do not modify `rtl/cache/dcache.v` merely because its `COMPARE` trace is the
first visible mutation. Do not treat the later Linux load, DDR contents, or a
panic as an owner boundary.

### Phase 3: apply one owner-scoped fix

Modify only the module/state-machine boundary selected in Phase 2. The change
must include:

- a directed positive test reproducing the exact address/data dependency;
- a reset-in-flight, backpressure, error, or negative test for that path;
- an assertion/checker that store address, data, byte enables, and validity
  remain owned by the same instruction until acceptance;
- frontend compile and the affected CPU/cache/AXI gate;
- a fresh focused QEMU/RTL comparison using frozen inputs.

Forbidden workarounds:

- changing interrupt, timer, `WAIT`, `lpj`, or CP0 timing;
- invalidating the target cache line unconditionally;
- disabling L1/L2, MMU, or AXI IDs;
- changing the Linux image, workload, or comparator tolerance;
- changing the store to match QEMU without proving the source operand.

### Phase 4: rerun focused regressions

After the owner fix, run outside the sandbox with the required VCS module:

```text
source /etc/profile.d/modules.sh
module load vcs
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

The root-cause checkpoint is diagnostic evidence, not a Linux boot pass. The
generic `/init` gate must reject panic/oops, simulator failures, missing
markers, and nonzero child status.

### Phase 5: bounded differential recheck

Only after Phase 4 passes, run the bounded comparisons and preserve separate
reports for:

1. QEMU system-mode versus default blocking RTL;
2. QEMU system-mode versus opt-in nonblocking-L1 RTL;
3. blocking RTL versus nonblocking-L1 RTL.

Compare complete retire records, PC/instruction, selected GPRs, CP0 exception
metadata, and committed memory effects. Reject unequal record counts, missing
or duplicate sequence numbers, unmatched stores/loads, partial child logs,
and unexpected termination.

Label a result `BOUNDED_PASS` only with the exact image, CPU/cache mode, record
bound, and terminal condition. This is not unrestricted system-mode
equivalence.

### Phase 6: evidence and status

Write a completion report under the run directory containing:

- source and artifact hashes;
- the narrow CPU store trace;
- the first-wrong boundary and rejected alternatives;
- RTL diff and directed-test results;
- Linux gate logs and differential reports;
- residual risks and unsupported claims.

Update this plan only after the report is complete. Keep the following open
unless separate evidence closes them: full ISA/FPU, unrestricted demand
paging and shootdown, real DDR/QSPI PHY/device timing, formal/CDC/RDC,
synthesis/STA/DFT, board validation, generic userspace, and unbounded
QEMU/RTL equivalence.

## 5. Status ledger

| Item | Status |
| --- | --- |
| Memory owner checker | `PASS`, 196 records / 49 cycles |
| Target-line first visible mutation | `CLASSIFIED`, blocking L1 hit-store at cycle 8567954 |
| CPU store operand owner | `OPEN`, next critical investigation |
| Owner-scoped functional RTL fix | `NOT STARTED` |
| Positive and negative/reset tests for the fix | `NOT STARTED` |
| Root-cause checkpoint after functional fix | `OPEN` |
| Generic RTL `/init` and userspace | `OPEN` |
| Bounded QEMU/RTL differential closure | `OPEN` |
