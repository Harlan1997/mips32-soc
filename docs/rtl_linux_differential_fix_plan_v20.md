# RTL Linux Differential Fix Plan v20

Plan date: 2026-09-23  
Status: `OPEN / INPUT IDENTITY AND FIRST MISMATCH REQUIRED`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v19.md`

## 1. Objective

Close the largest remaining architectural gap: a current-source, system-mode
Linux differential between the RTL and QEMU `mips32-soc-ref` machine. The next
RTL change is allowed only after both models consume the same image bundle and
the first committed architectural mismatch has been classified.

This plan does not claim unrestricted Linux, complete MIPS32/FPU compliance,
or product-level DDR/QSPI/PHY signoff. Its closure target is a bounded,
reproducible Linux run with a strict retire comparison and a declared terminal
userspace checkpoint.

## 2. Current evidence and blocker

| Boundary | Current status | Interpretation |
| --- | --- | --- |
| RTL frontend and existing CPU gates | Existing evidence is available | Must be rerun after any owner-scoped RTL change |
| RTL Linux 30M-cycle capture | `WAIT_FUTURE_TIMER` / `WAIT_WAKEUP_PROGRESS` | Diagnostic only; 128 WAIT records and 102 accepted interrupts |
| RTL Linux terminal state | `pc=0x88a55d98`, `wait=1`, `resume=0x88002380`, `badv=0xc0000010` | Does not identify timer, cache, MMU, or scheduler ownership |
| QEMU retire capture | 300k records captured with RTL DTB input | Must be validated and compared before extending the run |
| Previous joined comparison | Invalid | It used a different QEMU DTB and omitted CP0 identity |
| Generic RTL Linux userspace | Open | `/init` and all declared markers are not yet proven on current source |

The known comparison error is concrete: RTL used
`image-a/mips32_soc_ref_rtl.dtb`, while QEMU previously used
`kernel-random/mips32_soc_ref.dtb`. The first observed data difference at
`0x88a13f74` therefore cannot be assigned to RTL. A QEMU trace pass with
different guest bytes is invalid.

## 3. Non-negotiable run contract

Every run must record a manifest under its temporary run root containing:

- kernel, DTB, Boot ROM, DDR image, command line, RAM size, and RNG seed;
- QEMU binary, QEMU source/build identity, plugin hash, and machine properties;
- RTL simulator hash, RTL source/dirty-worktree identity, defines, and plusargs;
- cycle/retire/host bounds, exit statuses, record counts, and free space;
- SHA-256 hashes before execution and after artifact generation.

The QEMU DTB must be selected from the exact RTL image manifest, or the gate
must fail closed. A DTB inferred from the kernel directory is forbidden for
the joined gate. A timeout, stale artifact, truncated trace, missing marker,
or producer-only result is `INCOMPLETE`, never `PASS`.

Large traces remain under `/data/disk/tmp/mips32-soc`; repository documents
retain only compact reports, hashes, and the run path.

## 4. Ordered implementation plan

### Phase 0: validate the current same-DTB capture

1. Poll and validate the existing run:
   `/data/disk/tmp/mips32-soc/repo-build-20260905/v19-qemu-retire-300k-rtl-dtb`.
2. Confirm the QEMU trace has exactly the declared bound and has a clean
   lifecycle/flush status.
3. Compare it to the RTL trace using the same first-PC alignment, CP0 identity,
   and streaming comparator.
4. Save the result and all input hashes in a new v20 run manifest.

Required comparison:

```bash
python3 tb/isa_ref/trace_compare.py \
  --align-first-pc 88a55e74 --allow-golden-prefix \
  --truncate-golden-to-rtl --stream \
  <rtl-retire.jsonl> <qemu-retire.jsonl>
