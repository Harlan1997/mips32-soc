# RTL Linux Differential Fix Plan v14

Plan date: 2026-09-22  
Status: `OPEN / LL-SC AND KERNEL PROGRESS BLOCKER`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v13.md`

## 1. Objective

Close the next evidence-backed blocker in the bounded RTL/QEMU Linux flow.
The current RTL run reaches kernel initialization and repeatedly executes the
`down_write()` lock path, but does not reach `/init` or the declared userspace
marker. The immediate objective is to identify and repair the first incorrect
LL/SC, reservation, cache, or exception/replay boundary without changing the
default architectural contract.

This plan closes a bounded generic-Linux progress gate. It does not claim full
MIPS32 privileged-ISA compliance, unrestricted Linux, full MMU/OS semantics,
FPU support, or unrestricted QEMU/RTL equivalence.

## 2. Current evidence snapshot

| Boundary | Evidence | Status |
| --- | --- | --- |
| RTL frontend | Current compile passed `8/8` | Pass |
| CPU/CP0 gate | `make cpu-cp0-gate` passed | Pass |
| Linux Count/Compare readback | `0` mismatches; `0` unexpected backsteps | Pass |
| Timer interrupts | `102` accepted interrupts in the 30M-cycle run | Pass |
| WAIT wakeup | Repeated wakeup and ERET return observed | Pass |
| RTL generic Linux userspace | No userspace marker; stops in kernel-side path after `devtmpfs: initialized` | Open |
| First useful lock-path PC | `0x88a5a304: bnez a1, 0x88a5a31c` after `ll a1, 0(a0)` in `down_write()` | Open |
| LL/SC diagnostic | Reservation and effective address fields are present, but no architectural SC result classification exists yet | Open |
| QEMU timer comparison | Not run; expected source tree is absent | Environment blocked |
| Strict QEMU/RTL differential | No valid pair reaching the common terminal marker | Open |

Primary diagnostic artifacts:

```text
/data/disk/tmp/mips32-soc/plan-v13-rtl-wait-timer-20260922/baseline-diagnostic/
/data/disk/tmp/mips32-soc/plan-v13-rtl-wait-timer-20260922/llsc-window/sim/sim_runtime.log
```

The LL/SC trace contains examples where the reservation and effective data
addresses differ in representation, including `0941933c` versus `8941933c`.
This is a high-priority hypothesis for address normalization or pipeline-stage
ownership, not a confirmed root cause. The first wrong architectural event
must be proven before RTL changes.

## 3. Invariants and non-goals

- Preserve default `MMU=0`, blocking L1/D-cache behavior, x1 QSPI, and existing
  firmware contracts.
- Keep nonblocking L1, Linux guest compatibility options, and diagnostic entropy
  behavior opt-in unless a separate contract is approved.
- Do not fix the failure by changing `lpj`, timer frequency, Count/Compare
  tolerance, WAIT behavior, host timeout, comparator tolerance, or marker rules.
- Do not retain an LL reservation across an architectural context switch or an
  exception unless the implementation contract explicitly requires it.
- Do not make a virtual/physical address alias compare pass by truncating bits
  or accepting any mismatch; define and test one canonical reservation key.
- Do not label a bounded kernel-progress result as generic Linux signoff.
- Keep large logs, compiled simulators, and QEMU source/build trees under
  `/data/disk/tmp/mips32-soc` or another explicitly configured temporary root.
- Preserve unrelated dirty-worktree changes and record source/artifact hashes
  for every run.

## 4. Execution plan

### Phase 0: freeze the current failure

Create a fresh run root and capture:

- commit plus dirty-worktree identity;
- RTL defines, simulator version, compile command, plusargs and seed;
- kernel, DTB, Boot ROM, DDR/root image and manifest hashes;
- exact PC/cycle window, host timeout and terminal-marker contract;
- current RTL progress log and LL/SC window log;
- QEMU binary/plugin identity, or an explicit `NOT_RUN` reason.

Run the existing checks without modifying RTL:

```bash
git diff --check
make rtl-frontend-compile
make cpu-cp0-gate
make linux-timer-clock-comparison-test
make cpu-irq-delay-slot-gate
```

Acceptance: the result reproduces the kernel-only terminal state and records
all missing gates as `NOT_RUN`, never as a pass inferred from timeout.

### Phase 1: make LL/SC observability architectural

Extend the diagnostic record at the retirement/request boundary with an
explicit event type and sequence number. For every LL or SC, record:

```text
cycle, retire_seq, pc, instruction, event=LL|SC,
virtual_address, canonical_physical_line, byte/word offset,
reservation_valid_before, reservation_key_before,
reservation_valid_after, reservation_key_after,
reservation_clear_reason, sc_match, sc_write_enabled, sc_result,
data_req, data_addr_ok, data_data_ok, data_wdata,
exception_flush, ctx_restore, interrupt_accept, cache_snoop,
selected GPR state and committed GPR write
```

The trace must distinguish request issue, response completion and architectural
retirement. A held request may not be reported as a second LL/SC event merely
because the pipeline remains stalled. Add a bounded parser that rejects missing
fields, duplicate event sequence numbers, unknown clear reasons and an SC result
without a matching LL/reservation history.

Acceptance: one focused run produces a complete LL-to-SC history for the
`down_write()` window, including every reservation invalidation reason.

### Phase 2: prove the first wrong LL/SC boundary

Analyze the focused trace in this order:

| First observed divergence | Owner to investigate | Required proof |
| --- | --- | --- |
| LL loads a different lock value | D-cache refill, byte lane, memory image, or load retirement | Compare request/response data and committed register value with a directed LL test |
| LL value matches but reservation key differs | VA-to-PA normalization or cache alias handling | Show both addresses, canonical line key, and translation state at the same event |
| Reservation is cleared before SC | exception, interrupt, context restore, snoop, ordinary store, or reset path | Identify exactly one clear reason and reproduce it in a minimal test |
| Reservation remains but `sc_match=0` | reservation-key compare or effective-address pipeline owner | Compare aligned physical line keys and prove the SC uses the correct request address |
| `sc_match=1` but no write occurs | data request/response handshake or cache write path | Show `data_we`, cache acceptance, completion, and memory/cache line update |
| SC writes but destination register is wrong | SC result writeback/forwarding/retirement | Compare result `0/1` at commit and the next branch operand |
| LL/SC is correct but control flow diverges | delay slot, exception replay, or precise interrupt boundary | Compare retire PC, EPC, BD, and branch target around the first mismatch |
| LL/SC/control flow match but lock path still loops | Linux memory ordering, scheduler/lock contract, or unrelated load/store owner | Compare later memory transactions and move the owner out of LL/SC |

Do not patch address masks or reservation lifetime based solely on the
`0941933c`/`8941933c` display. First establish whether those fields are the
same canonical physical line, different aliases, or values sampled from
different pipeline stages.

### Phase 3: add minimal reproducers before any RTL fix

Add or reuse directed tests for:

1. successful LL/SC on cached and uncached aliases of one word;
2. failed SC after an ordinary store to the same cache line;
3. failed SC after interrupt/exception and after context restore;
4. delayed D-cache response with a held LL/SC request;
5. same-line snoop invalidation and refill collision;
6. SC result forwarding into a branch immediately following the SC.

Each test must check the lock value, reservation key, SC result, committed
memory effect, destination register, and terminal PC. Include reset-in-flight,
backpressure, and error-response cases where the affected cache path supports
them.

Acceptance: the selected reproducer fails for the diagnosed owner and passes
after the proposed change. If no reproducer fails, classify the Linux issue as
unobserved by the current LL/SC instrumentation and continue with the next
architectural boundary rather than making a speculative fix.

### Phase 4: apply one owner-scoped RTL change

Modify only the proven owner. Candidate changes may include:

- one canonical physical-line reservation key shared by LL, SC and snoop;
- correction of request/response stage capture for LL or SC;
- precise reservation clearing on the proven architectural event;
- correction of SC result writeback or branch forwarding;
- correction of exception/replay metadata if LL/SC is proven equal.

Do not combine a cache, CP0, branch, MMU and LL/SC change in one patch. The
change must retain the default blocking path and must include a short comment
only where the ownership rule is not obvious.

Required regression after the change:

```bash
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Then rerun the minimal reproducer and the exact generic Linux manifest. A
passing unit test with a new Linux terminal failure is not closure.

