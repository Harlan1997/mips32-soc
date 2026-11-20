# RTL Linux Differential Fix Plan v17

Plan date: 2026-09-22  
Status: `OPEN / FIRST DIRECT-JAL REDIRECT DIVERGENCE IDENTIFIED`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v16.md`

## 1. Current blocker

The v16 WAIT/timer hypothesis is superseded by a fresher, joined RTL/QEMU
focus run. With the same Linux guest, deterministic seed, and
`rtl-cp0-identity=on`, the first confirmed control-flow mismatch is:

```text
RTL:  0x8800d170  0x0e003380  # JAL 0x8800ce00
      0x8800d174  0x2d050001  # delay slot
      0x8800d178  0x40068000  # incorrect sequential/fall-through PC

QEMU: 0x8800d170  0x0e003380  # JAL 0x8800ce00
      0x8800d174  0x2d050001  # delay slot
      0x8800ce00  ...          # architectural target
```

QEMU focus evidence reports `pc=0x8800d174` and
`next_pc=0x8800ce00`, with no exception or interrupt active. Therefore the
next owner to investigate is the ordinary direct `J/JAL` redirect across its
architectural delay slot. Cache, LL/SC, timer, MMU, and CP0 exception changes
are out of scope until this control-flow mismatch is disproven.

This plan is a repair plan, not a claim of full Linux, ISA, MMU, or product
signoff. The large traces remain under `/tmp/mips32-soc-v16`; repository
artifacts should contain compact reports and manifests only.

## 2. Frozen evidence

Retained evidence:

- QEMU/RTL bounded differential passes the first 20,000 retire records.
- A 1M-cycle RTL run contains 479,757 valid retire records.
- A 300,000-record QEMU trace validates independently.
- The fresh QEMU focus event at the failing window has
  `status=0x10400000`, `cause=0`, `epc=0`, and `badv=0`.
- The current RTL trace is therefore not explained by an exception-entry or
  timer event at this first mismatch.

Canonical diagnostic configuration:

```text
rtl-cp0-identity=on
linux-rng-seed=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff
```

The exact run directory, source hash, guest hashes, RTL defines, QEMU build
identity, and trace paths must be recorded in the next manifest. Do not use
the older QEMU trace without the CP0 identity property as root-cause evidence.

## 3. Closure criteria

The direct-JAL blocker is closed only when:

1. A minimal RTL test fails before the fix by fetching the sequential PC after
   a JAL delay slot and passes after the fix by fetching the encoded target.
2. The test proves exactly one delay-slot retirement and no fall-through
   retirement between the JAL and target.
3. The fix is limited to the direct-jump fetch/redirect owner, or a more
   specific owner is demonstrated by diagnostics before editing.
4. Existing frontend, CPU/CP0, interrupt-delay-slot, and Phase 3 gates pass.
5. A fresh Linux focus run reaches the former mismatch without divergence.
6. The generic Linux gate either reaches `/init` and declared markers or
   reports the next first mismatch as a new, separately classified blocker.
7. The bounded QEMU differential remains fail-closed for incomplete, stale,
   malformed, or mismatched artifacts.

## 4. Execution phases

### Phase 0: freeze a current baseline

Create a compact manifest containing the dirty-worktree hash, RTL/QEMU
commands, feature defines, cycle/retire limits, guest and image SHA-256,
QEMU/plugin hashes, and exit status. Preserve the existing user changes.

Run the already established checks without changing RTL:

```bash
git diff --check
source /etc/profile.d/modules.sh
module load vcs
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

If a resource or license prevents a gate, record `NOT_RUN` with the reason;
do not infer a pass from an older build.

### Phase 1: add a minimal direct-JAL reproducer

Add a focused directed test using the real CPU fetch/ID/IF path. It must cover:

- `JAL target` followed by one ordinary delay-slot instruction;
- target address in the same and a different 256 MB region;
- link register value equal to `PC+8`;
- a fetch stall or bubble at the redirect boundary;
- BPU disabled/default path, plus the existing opt-in BPU path if applicable;
- a negative sequential stream with no control transfer.

The expected architectural sequence is:

```text
JAL, delay-slot, target
```

The sequence must not be accepted if it is `JAL, delay-slot, fall-through,
target`, if the delay slot is duplicated, or if the target is fetched before
the delay slot. Keep the test independent of Linux and QEMU so it fails fast.

### Phase 2: instrument the redirect owner

Add bounded diagnostics at the IF next-PC decision and ID resolution edge,
not only in the retire formatter. For every direct J/JAL candidate record:

