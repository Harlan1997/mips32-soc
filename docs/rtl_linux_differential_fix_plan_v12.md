# RTL Linux Differential Fix Plan v12

Plan date: 2026-09-21  
Status: `OPEN / ENTROPY CONTRACT IMPLEMENTED, GATES NOT YET CLOSED`  
Supersedes: `docs/rtl_linux_differential_fix_plan_v11.md`

## 1. Purpose

Close the next real gap in the RTL Linux differential flow:

1. prove that the new deterministic guest-entropy contract is reproducible in
   both QEMU and RTL;
2. reject stale, incomplete, or mismatched artifacts before comparing traces;
3. rerun the comparison with valid identical inputs; and
4. fix the first RTL-owned architectural mismatch, if one remains.

This is a bounded verification plan. It does not claim full MIPS32/privileged
ISA compliance, unrestricted Linux userspace equivalence, complete demand
paging/shootdown behavior, or product-level DDR/QSPI/PHY signoff.

## 2. Verified baseline

The previous v11 work established the following facts:

| Item | Current state | Evidence |
| --- | --- | --- |
| Linux entropy source | UHI `fw_getenv("rngseed")` is consumed by the selected kernel | seeded kernel build and boot artifact |
| Deterministic mode | Opt-in `rngdet=1` selects a deterministic entropy counter | `setup.c`, `random.c`, `random.h` |
| QEMU seed handoff | QEMU custom machine publishes `rngseed` and `rngdet` | system-mode capture |
| RTL seed handoff | Boot ROM/image publishes the same environment entries | RTL seeded image |
| QEMU repeatability | Two 20,000-retire captures are byte-identical | SHA-256 `9f0f5f...7b9fd90a` |
| QEMU boot | Linux and GPIO success markers are reached | seeded QEMU logs |
| RTL capture | One 20,000-retire seeded capture exists | `rtl-seed-1/rtl/sim/rtl_retire.jsonl` |
| Strict input manifest | Not yet enforced for every comparison | remaining gap |
| RTL repeatability | One capture is insufficient | remaining gap |
| Valid QEMU/RTL first mismatch | Not yet classified after entropy control | remaining gap |

The working evidence root is:

```text
/data/disk/tmp/mips32-soc/plan-v11-entropy-contract-20260921
```

Existing dirty-worktree changes and prior artifacts remain user-owned. This
plan must not revert or silently replace them.

## 3. Definition of done

The plan is complete only when all conditions below are met:

- every run has an immutable machine-readable manifest;
- QEMU and RTL use equal kernel, DTB, boot ROM, DDR image, workload, entropy
  mode, seed ID, and declared bounds;
- repeated same-seed QEMU and RTL captures are identical for the compared
  record classes;
- a different seed changes an explicitly entropy-dependent record;
- malformed or missing deterministic-input metadata fails closed;
- trace sequence numbers and terminal conditions are validated;
- the first post-contract architectural mismatch is reported with its owner;
- any RTL change is limited to that owner and has a reproducer plus regression;
- the final report distinguishes `PASS`, `INVALID_INPUTS`, `MISMATCH`,
  `OWNER_UNOBSERVED`, and `NOT_RUN`.

No bounded differential result is a signoff if it lacks the manifest or if a
child process ended by timeout, signal, truncation, or an undeclared bound.

## 4. Execution order

### Phase 0: freeze the run and inspect the current implementation

Before modifying RTL, capture the exact current source state and verify the
new entropy path is present in all consumers:

- `third_party/linux/arch/mips/kernel/setup.c`;
- `third_party/linux/drivers/char/random.c`;
- `third_party/linux/include/linux/random.h`;
- `scripts/qemu/mips32_soc_ref.c`;
- `tb/linux_boot/rtl_bootrom.S`;
- `tb/linux_boot/build_rtl_linux_image.sh`;
- QEMU and RTL Linux differential runners.

Record commit, complete dirty-worktree listing, hashes of all source and
generated artifacts, tool versions, command lines, defines, bounds, and exit
codes.

Acceptance:

```text
git diff --check
bash -n tb/isa_ref/run_qemu_linux_differential_gate.sh
bash -n tb/linux_boot/run_rtl_linux_focus_differential_gate.sh
make rtl-frontend-compile
```

### Phase 1: add one canonical differential manifest

Implement a single manifest writer/validator shared by the QEMU and RTL
Linux runners. JSON is preferred; a shell key/value companion may remain for
humans, but it is not the validation authority.

Required fields:

```text
schema_version
git_commit
git_dirty_status_hash
kernel_sha256
dtb_sha256
bootrom_sha256
ddr_image_sha256
root_image_sha256
qemu_sha256
qemu_plugin_sha256
rtl_simulator_sha256
rtl_source_identity_sha256
entropy_mode
entropy_seed_id
entropy_seed_width
entropy_contract_version
qemu_machine
rtl_defines
linux_cmdline
retire_bound
cycle_bound
timeout_bound
terminal_condition
```

Reject missing fields, path substitutions, unequal hashes, unequal seed IDs,
unsupported entropy modes, and reused artifacts whose identity changed. Add
positive and negative tests for equal manifests, changed seed, changed DTB,
changed kernel, missing field, malformed JSON, and stale source identity.

### Phase 2: close entropy determinism