### Phase 5: close generic RTL Linux progress

Run the staged gates with one immutable image/configuration manifest:

1. root-cause checkpoint gate: complete LL/SC and exception records through
   the first lock-path window;
2. generic init gate: console, `ttyS0`, initramfs and `/init` in order;
3. generic userspace gate: process creation, timer/sleep, GPIO and entropy
   markers, with no panic/oops/unresolved transaction.

Run default blocking and opt-in nonblocking L1 separately. The nonblocking
run is a compatibility check, not a substitute for the default baseline.

Acceptance requires the guest itself to emit `/init` and userspace markers;
host timeout, UART silence, or a bounded PC heartbeat is insufficient.

### Phase 6: restore and run QEMU system differential

The expected QEMU source tree is currently missing:

```text
/home/admin/mips32-soc/build/deps/src/qemu-9.2.0
```

Resolve this as a separate environment task using the pinned official QEMU
9.2.0 source/archive or a verified prebuilt binary. Record provenance and
hashes; do not silently substitute user-mode QEMU for the custom machine.
Build or obtain the `mips32-soc-ref` system-mode binary, then run the QEMU
timer comparison and system retire capture before the strict differential.

The final bounded differential must fail closed on unequal manifests, missing
terminal markers, incomplete retire streams, QEMU nonzero exit, simulator
timeout, or unsupported state. It may report `BOUNDED_PASS`, `MISMATCH`,
`INVALID_INPUTS`, `OWNER_UNOBSERVED`, or `NOT_RUN`; it must not report full
ISA/MMU/Linux equivalence.