```text
cycle, retire_seq
if_pc, if_next_pc, id_pc, id_inst
jump_taken, jump_target, control_target
branch_taken, bpu_valid, bpu_taken, bpu_target
bpu_delay_pending, bpu_delay_target
stall, exception_req, ctx_restore_req
retire_pc, retire_next_pc
```

The diagnostics must identify whether the encoded target is lost in:

1. ID decode/target generation;
2. IF `next_pc` priority selection;
3. BPU delay-pending/recovery state;
4. pipeline flush or stall handling; or
5. only the retire trace’s `next_pc` metadata while fetch is correct.

Do not broaden the trace to all registers or all memory transactions until
this decision is made.

### Phase 3: classify before editing

Use the following owner table:

| Observation | Owner | Required conclusion |
| --- | --- | --- |
| `jump_target` is wrong in ID | decode/target concatenation | verify `PC+4[31:28]`, immediate, and word alignment |
| ID target is right but `if_next_pc` is sequential | IF priority/state | direct jump loses to BPU, stall, or pending state |
| IF fetches target but retire reports fall-through | retire metadata only | fix trace contract; do not change control flow |
| BPU enabled only failure | BPU delay/recovery | repair opt-in BPU state and retain default regression |
| failure with a real exception/flush | flush owner | prove the flush is architecturally active at the same cycle |

The QEMU focus event currently rules out CP0 exception state as the first
owner. A target mismatch must be proven in RTL signals before changing
`mips_cpu.v` delay-slot recovery logic, which already contains broad historical
interrupt fixes.

### Phase 4: apply one owner-scoped fix

Change only the proven owner. The preferred default-path invariant is:

```text
direct J/JAL: fetch delay slot first, then fetch jump_target exactly once
```

Preserve `PC+8` link semantics, branch-likely annul behavior, indirect
JR/JALR behavior, exception/ERET redirects, and BPU opt-in compatibility.
Do not combine this change with cache, MMU, timer, CP0, QSPI, or Linux image
changes.

### Phase 5: regress in increasing scope

Run the reproducer and the required gates:

```bash
make rtl-frontend-compile
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
make phase3-complete
```

Then rerun a bounded RTL trace through `0x8800d170`, a fresh QEMU focus run
with CP0 identity enabled, and the streaming comparator. Check that the first
post-fix mismatch is either absent or reported at a later retired event.

### Phase 6: resume Linux closure

Run the generic Linux progress gate with a bounded trace path and verify, in
order:

1. the direct-JAL window matches QEMU;
2. `devtmpfs: initialized` remains reachable;
3. `/init` and declared userspace markers are observed;
4. no panic, oops, unresolved transaction, or simulator error occurs.

If a later mismatch appears, create a new owner-specific checkpoint rather
than folding it into this JAL fix.

### Phase 7: update signoff evidence

Update the evidence registry with the exact command, manifest, compact report,
and residual-risk classification. Permitted results are:

```text
BOUNDED_PASS | MISMATCH | INVALID_INPUTS | OWNER_UNOBSERVED | NOT_RUN
```

Do not call the result full ISA/MMU/Linux differential. Full FPU, unrestricted
Linux VM semantics, complete privileged ISA, SMP shootdown, physical DDR/QSPI,
and product signoff remain separate gaps.

## 5. Required artifacts

- current-source baseline manifest and hashes;
- direct-JAL reproducer and before/after logs;
- bounded IF/ID redirect diagnostic;
- owner-classification report;
- post-fix frontend/CPU/Phase 3 gate logs;
- fresh RTL and QEMU focus traces with CP0 identity enabled;
- streaming comparison report and generic Linux marker report;
- explicit residual-risk and `NOT_RUN` list.

## 6. Tracking checklist

- [ ] Current baseline manifest frozen
- [ ] Minimal JAL delay-slot reproducer added
- [ ] Reproducer fails before fix
- [ ] IF/ID redirect diagnostics identify the owner
- [ ] One owner-scoped fix applied
- [ ] Frontend, CPU/CP0, IRQ delay-slot, and Phase 3 gates pass
- [ ] QEMU focus run uses `rtl-cp0-identity=on`
- [ ] Post-fix bounded comparison passes through the prior mismatch
- [ ] Generic Linux reaches `/init` and declared markers
- [ ] Evidence registry and residual risks updated

## 7. Explicitly deferred

Full ISA/FPU compliance, demand-paging Linux ownership, SMP shootdown stress,
complete MMU/QEMU equivalence, broad SoC peripheral model equivalence, DDR PHY
and JEDEC timing, QSPI device timing, CDC/RDC/STA/DFT, and board validation
remain outside this focused repair.
