# RTL Linux Differential Fix Plan v13

Plan date: 2026-09-22  
Status: `OPEN / RTL WAIT-TIMER BLOCKER`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v12.md`

## 1. Objective

Close the next largest current-source gap in the bounded RTL/QEMU Linux
differential flow: generic RTL Linux must leave the kernel idle/wait path,
receive the expected timer interrupt, and reach the declared userspace marker
before a full architectural comparison is attempted.

This plan is intentionally bounded. Passing it does not claim full MIPS32
privileged ISA compliance, unrestricted Linux support, FPU completeness,
unbounded QEMU/RTL equivalence, or physical DDR/QSPI/PHY signoff.

## 2. Current evidence

| Area | Current status | Interpretation |
| --- | --- | --- |
| Canonical differential manifest | Implemented | Input identity can now fail closed before comparison. |
| Trace sequence/terminal validation | Implemented and unit-tested | Invalid, truncated, reordered, or stale traces must not pass. |
| QEMU deterministic entropy | Proven for the diagnostic workload | Same-seed output repeats; seed A/B changes `MIPS32_SOC_LINUX_RANDOM`. |
| QEMU system-mode boot | Bounded pass | Custom `mips32-soc-ref` reaches UART and the entropy probe. |
| RTL same-seed entropy | Not reached | The RTL run stops in kernel idle/wait before userspace. |
| RTL bounded end state | Reproduced | At 30M cycles, PC is `0x88a55d98` in `r4k_wait`; `timer_ip=0`. |
| CP0 timer implementation | Not yet classified | Count/Compare/TI, interrupt masking/routing, and timer source need an edge trace. |
| `scheduler_timer_tick` | Tied to `1'b0` in `soc_core_subsystem` | This is a scheduler input, not proof that CP0 Count is stopped. |
| Full RTL/QEMU Linux differential | Open | No valid full userspace terminal pair exists yet. |

The current evidence is a blocker classification, not a timer root-cause
claim. Existing CP0 timer and WAIT regressions must be run before RTL changes.

## 3. Non-goals and invariants

- Preserve default `MMU=0`, blocking cache, x1 QSPI, and existing firmware
  contracts while diagnosing this failure.
- Keep the entropy probe and `rngdet` path opt-in; do not make the diagnostic
  `getrandom()` workload the default Linux image without a separate contract
  review.
- Do not fix the failure by changing `lpj`, `WAIT`, Count/Compare tolerance,
  interrupt timing, timeout limits, or differential comparator semantics.
- Do not infer a CP0 bug solely from `scheduler_timer_tick=0`; trace the actual
  CP0 Count/TI/Cause/IP/interrupt-accept path.
- Keep all large logs and simulator artifacts under `/data/disk/tmp/mips32-soc`.
- Preserve unrelated dirty-worktree changes and record the complete source
  identity in every run manifest.

## 4. Execution plan

### Phase 0: freeze a reproducible baseline

Create a fresh run root, for example:

```text
/data/disk/tmp/mips32-soc/plan-v13-rtl-wait-timer-20260922/
```

Record:

- git commit and dirty-worktree hash;
- RTL source identity, simulator/tool versions, defines and plusargs;
- kernel, DTB, Boot ROM, DDR/root image, QEMU binary and plugin hashes;
- cycle, retire, host-timeout and terminal-marker bounds;
- exact commands, exit codes, signal/timeout status, and log paths.

Run the unchanged baseline first:

```bash
make rtl-frontend-compile
make qemu-system-cp0-timer-wait-differential-gate
make linux-timer-clock-comparison-test
make cpu-cp0-gate
```

Acceptance: baseline results are classified as `PASS`, `FAIL`, or
`NOT_RUN`; no timeout or missing marker is silently promoted to pass.

### Phase 1: instrument the timer-to-WAIT chain

Add a bounded diagnostic trace, disabled by default, at the actual ownership
boundaries. At every transition or at a low-rate heartbeat, capture:

```text
cycle, retire_seq, pc, wait_state, wait_resume_pc,
cp0_count, cp0_compare, count_prescale, count_div,
cnt_eq_cmp, Cause.TI, Cause.IP, Status.IE/EXL/ERL,
Status.IM, IntCtl.IPTI, hw_int, combined_ip_hw,
timer_ip_active, intr_req, interrupt_accept, exception code/EPC/BD,
APB timer interrupt, PIC raw/masked/pending/active state,
scheduler_timer_tick
```

The trace must distinguish these edges:

1. Linux writes Count or Compare.
2. Count advances through the programmed Compare value.
3. TI becomes set and remains set until Compare write.
4. the timer IP bit is visible in Cause and passes Status mask/IE/EXL/ERL;
5. `intr_req` becomes true;
6. `interrupt_accept` wakes WAIT and records the expected EPC/BD;
7. the handler writes the next Compare and ERET returns to Linux.

Add assertions/checks for monotonic Count progression while `DC=0`, TI set
on the documented match condition, Cause.IP routing from TI, no interrupt
accept while EXL/ERL/masked, and WAIT wakeup preserving `wait_resume_pc`.

