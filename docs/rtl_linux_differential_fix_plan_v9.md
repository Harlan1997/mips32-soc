# RTL Linux Differential Fix Plan v9

Plan date: 2026-09-21  
Status: `OPEN / OWNER-SOURCE CLASSIFICATION`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v8.md`

## 1. Objective

Close the current bounded RTL Linux mismatch without changing timer, `WAIT`,
`lpj`, CP0 Compare, interrupt, MMU policy, or Linux command-line behavior as
a workaround.

The current target mismatch is:

```text
PC   = 0x8886cebc
inst = 0x8e62ea9c       # lw v0,-5476(s3)
VA   = 0x88c4ea9c
PA   = 0x08c4ea9c
line = 0x08c4ea80
QEMU = 0x0df62201
RTL  = 0x28e6de6b
```

The next task is to identify the first owner of `0x28e6de6b`, then apply one
owner-scoped fix and rerun the declared Linux gates. A diagnostic pass is not
a functional closure claim.

## 2. New evidence and corrected interpretation

Fresh run:

```text
/data/disk/tmp/mips32-soc/plan-v8-owner-ddr-20260921
```

The owner checker passes:

```text
LINUX_MEMORY_OWNER_TRACE_PASS records=196 cycles=49
```

The relevant observations are:

| Observation | Meaning | Status |
| --- | --- | --- |
| DDR target word is `0x28e6de6b` before the late load | The backing model already contains the wrong value | Proven |
| DDR `s_r` traffic around the late load is instruction traffic | The sampled DDR response is not evidence that DDR returned the target data word | Proven |
| Store `PA=0x09425bfc`, `data=0x28e6de6b` occurs after the target load response | This store cannot be the causal owner of this occurrence | Proven for this occurrence |
| `data_rdata` changes from `0x88db0000` to `0x28e6de6b` while the target request is outstanding | A cache/refill/response source still needs to be joined to the architectural response | Open |
| L2 target-array record is invalid and contains no target line | The current L2 observation does not prove L2 ownership | Open |

Therefore the current hypothesis is not “DDR controller read corruption.” The
remaining candidates are:

```text
earlier committed write or image load
  -> DDR backing-array write/index or stale contents
  -> crossbar/DDR response source selection
  -> L2/L1 refill or cached-line state
  -> word extraction / response mux
  -> architectural load result