Use a fresh directory under `/data/disk/tmp/mips32-soc`, for example:

```text
/data/disk/tmp/mips32-soc/plan-v12-deterministic-differential-20260921
```

Run this matrix with one kernel/image and declared bounds:

| Case | Expected result |
| --- | --- |
| QEMU seed A, run 1 vs run 2 | exact equal entropy-dependent records |
| RTL seed A, run 1 vs run 2 | exact equal entropy-dependent records |
| QEMU seed A vs RTL seed A | equal contract metadata; comparison proceeds |
| QEMU seed A vs QEMU seed B | an intended entropy-dependent value differs |
| RTL seed A vs RTL seed B | an intended entropy-dependent value differs |
| missing seed in deterministic mode | explicit failure, never silent pass |
| malformed seed | explicit failure, never silent pass |
| default mode without `rngdet=1` | existing default behavior retained |

Do not tune CP0 timing, `WAIT`, `lpj`, interrupt timing, or comparison
tolerance to force entropy values to match. The seed is the only intentional
deterministic input.

### Phase 3: make trace validity fail closed

Validate before architectural comparison:

- JSON syntax and required fields on every record;
- strictly increasing retire sequence numbers, with no duplicates;
- valid PC/instruction widths and delay-slot metadata;
- complete child status and terminal marker;
- record and byte bounds;
- no timeout or signal termination presented as a pass;
- equal manifest identity for QEMU and RTL;
- exact lengths, or an explicitly declared prefix, for bounded comparison.

Publish `INVALID_INPUTS` separately from `MISMATCH`. Add fixtures for
truncation, reorder, duplicate sequence, mutated selected GPR, changed
manifest, missing terminal marker, and timeout exit.

### Phase 4: rerun and classify the first real mismatch

With one valid manifest, rerun the seeded workload around the former
divergence:

```text
0x88cecc4c: jal get_random_u32
0x88cecc58: sw v0,960(a0)
0x8886cebc: lw v0,-5476(s3)
```

Capture retire sequence, PC, instruction, delay-slot metadata, source GPRs,
forwarding selections, EX/MEM address and store operand, `mem_val_rt`,
alignment, byte enables, core request, L1 request/acceptance/array write,
exceptions, replay, flush, reset, and stall state.

Classify only the first wrong boundary:

| Boundary | Required action |
| --- | --- |
| Entropy or artifact identity | repair manifest/contract; do not change RTL |
| committed GPR/writeback | CPU retirement/state fix and dependency test |
| forwarding or load-use value | hazard lifetime fix and store-data test |
| EX/MEM or replay state | pipeline flush/stall fix and delay-slot/reset test |
| aligned data/byte enable | store alignment fix and SB/SH/SW tests |
| core request/backpressure | valid-hold/acceptance fix and AXI stress |
| cache array/tag merge | cache ownership fix and exact-line test |
| unobservable | add an observation point and report `OWNER_UNOBSERVED` |

The downstream target load, cache word, or DDR response is not an owner unless
the immediately preceding architectural inputs are proven equal.

### Phase 5: apply and verify one owner-scoped fix

Only if Phase 4 identifies an RTL owner:

1. add a minimal directed reproducer at the first wrong instruction;
2. make one scoped RTL change in the owning pipeline/cache contract;
3. add a negative, reset-in-flight, backpressure, or exception test;
4. run frontend compile and affected CPU/cache/AXI gates;
5. rerun the exact same seeded manifest;
6. run the unchanged default blocking configuration for regression.

Do not fix this failure by hard-coding a random result or changing timer, MMU,
cache mode, interrupt, AXI-ID, Linux command-line, or comparator semantics.

### Phase 6: bounded closure report

Run the applicable existing gates and record unavailable tools as residual
risk rather than silently skipping them:

```text
make rtl-frontend-compile
make focus-differential-checker-test
make peripheral-differential-checker-test
make linux-timer-clock-comparison-test
make cpu-badvaddr-owner-gate
make cpu-irq-delay-slot-gate
make rtl-linux-root-cause-checkpoint-gate
make rtl-linux-generic-init-gate
make rtl-linux-focus-differential-gate
```

The final report must include the manifest and validation result, entropy
matrix, repeatability hashes, checker negative tests, first mismatch and owner,
affected logs, exact bounds, residual scope, and unrun checks.

## 5. Tracking checklist

- [ ] v12 run directory created outside the repository build tree
- [ ] canonical JSON manifest implemented and validated
- [ ] same-seed QEMU repeatability passed
- [ ] same-seed RTL repeatability passed
- [ ] different-seed negative test passed
- [ ] missing/malformed entropy input rejected
- [ ] trace truncation/reorder/sequence tests passed
- [ ] valid post-contract QEMU/RTL comparison completed
- [ ] first wrong architectural owner classified
- [ ] owner-scoped RTL fix, if required, completed
- [ ] default blocking regression passed
- [ ] completion report and residual risks published

## 6. Explicit residual scope

Even after this plan passes, full MIPS32 privileged ISA and FPU, unrestricted
Linux demand paging and shootdown stress, complete generic userspace
semantics, unbounded QEMU/RTL system equivalence, physical DDR/QSPI PHY and
device timing, formal/CDC/RDC, synthesis/STA/DFT, board validation, and
production Linux/U-Boot release signoff remain separate work unless evidenced.