Acceptance: the first absent transition is named. The report must classify
the owner as one of `CP0_COUNT`, `CP0_TI`, `CAUSE_IP_ROUTING`, `INT_MASK`,
`CPU_INTERRUPT_ACCEPT`, `WAIT_WAKEUP`, `PIC/APB_TIMER`, or `LINUX_PROGRAMMING`.

### Phase 2: classify before modifying RTL

Use the Phase 1 trace and the Linux CP0 write trace to select exactly one
branch:

| First wrong boundary | Allowed next action |
| --- | --- |
| Linux never writes a usable Compare | Diagnose CP0 write/retirement, MMU/cache load, or Linux image mismatch. |
| Count does not advance | Fix CP0 Count ownership/prescaler/DC handling; add a directed Count test. |
| Count crosses Compare but TI stays clear | Fix only the Count/Compare/TI match contract; add same-cycle write/match coverage. |
| TI is set but Cause.IP is absent | Fix only timer routing/IPTI/refresh logic; add masked and collision tests. |
| Cause.IP is pending but `intr_req` is false | Fix only IE/EXL/ERL/IM priority semantics; add nested/blocked interrupt tests. |
| `intr_req` is true but WAIT does not wake | Fix only CPU interrupt acceptance or WAIT state ownership; retain EPC/BD assertions. |
| WAIT wakes and handler runs but reprogramming fails | Compare CP0 writes, APB/PIC traffic, and handler retirement before changing RTL. |
| All transitions pass but userspace remains absent | Move ownership to Linux memory/cache/MMU/console/scheduler integration; do not alter CP0 timing. |

No code change is justified until one boundary is shown wrong in a fresh
current-source trace.

### Phase 3: apply one owner-scoped fix and regress it

For the selected owner only:

1. add a minimal directed reproducer that fails at the same boundary;
2. make one RTL change with no default-feature expansion;
3. add reset, backpressure, masked/EXL, same-cycle write, and repeated-timer
   coverage appropriate to that owner;
4. run frontend compile and the affected CP0/CPU/PIC/APB gates;
5. rerun the exact Linux manifest and compare the first wrong boundary;
6. rerun the unchanged blocking baseline and existing phase gates.

Required minimum after any RTL change:

```bash
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

An isolated timer fix must not be accepted if it regresses delay-slot,
exception, reset, or default blocking behavior.

### Phase 4: prove RTL generic Linux progress

Run staged gates with one manifest and the same image/configuration:

1. `rtl-linux-root-cause-checkpoint-gate`: timer/wait and the known first
   architectural checkpoints have valid retire records.
2. `rtl-linux-generic-init-gate`: early console, `ttyS0`, initramfs, and
   `/init` execute in the declared order.
3. `rtl-linux-generic-userspace-gate`: userspace process, timer/sleep, GPIO,
   and entropy markers are reached without panic/oops.

Run blocking and opt-in nonblocking configurations separately. A minimal
userspace pass cannot substitute for generic Linux.

Acceptance for the entropy workload:

- RTL same-seed runs produce identical entropy-dependent records;
- RTL seed A/B changes the intended random value;
- QEMU and RTL manifests agree on seed, image, command line and bounds;
- missing/malformed entropy metadata fails closed;
- the terminal marker is emitted by the guest, not inferred from timeout.

### Phase 5: close the differential gate

Only after Phase 4 passes, run the strict QEMU/RTL comparison. Compare
retired records at the agreed architectural boundary, including PC,
instruction, selected/all GPR state, HI/LO, committed memory operations,
LL/SC result, implemented CP0 state, exception metadata, delay-slot metadata,
and TLB operations where enabled.

The report must contain:

- equal manifest identity and artifact hashes;
- complete record counts and terminal condition;
- first mismatch and owner classification;
- repeatability hashes for both implementations;
- negative validator results;
- simulator exit/timeout status and residual unrun checks.

Valid outcomes are `BOUNDED_PASS`, `MISMATCH`, `INVALID_INPUTS`,
`OWNER_UNOBSERVED`, or `NOT_RUN`. `BOUNDED_PASS` must not be described as
full ISA, full MMU, or unrestricted Linux equivalence.

## 5. Tracking checklist

- [ ] v13 manifest/run root created outside repository build output
- [ ] unchanged CP0 timer/WAIT baseline gates recorded
- [ ] timer-to-WAIT edge trace implemented and bounded
- [ ] first missing transition classified with an owner
- [ ] minimal owner reproducer added
- [ ] owner-scoped RTL fix, if required, implemented
- [ ] CP0/CPU/PIC/APB/reset regressions pass
- [ ] RTL reaches generic Linux `/init`
- [ ] RTL reaches declared userspace marker
- [ ] RTL same-seed and seed A/B entropy checks pass
- [ ] QEMU/RTL strict differential runs with a valid manifest
- [ ] v13 completion report records residual risks and unrun checks

## 6. Residual scope after v13

Even if this bounded gate closes, the following remain separate work:

- complete MIPS32 privileged ISA and FPU compliance;
- unrestricted Linux userspace, demand paging and SMP shootdown stress;
- full ISA/MMU/QEMU differential beyond the declared record/boundary set;
- production DDR PHY/JEDEC timing, QSPI device timing, STA, DFT and board
  validation;
- formal, CDC and RDC signoff when the required commercial tools are absent.