```

The `LINUX_MEMORY_OWNER_STORE` record currently shows the sampled CPU request
and request buffer, not a complete accepted-write history. It must not be
treated as proof that all backing-array writes have been accounted for.

## 3. Definition of done

This plan is closed only when all items below are fresh and based on the
current dirty worktree:

1. A trace identifies the first boundary that contains `0x28e6de6b` for the
   target line and distinguishes valid, absent, and four-state values.
2. The trace proves whether the target line was written by an earlier store,
   loaded from the image, or produced by a cache/response path.
3. One RTL fix is limited to that owner boundary and has a positive test plus
   reset/backpressure/error or negative coverage.
4. The original target load matches QEMU, or the newly exposed first mismatch
   is independently classified.
5. The root-cause checkpoint and generic `/init` gate pass, with residual
   scope recorded. No full ISA, full MMU, generic Linux, or unrestricted
   QEMU/RTL equivalence claim is made without separate evidence.

## 4. Execution plan

### Phase 0: freeze and reproduce

Create a new run directory below `/data/disk/tmp/mips32-soc` and save:

- commit, branch, dirty status, and `git diff` hash;
- kernel, DTB, Boot ROM, DDR image, QEMU, simulator, and plugin hashes;
- defines, plusargs, cycle limit, target line, and trace window;
- tool versions and all child exit statuses;
- the first target-load divergence and the complete owner-trace checker output.

Run:

```text
git diff --check
bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh
bash -n tb/linux_boot/run_rtl_linux_root_cause_checkpoint_gate.sh
bash -n tb/linux_boot/run_rtl_linux_generic_init_gate.sh
make linux-memory-owner-trace-checker-test
make rtl-frontend-compile
```

Acceptance: the run reproduces the target PC, PA, and both values, or the
manifest records why the input/source set differs.

### Phase 1: complete the owner trace

Extend the opt-in trace in `tb/soc_test/tb_mips_soc.v` with a transaction ID
and target-line filtering at every data boundary. Keep records short and
machine-parseable. Add these record groups:

```text
LINUX_MEMORY_OWNER_WRITE_ACCEPT
LINUX_MEMORY_OWNER_DDR_WRITE
LINUX_MEMORY_OWNER_DDR_READ
LINUX_MEMORY_OWNER_L2_REFILL
LINUX_MEMORY_OWNER_L1_REFILL
LINUX_MEMORY_OWNER_L1_RESPONSE
```

Required information:

- cycle, transaction ID, PA/line, byte offset, beat, byte enable, and valid;
- CPU committed store PC, PA, data, byte enable, and acceptance;
- DDR write address/data and backing-array index after byte enables;
- DDR read address, beat number, response data, and response ID;
- crossbar route and response ID for data versus instruction traffic;
- L2 request/response and array write data;
- L1 refill buffer, line install, word extraction, response mux, and
  architectural `data_rdata`.

For unavailable channels use `valid=0`; do not use `<NIL>` or a zero value to
mean “not present.” The checker must reject duplicate fields, malformed
records, missing transaction IDs, mixed target lines, and incomplete paired
request/response records.

Acceptance: one run covers the target line from its first initialization or
write through the late load and produces a joined transaction table.

### Phase 2: classify the first wrong boundary

Run the late window first, then extend backward in chunks until the first
target-line write or fill is found. Use the same source and image manifest.

Classify exactly one result:

| First wrong boundary | Next action |
| --- | --- |
| Image initialization is wrong | Fix image address/format/loading and add an image-load test. |
| DDR backing write/index is wrong | Fix DDR byte-lane/index/write acceptance and add burst/backpressure coverage. |
| DDR read/response is wrong while backing data is correct | Fix DDR beat/address/ID routing and add instruction/data arbitration coverage. |
| Crossbar routes an instruction response to a data request | Fix response ID/channel ownership and add out-of-order response tests. |
| L2 refill or array write is first wrong | Fix L2 line/beat/state handling and add refill collision/error tests. |
| L1 refill/install/extraction is first wrong | Fix L1 line-buffer, beat order, word select, or response mux and add reset/backpressure tests. |
| Architectural response is first wrong after cache data is correct | Fix CPU data-response timing/hold/formatting and add load-use/replay tests. |
| No first write can be found | Extend instrumentation to reset/image loading and treat the result as an observability blocker. |

Do not classify from the final `data_rdata`, a later store, or a Linux panic.

### Phase 3: apply one owner-scoped RTL fix

Modify only the module or state-machine boundary identified in Phase 2. The
change must include:

- a directed test for the exact line, beat, byte offset, and response source;
- a reset-in-flight, backpressure, error, or negative test for the same path;
- an assertion or checker for request/response ownership and ID matching;
- frontend compile and the affected cache, AXI, or CPU gate;
- a fresh focused QEMU/RTL comparison using frozen inputs.

Forbidden workarounds:

- changing timer or interrupt timing;
- invalidating the target line unconditionally;
- disabling L1, L2, MMU, or AXI IDs;
- changing the Linux image or comparator tolerance;
- declaring the late store to be the owner without an accepted-write record.

Acceptance: the original load returns `0x0df62201`, or a new first mismatch
has a complete owner trace and a new plan entry.

### Phase 4: restore Linux gates

After the owner fix, run outside the sandbox with the required VCS module:

```text
make rtl-frontend-compile
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
```

The generic gate must reject kernel panic/oops, missing or reordered markers,
AXI/APB errors, incomplete traces, simulator failures, and nonzero child
status. A bounded boot marker is not generic userspace closure.

### Phase 5: bounded differential recheck

Only after Phase 4 passes, run and preserve separate reports for:

1. QEMU versus default blocking RTL;
2. QEMU versus opt-in nonblocking-L1 RTL;
3. blocking RTL versus nonblocking-L1 RTL.

Compare complete retire records, PC/instruction, selected GPRs, CP0 exception
metadata, and committed memory effects. Reject unequal record counts, missing
sequence numbers, duplicate records, unmatched stores/loads, partial child
logs, and unexpected termination.

The result may be labeled `BOUNDED_PASS` only with the exact image, CPU mode,
cache mode, record bound, and terminal condition. It is not unrestricted
system-mode equivalence.

### Phase 6: evidence and status

Write a manifest and completion report under the run directory containing:

- source and artifact hashes;
- joined target-line transaction table;
- first-wrong boundary and rationale;
- RTL diff and directed-test results;
- Linux gate logs and differential reports;
- explicit residual risks and unsupported claims.

Update this plan from `OPEN` only after the report is complete. Keep open
full ISA/FPU, unrestricted demand paging and shootdown, real PHY/device
timing, formal/CDC/RDC, synthesis/STA/DFT, board validation, and unbounded
QEMU/RTL equivalence.

## 5. Current status

| Item | Status |
| --- | --- |
| Owner trace checker | `PASS`, 196 records / 49 cycles |
| DDR target word provenance | `OPEN`: contents are wrong before the late load, write history incomplete |
| Data response source | `OPEN`: cache/response path not joined to DDR data transaction |
| Owner-scoped RTL fix | `NOT STARTED` |
| Generic RTL `/init` and userspace | `OPEN` |
| Full system-mode QEMU/RTL differential | `OPEN` |