## 5. Required artifacts

Each phase retains only the bounded evidence needed for review:

- run manifest and SHA-256 artifact list;
- LL/SC normalized trace and parser report;
- first-divergence/owner report;
- minimal reproducer compile and simulation logs;
- RTL frontend and affected regression reports;
- generic Linux terminal report and guest marker transcript;
- QEMU provenance/build log and system-mode trace when available;
- residual-risk and explicitly unrun-check list.

Large simulator and build intermediates belong under `/data/disk/tmp/mips32-soc`
and may be pruned only after hashes and reports are retained.

## 6. Tracking checklist

- [ ] v14 run manifest and fresh baseline captured
- [ ] LL/SC event schema defined and parser fail-closed
- [ ] complete `down_write()` LL-to-SC history captured
- [ ] first wrong boundary classified to one owner
- [ ] minimal owner reproducer fails before the fix
- [ ] one owner-scoped RTL change implemented, if required
- [ ] frontend, CPU/CP0, delay-slot and Phase 3 gates pass
- [ ] default blocking RTL reaches `/init` and userspace marker
- [ ] opt-in nonblocking path is separately classified
- [ ] pinned QEMU system-mode source/binary provenance restored
- [ ] QEMU timer/system capture gates pass or are explicitly `NOT_RUN`
- [ ] strict bounded QEMU/RTL differential report is fail-closed
- [ ] residual scope is recorded without full-compliance claims

## 7. Residual scope after v14

Even after this plan closes, the following remain separate unless independently
gated: full MIPS32/FPU and privileged ISA coverage, complete demand paging and
SMP shootdown stress, full ISA/MMU/QEMU differential, Linux-wide device model
coverage, production DDR PHY/JEDEC timing, QSPI device timing, STA/DFT, CDC/RDC
signoff, and board-level validation.