```

Acceptance: the report explicitly says `PASS`, `FIRST_MISMATCH`, or
`INVALID_INPUT`. `INVALID_INPUT` must be fixed before any RTL diagnosis.

### Phase 1: make DTB/image identity fail-closed

Update `tb/isa_ref/run_qemu_linux_differential_gate.sh` and the image-build
handoff so that:

- `DTB` is required or resolved only from `LINUX_IMAGE_DIR`'s manifest;
- the manifest names the RTL DTB and QEMU DTB separately and requires equal
  hashes for the joined comparison;
- kernel, DTB, Boot ROM, DDR image, RAM size, command line, and CP0 machine
  properties are checked before either producer starts;
- QEMU is always invoked with `rtl-cp0-identity=on` for this contract;
- a missing or mismatched identity exits nonzero before simulation.

Add a regression fixture for a deliberately wrong DTB and verify that the gate
rejects it before producing a comparison result. Preserve the existing
reference-only gates; this change applies to the joined Linux differential.

Acceptance: changing one input byte causes a deterministic manifest failure,
not a later architectural mismatch.

### Phase 2: prove producer and comparator lifecycle

Run the QEMU lifecycle gate for normal completion, record-limit completion,
expected timeout, missing target, and forced plugin failure. Check that:

- records are flushed at exit;
- sequence numbers are monotonic and unique;
- no partial JSONL record is accepted;
- QEMU nonzero status is propagated;
- exact bounded record counts are enforced.

Rerun the focus-plugin parser tests after the non-focus register-read
optimization. Keep QEMU samples explicitly labeled with their architectural
sampling phase; do not treat a translation-block callback as retirement.

Acceptance: lifecycle failures fail the gate and a successful capture has a
complete, validated trace.

### Phase 3: obtain the first valid joined mismatch

Compare the same-DTB QEMU and RTL streams at 300k records. If the prefix
passes, extend in bounded increments (600k, 1.2M, then the first declared
Linux checkpoint) without changing the manifest.

For the first mismatch, retain at least 32 records before and after it and
classify one owner:

| Evidence | First owner to investigate |
| --- | --- |
| PC, instruction, delay-slot, or `next_pc` differs | fetch, redirect, flush, exception replay |
| GPR or HI/LO differs before WAIT | writeback, forwarding, replay, or memory response |
| Count/Compare/Status/Cause/EPC differs | CP0 or interrupt priority/WAIT contract |
| CPU state matches but load/store data differs | D-cache, L2, DDR image, or translation visibility |
| CPU and memory match but UART/VIC behavior differs | APB/peripheral model or RTL peripheral |
| BadVAddr/TLB metadata differs | fault owner, MMU refill, or pending-fault lifetime |

`WAIT_FUTURE_TIMER` is a terminal classification, not an owner. No timer,
cache, MMU, or interrupt edit is permitted before this classification.

### Phase 4: close generic RTL Linux progress

Run the current generic gate from the same manifest and require, in order:

1. kernel early console and `devtmpfs: initialized`;
2. `Run /init as init process`;
3. GPIO, mmap/mprotect, brk, sleep/yield, exec, wait-status, and fork/wait
   markers;
4. no panic, Oops, simulator fatal, malformed trace, or unbounded timeout.

Run the blocking default and any nonblocking opt-in configuration separately.
A minimal userspace pass cannot substitute for generic Linux, and a QEMU
userspace pass cannot substitute for RTL userspace.

### Phase 5: implement one owner-scoped fix

Add a minimal directed reproducer that fails before the fix and passes after
it. Modify only the owner identified in Phase 3. If the owner is RTL, retain
the default blocking behavior unless the contract explicitly requires an
opt-in change. If the owner is QEMU/model or input packaging, fix that layer
before touching RTL.

Every RTL fix iteration must pass:

```bash
git diff --check
make rtl-frontend-compile
make direct-jal-gate
make cpu-cp0-gate
make cpu-irq-delay-slot-gate
```

Then rerun the owner-specific gate, generic RTL userspace gate, and bounded
same-manifest differential. Preserve the pre-fix trace and first-mismatch
report as evidence.

### Phase 6: declare bounded closure

Run the final contract gates only after Phases 0-5 pass:

```bash
make phase3-complete
make current-contract-signoff
```

The final report must contain equal producer input hashes, compared record
count, first-mismatch result, terminal userspace markers, lifecycle status,
and residual risks. The only acceptable closure label for this plan is
`BOUNDED_LINUX_DIFFERENTIAL_PASS`.

## 5. Tracking checklist

- [ ] v20 run manifest created with exact image and tool hashes
- [ ] Existing 300k same-DTB QEMU capture validated
- [ ] Wrong-DTB negative test fails closed
- [ ] QEMU CP0 identity and lifecycle checks pass
- [ ] First valid RTL/QEMU mismatch or bounded prefix pass recorded
- [ ] Owner category selected from architectural evidence
- [ ] Minimal owner-specific reproducer added
- [ ] Fix iteration passes frontend and CPU regression gates
- [ ] RTL reaches `/init` and all declared generic userspace markers
- [ ] Phase 3 and current-contract gates pass
- [ ] Final bounded differential report and residual-risk list published

## 6. Explicit non-claims

This plan does not close full MIPS32 ISA compliance, FPU completeness,
arbitrary Linux workloads, full demand paging and SMP shootdown semantics,
unrestricted QEMU equivalence, physical DDR/QSPI timing, PHY training, DFT,
STA, or ASIC release signoff. Those remain separate contracts.
