# Architecture Closure Execution Tracking

### 2026-08-31 R-type trap code field and Linux BUG_ON boundary

- The Linux progress trace identified `0x00040336` at `0x880e89a4` as the
  legal `TNE $zero,$a0,0xc` form used by `__BUG_ON`, not a coprocessor
  instruction. The RTL decoder had incorrectly required `rd` and `sa` to be
  zero, turning the instruction into RI (`ExcCode=10`).
- Removed that false fixed-field check for all six R-type conditional traps;
  `rd:sa` is the architecturally ignored ten-bit trap code.
- `make rtl-frontend-compile qemu-system-trap-differential-gate
  qemu-system-trap-imm-differential-gate` passes from a fresh temporary build.
  The R-type differential firmware now explicitly encodes `TNE` with code
  `0xc`.
- A fresh 2M-cycle no-coverage RTL Linux probe passes its bounded progress
  gate and reaches normal kernel addresses after the fix; the former
  `RI@__BUG_ON` is absent. Userspace boot and full RTL/QEMU Linux differential
  remain open.

### 2026-08-31 FPU bit-preserving sign and move operations

- `MOV.S/D`, `ABS.S/D` and `NEG.S/D` preserve IEEE bit patterns, including
  NaN payloads and signed zero, through explicit result overrides.
- The primitive gate checks single and double negative-zero and NaN payload
  behavior. Complete IEEE-754 arithmetic flags/traps and OS FPU ABI remain
  open.
- Real `fpu_single` and `fpu_double` CPU/SoC firmware now checks the same
  boundary, including `ABS/NEG` sign changes and no Invalid sticky update for
  non-arithmetic NaN operations.
- Fresh single- and double-precision QEMU system-mode retire differential
  gates both pass. This closes the selected system slice only; complete
  IEEE-754 arithmetic and the FPU OS ABI remain open.

### 2026-08-31 fixed FPU rounding tie semantics

- `ROUND.W.S` and `ROUND.W.D` now use MIPS round-to-nearest ties-away-from-zero;
  `CVT.W.*` RM=00 remains nearest-even and other FCSR modes remain unchanged.
- Primitive and SoC firmware tests add positive `2.5 -> 3` and negative
  `-1.5 -> -2` checks. This closes the tested fixed-rounding tie boundary only;
  complete IEEE-754 edge cases and OS FPU ABI remain open.

### 2026-08-31 LL/SC physical reservation and SC-consumption repair

- Reservation matching/storage now uses translated physical `data_addr`,
  while CP0 LLAddr and retire tracing preserve the virtual diagnostic address.
- Every completed SC attempt consumes the reservation, including mismatched or
  otherwise failed SC; the firmware gate checks that a second SC cannot inherit
  the first LL after a failed attempt.
- Full memory ordering, arbitrary SMP atomicity and MESI/directory behavior
  remain outside this bounded contract.

### 2026-08-30 hardware walker seven-page-size matrix

- Extended the opt-in page-table walker to support the remaining contract
  PageMask values: 1 MiB (`0x00ff`), 4 MiB (`0x03ff`) and 16 MiB (`0x0fff`).
  The implementation now reduces L2 index width, validates leaf alignment,
  preserves the larger page offset in PA formation, and carries the matching
  even/odd selector into the CPU hardware-refill TLB write path.
- Fresh `VCS_JOBS=1 EDA_MEMORY_MAX=1500M EDA_SWAP_MAX=512M BUILD_DIR=/tmp/mips32-walker-pages-3 make page-table-walker-page-sizes-gate`
  passed all seven configurations: 4K, 16K, 64K, 256K, 1M, 4M and 16M.
- This closes the bounded hardware-walker page-size matrix only. The walker
  remains two-level, single-outstanding and opt-in; unrestricted demand
  paging, OS page-table ownership, Linux VM and full privileged/MMU closure
  remain open.

### 2026-08-30 L1 nonblocking real CPU/D-cache path closure

- Confirmed `mips_core` selects `l1_cache_nb_cpu_axi` under the opt-in
  `SOC_L1_NONBLOCKING_ENABLE`/`SOC_CPU_NONBLOCKING_ENABLE` configuration; the
  adapter is connected to the real CPU data request and SoC AXI fabric, while
  the default blocking dcache path remains unchanged.
- Fresh `VCS_JOBS=1 EDA_MEMORY_MAX=1500M EDA_SWAP_MAX=512M BUILD_DIR=/tmp/mips32-l1-complete`
  `make l1-nonblocking-cpu-complete-gate` passed compatibility, multi-request,
  three-seed reset stress, single/two-response AXI errors, reset-in-flight and
  maintenance CPU gates. Firmware reached `REGRESSION_TEST_SUCCESS` for every
  requested seed.
- Corrected the opt-in wrapper's diagnostic FSM aliases from 4 bits to the
  full 5-bit legacy dcache state width. A fresh no-coverage RTL frontend matrix
  passed all 8 configurations, including `cpu_nonblocking`.
- This closes the real CPU/D-cache opt-in integration contract. Default
  blocking behavior, full L1/L2 ordering/coherency, SMP cache protocol and
  product default-path migration remain separate open items.

### 2026-08-30 L1 nonblocking DDR system differential

- Added `FW_DIR=$(BUILD_DIR)/firmware/qemu_system_l1_ddr` to the Make target so
  an external build root isolates firmware as well as RTL/QEMU logs.
- Fresh bounded run with `BUILD_DIR=/tmp/mips32-l1-ddr-isolated`, VCS memory
  limits and the opt-in `SOC_L1_NONBLOCKING_DDR_ENABLE=1` configuration passed
  the real RTL/QEMU `mips32-soc-ref` retire differential with
  `TRACE_COMPARE_PASS records=22`. Both sides reached the firmware mailbox
  boundary.
- This closes the checked L1 nonblocking CPU-to-DDR behavioral integration
  slice. It does not close arbitrary DDR contention, full L1/L2 ordering or
  coherency, physical DDR PHY/timing, or product default-path migration.

### 2026-08-30 legal SLL decode and BREAK differential recovery

- Corrected the SPECIAL/SLL decoder to accept all architecturally legal
  `SLL rd,rt,sa` encodings when `rs=0`. The previous predicate rejected
  non-NOP shifts, which caused the BREAK exception handler's legal
  `sll k1,k1,2` to raise Reserved Instruction and loop at the exception
  vector.
- Fresh `qemu-system-break-differential-gate` passes through the BREAK
  ExcCode 9 handler, EPC+4, ERET, and mailbox retirement. Fresh
  `qemu-system-isa-r2-differential-gate` and no-coverage `rtl-frontend-compile`
  also pass all 8 frontend configurations.
- This closes the identified SLL decode defect and its system differential
  regression. It does not claim complete MIPS32 ISA or privileged ISA
  compliance.

### 2026-08-30 MEM-stage merge/load-store scoreboard closure

- Corrected the standalone MEM-stage UVM interface to match the RTL contract:
  `dmem_we` is one bit and `dmem_be` is checked as the four byte enables.
  Previously the interface widened `dmem_we` and omitted `dmem_be`, so the
  scoreboard could not prove the actual write mask.
- Added LWL/LWR/SWL/SWR and LL/SC to the randomized reference model, including
  little-endian merge formulas and suppression of requests on AdEL/AdES,
  translation faults and already-completed MEM transactions.
- Added the reproducible root target `make mem-stage-gate`; it requires a
  `SCB_PASS` result and rejects `SCB_FAIL` rather than trusting VCS's process
  exit status. A fresh isolated VCS run passed all 2,009 transactions.
- This closes the MEM-stage byte-mask and merge-reference verification gap;
  cross-page exception sequencing, Linux unaligned policy and full ISA remain
  open.

### 2026-08-30 RTL Linux MEM interruption state trace

### 2026-08-30 D-cache diagnostic state-width correction

- Matched the legacy SoC observation interface and bind to the 5-bit D-cache
  FSM state and next-state registers. The previous 4-bit observation silently
  truncated FSM states and produced VCS port-width warnings in Linux probes.
- This changes diagnostic observability only; it does not claim to fix the
  remaining RTL Linux userspace boot or full RTL/QEMU differential failure.

- Extended the bounded Linux exception trace with `wb_valid`,
  `wb_arch_valid`, MEM/EX instruction words, `oldest_flushed_pc`, delay-slot
  markers and the WB-branch-delay classification.
- The fresh `13.6M`-cycle run proves that the first problematic interrupt at
  cycle `13503087` has `wb_valid=0`, while MEM still holds
  `lw s1,44(s1)` at `0x88852ca4` and `oldest_flushed_pc=0x88852ca4`. The
  following retry eventually faults at `0xfffffffc` with `wb_valid=1`.
  Thus the remaining issue is recovery/state preservation for an interrupted
  but not-yet-retired MEM transaction; it is not evidence that the load had
  already committed or that EPC alone explains the panic.
- This diagnostic evidence does not close RTL Linux userspace boot, full
  RTL/QEMU differential, or complete ISA/MMU/OS closure.

### 2026-08-30 Linux asynchronous-interrupt EPC precision follow-up

- RTL Linux diagnostics isolated a real precision hazard at the first
  `alloc_pid` failure window: a normal `lw s1,44(s1)` at `0x88852ca4` could
  be re-entered after an asynchronous interrupt because the exception frame
  selected a stale pipeline PC. The CPU now requires valid control-transfer
  evidence for delay-slot recovery and advances EPC past an already-retiring
  ordinary WB instruction.
- Fresh `SKIP_COVERAGE=1 make rtl-frontend-compile cpu-cp0-gate
  cpu-irq-delay-slot-gate` passed, including all 8 frontend configurations.
- A fresh 16M-cycle relocated RTL Linux probe still reaches the same kernel
  `die()`/panic boundary, although the original false `Cause.BD`/EPC rollback
  is removed. The remaining failure is an independent architectural-state
  mismatch: subsequent exception handling still reaches `BadVAddr=0x2c` and
  the Linux userspace marker remains absent. RTL Linux userspace boot, full
  Linux differential, and complete ISA/MMU/OS closure therefore remain open.

### 2026-08-30 fresh Linux/QEMU build and system peripheral recheck

- Reclaimed only failed Linux kernel objects and obsolete source download
  caches after the previous kernel link stopped with `ENOSPC`; QEMU source,
  its built custom-machine binary, and Linux/U-Boot source trees were kept.
- `make linux-boot-build-gate` now passes, rebuilding the Linux v6.6 image and
  the QEMU 9.2.0 `mipsel-softmmu` `mips32-soc-ref` machine.
- Fresh QEMU peripheral, QSPI, DDR, and unified current-contract gates pass.
  This is behavioral custom-machine evidence; physical DDR/QSPI timing,
  RTL Linux userspace boot, and full RTL/QEMU system differential remain open.

### 2026-08-30 Linux userspace host-budget stabilization

- A fresh run completed all Linux VM, protection, timer, fork/exec and
  exact-PID wait markers but exceeded the old 60-second host budget under
  concurrent host load. A direct 120-second run completed the same marker set.
- Increased the generic Linux gate's default QEMU host budget to 120 seconds;
  all marker assertions remain unchanged. This addresses host scheduling
  variance only. Follow-up plain and `-icount` A/B runs still stopped at
  different post-SIGSEGV/fork-wait boundaries, so this remains a diagnostic
  stabilization and does not close generic Linux reproducibility, RTL Linux
  boot or full system differential.
- The runner now stops QEMU after the final fork/wait marker and retains the
  full marker assertions, avoiding the expected post-test `init` panic and
  reducing host resource consumption on successful runs.
- After clearing the accumulated historical `/tmp` outputs, a fresh
  `JOBS=2 QEMU_TIMEOUT=120s make linux-boot-build-gate` passed through the
  bounded shutdown path. The earlier resource-loaded A/B failures remain
  useful residual evidence, so this closes the runner execution boundary but
  not full Linux/RTL differential or OS VM signoff.

### 2026-08-29 stale delay-slot metadata guard

- Fixed `rtl/cpu/mips_cpu.v` so asynchronous interrupt BD/EPC inference requires
  both the stage delay-slot marker and its nonzero paired resume-target
  metadata. A stale `id_bd` left on a post-flush bubble can no longer classify
  an ordinary instruction as a branch delay slot.
- The diagnosed Linux window at cycle `23479196` had been taking EPC
  `0x8923af20` for `lbu v1,0(v1)` after the producer at `0x8923af1c` was
  discarded. The guard removes that false BD path while retaining the
  contiguous MEM->EX->ID legal delay-slot recovery logic.
- Fresh `SKIP_COVERAGE=1 BUILD_DIR=/tmp/mips32-delay-metadata-fix make
  cpu-irq-delay-slot-gate cpu-cp0-gate rtl-frontend-compile` passed. The
  frontend matrix passed all 8 configurations. This is a targeted CPU
  recovery fix; RTL Linux userspace boot and full RTL/QEMU Linux differential
  remain open until a fresh long Linux run proves them.
- A fresh no-coverage 20M-cycle probe under
  `/tmp/rtl_linux_after_delay_metadata_fix` reached the dynamic Linux TLB
  boundary and continued through approximately 17.4M cycles before the
  runner timeout, with no userspace marker. It is useful progress evidence but
  not a Linux boot pass; the full Linux items remain open.

### 2026-08-29 current-contract external build-root isolation

- Fixed the current-contract signoff wrapper and Phase 2/3 completion wrappers
  so an external `RUN_ROOT` is accepted only with the explicit
  `ALLOW_EXTERNAL_RUN_ROOT=1` opt-in. The default remains constrained to the
  repository `build` tree.
- Updated the Makefile current-contract entry and its IRQ delay-slot
  prerequisite to propagate `BUILD_DIR`, eliminating the remaining fixed
  `build/` write from this long-running path.
- A fresh isolated run under
  `/tmp/mips32-current-contract-post-cache-fix2` completed all functional
  prerequisites, Phase 2/3 completion, and 10/10 stress seeds. The run then
  correctly failed the existing 99% coverage policy at UVM 36.24% and Product
  36.97%; no coverage threshold was relaxed. Repository build output was not
  used by the corrected run.

### 2026-08-29 RTL Linux TLB refill recheck: lookup path cleared

- Added bounded exception diagnostics for the main TLB slot, its ASID, and the
  D-side lookup VA/hit vector. A fresh 20M-cycle no-coverage run is recorded
  under `/tmp/mips32-rtl-linux-tlb-asid`.
- At the post-refill `c0000220` trace point, TLB[41] is still
  `valid=1/VPN2=0x00060000/PageMask=0/EntryLo0=0x00211f5f`, the active and
  stored ASIDs are both `0x00`, the lookup VA is `0xc0000220`, and
  `lookup1_hit_vec[41]=1`. The D-side fields are `dmem_translate_req=0` and
  `mmu_d_ok=1`; the displayed `Cause.ExcCode=3` is the pre-edge value while a
  separate timer interrupt is being accepted, not a second TLB fault.
- This rules out TLB slot eviction, ASID mismatch, and the main lookup compare
  as the cause of that observed boundary. No TLB or MMU semantic change is
  justified by this probe; the remaining RTL Linux userspace failure stays in
  the interrupt/kernel control-flow path and requires a separate diagnosis.

### 2026-08-29 relocated Linux 2M-cycle RTL/QEMU differential expansion

- Rebuilt the RTL Linux image from the relocated kernel with
  `KERNEL_LOAD_VIRTUAL=0x88800000` and the fixed DTB handoff
  `DTB_LOAD_VIRTUAL=0x89f00000` after the DTB-address correction.
- Fresh isolated evidence:
  `BUILD_DIR=/tmp/mips32-qemu-dtb-fix-2m KERNEL=... DTB=...
  RTL_CYCLE_LIMIT=2000000 QEMU_TIMEOUT=10s HOST_TIMEOUT=240s
  SKIP_COVERAGE=1 make qemu-system-linux-differential-gate` passes.
  The exact run reports `TRACE_COMPARE_PASS` and compares the complete QEMU
  capture as a golden prefix after the explicit PC/instruction handoff anchor.
- This expands the checked relocated-kernel prefix beyond the earlier 100k
  probe without changing comparator semantics. It still does not prove RTL
  Linux userspace boot, a full-length Linux differential, unrestricted demand
  paging, complete privileged/ISA/FPU compliance, or product signoff.

### 2026-08-29 QEMU/RTL Linux DTB handoff alignment

- The custom QEMU machine previously placed `-dtb` at the top of its generic
  RAM allocation (`0x87ff0000` for the 128 MiB profile), while the RTL Linux
  image builder passes the fixed prototype DDR handoff VA `0x89f00000`.
  This changed register `a1` before the first kernel save and was the first
  long differential mismatch (`0x89f00000` versus `0x87ff0000`).
- `scripts/qemu/mips32_soc_ref.c` now places Linux DTBs at physical
  `0x09f00000`, yielding kseg0 VA `0x89f00000`; the UHI firmware gate checks
  the exact address as well as the FDT magic. `make qemu-system-uhi-dtb-gate`
  passes with the rebuilt custom machine.
- This closes the QEMU/RTL Linux boot-argument address precondition. The
  relocated Linux RTL build and full system-mode differential remain open;
  no comparator relaxation or TLB behavior change is claimed.

### 2026-08-29 bounded RTL/QEMU Linux retire differential

- Added `tb/isa_ref/run_qemu_linux_differential_gate.sh` and the Make entry
  `qemu-system-linux-differential-gate`. The gate runs the real RTL Linux
  progress path and QEMU `mips32-soc-ref` with the same relocated kernel and
  DTB, then compares retire records after an explicit Boot ROM-to-kernel
  handoff anchor.
- The comparator now supports an explicit exact PC+instruction handoff and a
  reviewed golden-prefix mode. It still compares every record in the QEMU
  capture and all architectural fields covered by the existing comparator;
  the prefix mode is opt-in and does not alter default strict comparisons.
- Fresh evidence: `SKIP_COVERAGE=1 BUILD_DIR=build KERNEL=... DTB=...
  RTL_CYCLE_LIMIT=100000 QEMU_TIMEOUT=2s make
  qemu-system-linux-differential-gate` passes with 70,764 QEMU retire records
  matching the RTL prefix after the handoff; the RTL capture contains 119,395
  records including its pre-handoff ROM prefix.
- This closes only a bounded Linux kernel retire-prefix differential. Linux
  userspace boot, full-length Linux differential, complete ISA/privileged/MMU
  semantics, and product signoff remain open.

### 2026-08-29 RTL Linux dynamic TLB fault boundary

- A fresh 20M-cycle no-coverage probe with the relocated kernel reaches Linux's
  first dynamic store TLB miss at cycle `16296236`: `0x8890cd90: sw v0,32(s1)`
  accesses `0xc0000000` and reports `ExcCode=3`.
- Linux's generated refill handler then performs `TLBWR` with the expected
  `VPN2=0x00060000` and a valid `EntryLo0` before the retry. The RTL continues
  to execute and reaches later kernel code, so this event is not evidence of a
  TLB write hazard or a stuck walker.
- The probe still observes zero userspace success markers. The remaining
  blocker is unrestricted Linux VM/page-table and runtime progress behavior,
  not a justified local TLB semantic change; full RTL Linux userspace boot and
  full Linux differential remain open.

### 2026-08-29 opt-in L1 SYNC drain contract

- Added private internal maintenance encoding `0x1e` for architectural
  `SYNC`. The opt-in L1 accepts it only when MSHRs, response FIFO, writeback
  queue, and line-port activity are drained; it has no tag/data side effects.
- Added `l1-nonblocking-sync-gate`, which holds an outstanding refill, checks
  that SYNC cannot complete early, then checks completion after the refill
  response drains. The decoder gate and isolated `rtl-frontend-compile` also
  pass. Default blocking dcache behavior remains unchanged.
- Corrected the existing CACHE `0x1d` test contract as writeback-only, keeping
  the resident line valid after completion. Full OS cache ABI, multicore
  ordering, and complete MIPS memory-model compliance remain open.

### 2026-08-29 QEMU synchronous-exception retire conversion

- Fixed `tb/isa_ref/qemu_system_state_to_jsonl.py` so a retire event that
  enters a synchronous exception vector cannot report a GPR write from a
  transient post-state register delta. The converter now prioritizes the
  exception boundary and emits no architectural GPR commit for the faulting
  instruction.
- Fresh `python3 -m py_compile` and
  `BUILD_DIR=/tmp/mips32-qemu-converter-fix make
  qemu-system-exception-differential-gate` passed. The existing syscall/ERET
  corpus remains green; this change improves exception capture semantics.

### 2026-08-29 QEMU integer signed-overflow retire differential

- Extended `qemu_system_exception` with real `ADD`, `SUB`, and `ADDI` signed
  overflow instructions and an `ADDIU` wrap boundary. The handler checks
  `Cause.ExcCode=12` and returns over each faulting instruction; each target
  register remains at its sentinel value, while `ADDIU` commits `0x80000000`.
- Added a corpus-specific post-comparison assertion requiring all three
  overflow opcodes, no faulting GPR commit in both traces, exactly one syscall,
  and the non-trapping `ADDIU` result. A fresh isolated RTL/QEMU run passed.
- The RTL trace bind now suppresses `retire_gpr_we` on an exception record, so
  the observation contract agrees with the architectural no-commit rule rather
  than relying only on comparator field filtering. Trace-size and record-count
  bounds also fail a stuck guest before it can exhaust host storage.
- This closes selected signed integer-overflow differential evidence only; it
  does not claim complete MIPS32/privileged ISA compliance or arbitrary
  exception-priority coverage.

### 2026-08-29 Integer signed-overflow exception path

- Routed the existing signed `ADD/SUB/ADDI` ALU overflow indication through
  the EX/MEM exception bundle in `rtl/cpu/mips_cpu.v`, preserving an upstream
  exception code and assigning architectural `ExcCode=12` for overflow.
- Added a real `soc_smoke` CPU test that executes signed `ADD`, `SUB`, and
  `ADDI` overflow cases and requires CP0 to observe one exception for each;
  the neighboring wrapping `ADDIU` case must not increment the count. Fresh
  `soc-smoke`, `rtl-frontend-compile`, `cpu-cp0-gate`, and `isa-r2-gate` runs
  passed after the change.
- This closes the selected signed integer overflow path only; it does not
  claim complete MIPS32 ISA/privileged-ISA compliance or complete exception
  priority/precision coverage.

### 2026-08-29 FPU SQRT Inexact classification

- Extended `rtl/cpu/mips_fpu.v` to classify non-perfect finite positive
  `SQRT.S`/`SQRT.D` results as Inexact by comparing the rounded result back to
  the source operand. Exact roots remain clear, and the previously fixed
  negative-zero/Invalid boundary is preserved.
- Added direct checks for `sqrt(2.0f)` and `sqrt(2.0d)` to
  `tb/unit/cpu_test/tb_mips_fpu_flags.sv`. The primitive flags gate passed;
  fresh real CPU/SoC `fpu-single-gate` and `fpu-double-gate` also passed.
- This closes only the SQRT Inexact slice. Full IEEE-754 tininess/rounding,
  precise FPE policy, Linux FPU ABI and complete ISA compliance remain open.

### 2026-08-29 SVA checker execution refresh

- Fresh isolated run `BUILD_DIR=/tmp/mips32-sva-closure SKIP_COVERAGE=1 make
  sva-gate` passed all three SVA scenarios: SoC bind, reset synchronizer and
  AXI SRAM protocol test.
- The SoC compile included the bound cache FSM, TLB lookup, page-table walker,
  L1 resource/maintenance and VIC checkers, in addition to AXI/APB/reset
  properties. No assertion or regression failure was reported.
- This confirms simulation assertion execution and failure propagation. It is
  not a formal proof and does not close CDC/RDC/lint, coverage percentage,
  Linux, complete ISA/FPU or product physical signoff.

### 2026-08-29 FPU SQRT negative-zero boundary

- Corrected `rtl/cpu/mips_fpu.v`: `SQRT.S(-0)` and `SQRT.D(-0)` now preserve
  the negative-zero bit pattern and do not raise Invalid; negative non-zero
  operands retain the Invalid behavior.
- Added direct primitive checks to `tb/unit/cpu_test/tb_mips_fpu_flags.sv`.
  Fresh `mips-fpu-flags-gate` passed, followed by real CPU/SoC
  `fpu-single-gate` and `fpu-double-gate` passes.
- This closes the negative-zero SQRT boundary only. Complete IEEE-754 edge
  behavior, precise FPE policy, Linux FPU ABI and full ISA compliance remain
  open.

### 2026-08-29 verification-foundation tool availability refresh

- Fresh `scripts/run_verification_foundation_gate.sh` evidence was generated
  under `/tmp/mips32-verification-foundation`.
- VCS is available at `/data/disk/vcs/X-2025.06/bin/vcs`; Verilator, Yosys,
  SymbiYosys, Verilator coverage, SpyGlass, Questa CDC, VC Static and
  JasperGold are unavailable in the current environment.
- The SVA/formal asset presence and two waiver-file broad-exclusion audits
  pass. The report correctly remains `FOUNDATION_READY_WITH_EXPLICIT_TOOL_STATUS`
  and explicitly does not claim formal, CDC/RDC, lint or coverage signoff.

### 2026-08-29 CPU/MMU aggregate recursive-build isolation

- `tb/soc_test/run_cpu_mmu_complete.sh` now propagates the caller's
  `BUILD_DIR` into every recursive `make` invocation. Previously an isolated
  P1 aggregate could pass `BUILD_DIR` to the outer target while child gates
  silently defaulted back to the repository `build/` directory.
- Fresh `BUILD_DIR=/tmp/mips32-cpu-mmu-isolated` verification completed
  `make cpu-mmu-complete`; all 25 CPU/MMU child gates passed and the report was
  written below the temporary root. Firmware and simulation artifacts were
  likewise confined to that root.
- This closes recursive artifact isolation for the CPU/MMU aggregate. It does
  not change the documented open scope of full Linux/OS semantics, complete
  ISA/FPU compliance, or production backend signoff.

### 2026-08-29 MMU refill isolated firmware output closure

- Separated the MMU refill runner's firmware source directory from its output
  directory. `run_mmu_refill.sh` now accepts `FW_SOURCE_DIR` and `FW_DIR`,
  defaults output below `RUN_DIR/firmware`, and never runs `clean all` against
  the source tree's generated artifacts.
- The `mmu-refill-gate` and hardware-walker SoC target now pass build-root
  specific firmware directories. A fresh hardware-walker run passed, and a
  before/after SHA256 check confirmed the pre-existing source-tree firmware
  was unchanged. This closes isolated artifact handling for this runner only;
  it does not close Linux VM ownership or full MMU/OS semantics.

### 2026-08-29 P1 isolated-build firmware path closure

- The `dual-core-soc-gate` Make target now passes `FW_DIR=$(BUILD_DIR)/firmware/dual_core_ipi`
  to its runner. Previously, an isolated `BUILD_DIR` still caused the runner's
  default firmware path to fall back to the repository `build/` directory,
  contaminating aggregate runs with out-of-tree artifacts.
- Fresh `BUILD_DIR` verification completed `make dual-core-soc-gate` with the
  firmware and run artifacts entirely below the temporary build root and
  reported `dual-core SoC gate: PASS`. This closes aggregate artifact
  reproducibility for this child gate only; it does not expand the dual-core
  coherency or Linux/MMU contract.

### 2026-08-29 RTL Linux load-address forwarding probe

- Extended the opt-in Linux delay trace with `id_val_rs`, `ex_val_rs`,
  `ex_out`, `ex_reg_write`, `ex_waddr` and `id_inst`. This observes the
  producer/consumer forwarding boundary without changing CPU timing or the
  default trace volume.
- The relocated kernel maps the failing runtime PC `0x8923af20` to
  `lbu v1,0(v1)`, preceded by `addu v1,t0,a1`; the historical bad address
  `0x0000006c` is therefore consistent with a stale `v1` value. A new
  20M-cycle probe remained resource-bounded but timed out at the host limit
  before reaching that window, so no RTL forwarding change is claimed yet.
- `make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_linux_trace_fix`
  passes all `8/8` configurations. The next diagnosis uses the bounded
  trace window around the exact producer/consumer pair.

### 2026-08-29 RTL Linux isolated image DTC resolution

- Fixed `build_rtl_linux_image.sh` to resolve DTC next to the supplied
  `vmlinux`, with an explicit override and actionable failure when no
  executable DTC exists. `run_rtl_linux_progress_gate.sh` now passes the
  matching DTC for both freshly built and reused kernels.
- Before this fix, an isolated `RUN_DIR` could build the kernel successfully
  and then fail silently during image construction because the script looked
  only under the unrelated repository `build/linux_boot/real` directory.
- Fresh verification with a newly built relocated kernel completed image
  generation and a 1000-cycle RTL probe: progress gate PASS, simulator data
  structure 1.1 MiB, userspace marker count 0. This closes the reproducibility
  issue only; RTL Linux userspace boot and RTL/QEMU Linux differential remain
  open.

### 2026-08-29 Linux interrupt delay-slot EPC fix

- Fixed the asynchronous interrupt PC selection in `rtl/cpu/mips_cpu.v`.
  When WB retires a branch delay-slot instruction on the same edge that a
  younger MEM instruction is visible, the precise interrupt PC is the WB
  delay-slot PC. The old selection used the younger MEM PC, and CP0's normal
  BD adjustment then saved an address inside the wrong function epilogue.
- Fresh `make cpu-irq-delay-slot-gate`, `make cpu-cp0-gate`, and
  `make cpu-load-return-gate` all pass. A no-coverage RTL Linux run through
  19,000,000 cycles no longer jumps to `0x895b0000`; it reaches the legal
  `__udelay` loop at `0x89243530`/`0x89243534` with bounded simulator memory.
- The Linux userspace marker is still absent. The remaining RTL Linux issue
  has moved past the corrupted `alloc_inode` return and now requires a timer
  / `__udelay` progress diagnosis; full RTL Linux userspace boot and full
  RTL/QEMU Linux differential remain open.

### 2026-08-29 RTL Linux stack-return diagnosis and bounded IRQ recheck

- Added `ex_inst/ex_val_rt` and `mem_inst/mem_val_rt` fields to the bounded
  `LINUX_DELAY_TRACE`, so a Linux stack fault can be compared at EX/MEM,
  MEM/WB, and the external D-cache request boundary.
- A fresh no-coverage capture reproduced the failure at the `alloc_inode`
  return path. The load `lw ra,28(sp)` reads `0x895b0000` from physical
  `0x08423d64`, and the subsequent `jr ra` transfers to `0x895b0000`; the
  trace does not show the expected `alloc_inode` prologue store in the
  captured window. The earlier `0x895b0000` store is a valid caller register
  save, so the previous conclusion that `sw ra` directly wrote a bad value
  was rejected.
- The same capture shows a prior asynchronous interrupt at a Linux kernel
  control-flow boundary. The dedicated `make cpu-irq-delay-slot-gate` passes,
  including the unit-level `Cause.BD`/EPC contract, but this does not yet
  prove the full Linux pipeline/interruption interaction. No speculative RTL
  cache or pipeline change was made from the incomplete evidence.
- RTL Linux userspace boot still has no `MIPS32_SOC_LINUX_BOOT_SUCCESS` marker;
  full RTL Linux userspace boot and full RTL/QEMU Linux differential remain
  open. The next diagnosis must capture the call-entry window and the exact
  interrupt/return transaction before changing architectural state handling.

### 2026-08-27 SPECIAL3 regression fixture correction

- `tb/unit/cpu_test/tb_mips_control_special3.sv` had retained the obsolete
  non-standard `RDHWR` encoding with `rs=3`, and its reserved-field sweep did
  not include the legal MIPS32 R2 `WSBW` sub-operation (`sa=6`).
- Corrected the fixture to use architectural `RDHWR rs=0, rd=2` and added the
  legal `WSBW` check. The RTL decoder was not loosened.
- Fresh evidence: `make mips-control-special3-gate cp0-rdhwr-gate
  isa-r2-gate` passes. Complete ISA and privileged-ISA compliance remain
  outside this selected corpus.

### 2026-08-27 Linux progress gate uses independent heartbeat

- The progress gate now checks `LINUX_PROGRESS_TRACE`, while detailed refill
  diagnostics remain independently controllable through
  `LINUX_REFILL_TRACE` and the other trace plusargs.
- Fresh end-to-end no-coverage run with detailed traces disabled passed at
  `RTL_CYCLE_LIMIT=1000000`; the generated report records zero Linux userspace
  markers, while the simulator completed normally with a 1.1 MiB VCS data
  structure.
- This closes the progress-gate observability defect only. RTL Linux
  userspace boot and full RTL/QEMU Linux differential remain open.

### 2026-08-27 Linux progress evidence decoupled from detailed traces

- Added a bounded `LINUX_PROGRESS_TRACE` heartbeat to the Linux RTL
  testbench and made the progress gate check it instead of requiring the
  verbose `LINUX_REFILL_TRACE` stream.
- The gate forwards the new control independently. Detailed refill,
  exception, EBase and WB traces can now be disabled without invalidating the
  post-reset progress criterion or changing RTL behavior.
- Fresh VCS compile/elaboration/link passed with coverage disabled. A 1000
  cycle run with all detailed traces disabled emitted only the independent
  progress heartbeat and completed at the explicit cycle limit with a 1.1 MiB
  VCS data structure. This improves probe resource control; RTL Linux
  userspace boot and full RTL/QEMU Linux differential remain open.

### 2026-08-27 Linux RTL probe trace gating and long-run evidence

- Added explicit `LINUX_REFILL_TRACE`, `LINUX_EXCEPTION_TRACE` and
  `LINUX_EBASE_TRACE` controls to `TB_LINUX_BOOT_TRACE`; all three remain
  enabled by default for the progress gate and can be disabled for resource
  controlled probes.
- Previously passing `+LINUX_REFILL_TRACE=0` did not suppress the sparse
  heartbeat, so a purported low-log run still emitted periodic refill lines.
  The testbench and `run_rtl_linux_progress_gate.sh` now forward and honor the
  controls independently.
- Recompiled the MMU-enabled Linux RTL testbench with coverage disabled and
  ran a fresh 10M-cycle probe. It ended at the explicit cycle limit with a
  1.1 MiB VCS data structure, no RTL regression/error/watchdog failure, and
  no userspace success marker. The remaining Linux RTL boot closure is still
  open; this change only fixes probe observability and resource behavior.

### 2026-08-27 Linux refill probe resource safety and runtime TLBWR evidence

- `tb/linux_boot/run_rtl_linux_progress_gate.sh` now forwards the bounded
  `LINUX_TLB_TRACE`, `LINUX_VECTOR_TRACE` and corresponding line limits to the
  simulator. This keeps runtime-vector diagnosis reproducible without enabling
  unbounded trace streams or changing the default Linux probe behavior.
- A 20M-cycle no-coverage run completed with a 1.1 MiB VCS data structure and
  no simulator error or OOM. The run reproduced the first real D-side `TLBS`
  at cycle `16265490` for `VA=0xc0000000`.
- A bounded 17M-cycle trace then observed the Linux-generated refill handler
  execute `TLBWR` at cycle `16265617`, writing `VPN2=0x60000` and a valid
  `EntryLo0`, followed by normal timer-handler progress. The vector was
  therefore written and executed; the remaining failure is deeper Linux boot
  progress, not missing runtime-vector installation.
- The progress gate still reports zero userspace success markers. Full RTL
  Linux userspace boot, OS-owned VM/shootdown semantics and RTL/QEMU Linux
  differential remain open.

### 2026-08-27 QEMU retire converter vector false-positive fix

- The `fpu_fpe_double` differential mismatch at retire 94 was traced to
  `qemu_system_state_to_jsonl.py`, not to QEMU's CP0 EPC state. A normal
  firmware branch-delay slot targeting the vector-shaped address `0x200` was
  incorrectly treated as an asynchronous interrupt boundary. Its stale
  Cause.BD data-flow override changed a later `0x0000003c` Cause value into
  `0x8000003c`.
- The converter now rejects a vector-shaped `next_pc` when the preceding
  instruction is an ordinary branch whose architectural target is that same
  address. Existing QEMU kseg0 vector PC behavior remains unchanged, including
  the VIC contract's explicit `0x80000180` checks.
- Fresh evidence: `make qemu-system-selected-differential-gate` and
  `make qemu-system-architecture-closure-gate` both pass. The latter includes
  current-contract, selected ISA/exception/privileged/peripheral/VIC/FPU/DMA
  differential, MMU refill/PageMask/OS-pressure differential, FPE boundary and
  double differential, LL/SC differential, and the Linux userspace marker
  gate. Full RTL Linux userspace boot and complete ISA/privileged/FPU/product
  signoff remain open.

### 2026-08-27 Linux vector cache-maintenance boundary diagnosis

- Added bounded `LINUX_CACHEOP_TRACE_LINE` and `LINUX_CP0_TRACE_LIMIT`
  controls to the RTL Linux trace path, and exposed them through
  `run_rtl_linux_progress_gate.sh`. The target line is selected by physical
  cache-line address, so early whole-cache operations cannot exhaust the
  diagnostic budget.
- A fresh 8M-cycle VCS capture observed Linux issuing `op=15`
  (`Hit_Writeback_Invalidate_D`) for physical line `0x08e08200`. The D-cache
  drove `AW=0x08e08200` and all eight `W` beats, and the backing DDR model
  retained the generated vector word `0x0a0008e8`. The following `op=10`
  invalidated the I-cache line and refill returned that word.
- The same capture showed CP0 Compare writes and `Cause.TI` clearing after
  each timer interrupt. A no-trace 16M-cycle run completed without simulator
  error or OOM, entered deeper kernel code, but did not emit
  `MIPS32_SOC_LINUX_BOOT_SUCCESS`. Therefore the current Linux blocker is not
  proven to be D-cache writeback or Compare/TI clearing; RTL Linux userspace
  boot and RTL/QEMU Linux differential remain open.

### 2026-08-27 asynchronous interrupt branch-delay EPC correction

- `rtl/cpu/mips_cpu.v` now selects the interrupted PC from the oldest valid
  in-flight pipeline stage and derives interrupt `Cause.BD` from all flushed
  MEM/EX/ID delay-slot markers. This preserves the MIPS rule for an IRQ
  accepted before WB: a delay-slot interruption records the branch PC in EPC
  and resumes by re-executing the branch after ERET.
- `make rtl-frontend-compile`, `make soc-smoke`, and `make cpu-cp0-gate` pass
  after the change. A dedicated runtime branch-delay IRQ gate was added and is
  recorded in the following entry.
- This correction is a CPU architectural bug fix, not Linux boot closure.
  Full RTL Linux userspace boot, complete ISA compliance, and RTL/QEMU
  differential signoff remain open.

### 2026-08-27 branch-delay IRQ runtime regression closure

- Added `make cpu-irq-delay-slot-gate`, which enables timer source 2, accepts a
  real SoC interrupt while a looping branch is in flight, and requires the
  handler to observe `Cause.BD=1` before writing the success mailbox.
- The first run exposed two real issues: the test had inverted the PIC enable
  value, and the CPU delay-slot metadata used `branch_taken` instead of the
  advancing control-transfer indication. The RTL now marks ordinary branch
  slots (including not-taken branches), excludes annulled branch-likely slots,
  and derives interrupt BD from all flushed MEM/EX/ID slots. The passing run
  exercised the important `branch in MEM / delay slot in EX` case.
- The gate passed with `REGRESSION_TEST_SUCCESS`, `CPU_CP0_SUMMARY intr=1`, and
  no watchdog expiry. This closes the targeted asynchronous IRQ BD/EPC runtime
  slice; full Linux IRQ ABI and complete privileged-ISA signoff remain open.

### 2026-08-27 bounded RTL Linux delay/interrupt diagnostic

- Added opt-in `LINUX_DELAY_TRACE`, `LINUX_DELAY_TRACE_LIMIT`,
  `LINUX_DELAY_TRACE_START` and `LINUX_DELAY_TRACE_END` controls to the RTL
  Linux progress gate. The trace observes the WB PC even when an entry is
  invalid or has been flushed, and records `$a0`, instruction, ERET, interrupt,
  EPC, Cause and Status without changing RTL timing.
- `make rtl-frontend-compile` passed all `8/8` configurations after the
  checker change. A direct no-coverage capture of the relocated image reached
  `cycle=7,509,009` without OOM or an RTL simulator error. It observed timer
  interrupt acceptance at `PC=0x892434e4`, with `EPC=0x892434e4`; no userspace
  marker was observed in the bounded slice.
- The 7.5M-cycle capture used the initial WB-valid-only probe and therefore did
  not prove a committed `__delay` decrement because target entries were
  flushed/invalid at the interrupt boundary. The broadened probe was compiled
  and exercised by the fresh 1M-cycle progress gate; a longer capture is still
  required to collect the new invalid-WB evidence. Full RTL Linux userspace
  boot and RTL/QEMU differential signoff remain open.

### 2026-08-26 Linux RDHWR architectural encoding correction

- Linux clocksource initialization exposed that the RTL and project fixtures
  had encoded `RDHWR` with `rs=3`. GNU MIPS32R2 emits the architectural
  `SPECIAL3` form with `rs=0`; for example `RDHWR v0,$2` is `0x7c02103b`.
- Corrected the RTL control decode, CPU privilege allowance, ID-stage CP0
  mapping, QEMU retire decoder, and all affected firmware fixtures to the
  standard encoding. This removes the previous false confidence from tests
  that shared the RTL's non-standard encoding.
- The fresh Linux RTL trace reached the prior RI at `PC=0x88cf34d8`, so this
  correction targets the proven post-boot blocker. The RDHWR and ISA gates
  must be rerun before claiming closure; full Linux RTL userspace boot and
  complete ISA compliance remain open.

### 2026-08-26 RTL Linux physical-memory contract correction

- Corrected `tb/linux_boot/mips32_soc_ref_rtl.dts` so the RTL Linux memory
  resource starts at physical `0x08000000`, matching the DDR window and the
  image produced by `build_rtl_linux_image.sh`. The previous `reg = <0 0x01000000>`
  declaration made Linux treat low physical addresses as RAM even though the
  Linux-only crossbar alias mapped them into the DDR region containing kernel
  text; a dirty D-cache writeback could therefore overwrite executable code.
- `build_rtl_linux_image.sh` now emits the same physical base from one named
  manifest constant. Fresh image construction passes and records
  `KERNEL_LOAD_PHYSICAL=0x08000000`; `make rtl-frontend-compile
  RUN_ROOT=/tmp/rtl_frontend_after_linux_dts` passes all `8/8` configurations.
- A fresh bounded RTL Linux run was resource-safe but did not reach a marker
  within 240 seconds, so this fixes the proven address-contract defect without
  closing RTL Linux userspace boot or the full RTL/QEMU Linux differential.
  The remaining diagnosis must follow post-entry CPU progress with a bounded
  retirement/progress probe.

### 2026-08-25 L2 nonblocking dirty writeback buffer closure

- `rtl/cache/l2_cache_nb.v` now has an opt-in fixed `WB_DEPTH=4` dirty-victim
  buffer. Miss acceptance snapshots the victim line/data, blocks dirty
  replacement when no slot is free, drives downstream `AW/W` from the
  snapshot, and frees the slot after `B`.
- The L2 unit test fixes the four-entry configuration and adds a known-dirty
  four-line replacement pressure sequence. Fresh evidence:
  `RUN_DIR=build/unit_tb/cache_concurrency_wb_depth4_retry
  tb/unit/cache/run_concurrency_gate.sh` -> `peak_mshr=8 peak_wb=4`,
  `hit_under_miss_beats=32`, `reads_checked=63`, PASS.
- `L2_NONBLOCKING=1 make soc-smoke` and `make rtl-frontend-compile` also pass.
- The named integration entry `make l2-nonblocking-end-to-end-gate` passes
  with `L2_E2E_TEST_SUCCESS policy=nonblocking-write-back` in
  `build/soc_test/l2_end_to_end_nonblocking/sim.log`.
- Remaining boundary: this is a bounded single-downstream-transaction L2
  writeback contract. The NB L2 now has clean-line invalidate and dirty-line
  snoop writeback through `AW/W/B`; the standard gate reports
  `peak_wb=4` and `reads_checked=65` after both snoop-forced refills.
  Same-cycle matching snoop/request ordering is backpressured and covered;
  complete coherency/directory, arbitrary writeback error/reset timing, and
  default-path selection are still open.

### 2026-08-24 strict URG exclusion metadata closure

- `make coverage-strict-clean-gate` now passes for both the merged UVM VDB and
  product CPU/CP0 VDB. The gate dumps exclusions fresh from each VDB, changes
  only the URG mode marker from `default` to `strict`, and loads line/FSM/
  condition/toggle/branch files through `-elfilelist`.
- This avoids mixed-VDB checksum and cross-metric parser ambiguity while
  preserving the existing exclusion semantics and 99% threshold. The gate
  reports zero URG metadata warnings and emits auditable run-local files under
  `build/coverage/strict_clean/`.
- This closes metadata hygiene, not measured coverage percentage: current
  UVM/product scores remain below the 99% policy and full coverage signoff is
  still open.

## Current Phase

### 2026-08-23 SRSMap state slice

- Added opt-in CP0 SRSMap `(12,3)` storage and MTC0/MFC0 access. All eight
  4-bit Cause.IP mappings are writable and the selected mapping drives the
  shadow set used on interrupt entry.
- Added `make srs-map-gate`; CP0 unit evidence passes in
  `build/unit_tb/cp0_srs_map/sim.log`. Default CP0 and all eight RTL frontend
  configurations also pass.
- Added `make qemu-system-srs-map-differential-gate`; a real VIC source on
  Cause.IP2 maps to CSS=3 on RTL and QEMU and passes the retire comparison with
  `TRACE_COMPARE_PASS records=26`.
- SRS hardware interrupt mapping and nested synchronous-fault policy are now
  closed for the IP-based opt-in contract. External VEIC/EICSS mode, Linux SRS
  ABI and scheduler/lazy ownership remain open.

### 2026-08-16 execution update

- Default WT L2 now receives D-cache `AWCACHE/ARCACHE` attributes. Uncached
  KSEG1 reads bypass tag/data lookup and uncached writes do not update a cached
  line. `make rtl-frontend-compile` passes all `8/8` configurations and
  `make l2-cpu-gate` passes.
- The bounded software MMU test now accesses its root/L2 page tables through
  KSEG1 aliases. `make mmu-refill-gate` passes the CPU-level TLBWI
  invalidate/refill pressure with `refills=7`, `demand_faults=6`,
  `page_allocs=4`, `permission_faults=1`, `unexpected_exc=0`, and
  `MMU_REFILL_MARKER_PASS`.
- `mips_tlb` now treats `TLBWI` entries with both EntryLo valid bits clear as
  invalid, and `make tlb-invalidate-gate` passes. The CPU integration fix also
  suppresses GPR/CP0 writeback for faulting WB entries, preserving the base
  register across ERET retry and closing the dynamic pressure case.
- The same exception-precision change passes `make cpu-cp0-gate`; the default
  frontend, TLB invalidate, and L2/CPU gates also pass after the change. The
  CPU gate's existing URG exclusion checksum warnings remain review items;
  they are not treated as coverage signoff.

### MMU demand paging slice: COMPLETE (bounded firmware OS contract)

- `make mmu-refill-gate` exercises a software-owned two-level PTE path.
- First touch allocates four backing PFNs and populates valid/user/write/dirty
  PTEs; the handler converts PTEs to EntryLo, fills deterministic TLB pair
  slots, and ERETs to retry.
- Second-pass accesses verify PTE/TLB reuse; the pressure pass reports
  `refills=7`, `demand_faults=6`, `page_allocs=4`, `permission_faults=1`,
  `unexpected_exc=0`; the read-only page's failed store leaves its backing
  value unchanged.
- Linux page allocator, multi-process ASID lifetime, and multicore shootdown
  stress remain open and are not claimed by this gate.
- `make mmu-ipi-shootdown-pressure-gate` passes 32 repeated generation/ASID/VPN
  invalidations, stale-generation rejection, busy-request rejection, and
  missing-target timeout. This closes the RTL shootdown protocol pressure
  slice only; scheduler/page-table ownership and multicore end-to-end Linux
  shootdown remain open.
- Fresh `make mmu-hardware-walker-soc-gate` passes the hardware-walker corpus
  using its dedicated `0xFFF0` marker. Fresh ASID-context, process-pressure,
  and PageMask gates also pass; these remain bounded RTL/firmware slices and
  do not claim Linux VM ownership or full OS shootdown semantics.
- `make product-mmu-process-pressure-gate` has fresh SoC evidence with four
  software ASIDs, distinct PFNs, dynamic-entry shootdown, wired-entry
  retention, and `refills=8` in
  `build/soc_test/product_mmu_process_pressure/sim.log`.
- The same guest passes on `mips32-soc-ref` through
  `build/isa_ref/qemu_system_mmu_process_pressure_final/completion_report.md`.
  This is a pass-boundary cross-model contract, not per-retire MMU
  differential evidence.

- The PageMask product workload now passes all four 4KB/16KB/64KB/256KB
  demand-refill and data-access phases (`refills=3`) with distinct ASIDs,
  even/odd halves, non-zero offsets and PFN folding. The fresh run also
  reaches the final success mailbox after the 256KB data phase, so the prior
  behavioral-DDR stall note was stale and is removed. Linux VM ownership,
  production page-table management and the hardware walker's explicit 4KB
  contract remain open.

### FPU: PARTIAL (opt-in behavioral single/double development slices)

- `SOC_FPU_ENABLE=0` remains the default and retains COP1-as-RI behavior.
- In the opt-in configuration, `Status.CU1` is now reset-disabled, writable
  through `MTC0`, and enforced on every COP1 instruction. An unenabled COP1
  instruction raises `CpU=0x0b` without committing FPR/FCSR state.
- `make fpu-single-gate` passes the CPU-integrated MTC1/MFC1/CTC1/CFC1 and
  single-precision ADD/SUB/MUL/DIV/SQRT/ABS/MOV/NEG contract, plus
  `RECIP.S`/`RSQRT.S`,
  `CVT.S.W`, `CVT.W.S`, `ROUND.W.S`, `TRUNC.W.S`, `CEIL.W.S` and
  `FLOOR.W.S`, `MOVZ.S` and `MOVN.S` with true and false integer conditions.
- The same opt-in CPU gate covers `MOVF`/`MOVT` with `cc=0`, using
  `FCSR[23]` for both write-enable polarities. `make
  mips-control-fpu-cond-gate` also checks non-zero condition selectors,
  malformed reserved fields and protects the existing `MTHI` encoding.
- FCC1..FCC7 are now decoded and stored using the architectural FCSR
  positions `[25:31]` (FCC0 remains `[23]`, `[24]` remains reserved). The
  controller gate covers FCC1/FCC7 and the real FPU firmware gate exercises
  compare plus `MOVT cc=3`; this extends the selected COP1 condition-code
  slice, but does not close IEEE-754 traps/rounding or full COP1 compliance.
- `make fpu-double-gate` passes the real CPU-integrated even-register-pair
  path for ADD.D/SUB.D/MUL.D/DIV.D/ABS.D/MOV.D/NEG.D, `RECIP.D`/`RSQRT.D` and the selected
  conversion/rounding slice: `CVT.S.D`, `CVT.D.S`, `CVT.D.W`, `CVT.W.D`, and
  `ROUND/TRUNC/CEIL/FLOOR.W.D`, plus `MOVZ.D`/`MOVN.D`.
- `make qemu-system-fpu-double-differential-gate` passes with the fresh
  `TRACE_COMPARE_PASS records=225`, comparing the same double arithmetic and
  conversion/rounding and conditional-move guest through the system-mode
  retire boundary.
- `make mips-fpu-recip-gate` passes the standalone single/double primitive
  vectors; the decoder gate covers legal single/even-pair D encodings and
  rejects W-format and odd D-pair reciprocal encodings.
- `make qemu-system-fpu-single-differential-gate` compares the enabled-FPU
  startup and single-precision guest through the mailbox retirement boundary.
  The project-owned QEMU 9.2 patch
  `scripts/qemu/patches/qemu-9.2-mips32-fpu-int32-indefinite.patch` makes
  invalid/overflow W conversions return the MIPS architectural indefinite
  value `0x80000000`, matching the RTL. Direct system-mode execution prints
  `FPU PASS`; the fresh differential reports `TRACE_COMPARE_PASS records=1248`.
- The same fresh differential now includes correctly encoded COP1X
  `MADD.S/MSUB.S/NMADD.S/NMSUB.S` and passes `TRACE_COMPARE_PASS records=1248`;
  the double guest includes the four D forms and passes
  `TRACE_COMPARE_PASS records=225`. COP1X uses QEMU's architectural
  `fs * ft +/- fr` field mapping (`rd`, `rt`, `rs`) and rejects odd D-pair
  selectors in all four register fields.
- `make fpu-single-gate` covers real `LWC1`/`SWC1` traffic and the opt-in
  blocking `LDC1`/`SDC1` two-word path through the CPU data path, including
  FPR load-use ordering and the behavioral DDR window at `0x00008000`.
  The double path is limited to even FPR pairs and commits a load only after
  both word beats complete.
- `make fpu-fpe-exception-gate` passes the first precise FPE slice: with CU1
  enabled and only FCSR Enable[div0] set, `DIV.S 1.0/0.0` reaches an ExcCode
  15 handler, updates FCSR Cause/Flags (`0x00008420`), and leaves the FPR
  destination uncommitted. The gate is deliberately narrow; other exception
  classes, configurable rounding, OS context save/restore and complete
  IEEE-754/COP1 compliance remain open.
- `make fpu-rounding-gate` passes the real CPU FCSR.RM[1:0] slice: nearest-even
  ties (`1.5/2.5 -> 2`), toward-zero (`-1.75 -> -1`), toward +infinity
  (`1.25 -> 2`) and toward -infinity (`-1.25 -> -2`). Fixed `ROUND.W.S`
  remains nearest-even independent of RM. Primitive and SoC evidence now use
  the same explicit rounding-mode input.
- `make fpu-fpe-invalid-gate` also passes `DIV.S 0.0/0.0` with FCSR
  Enable[invalid], proving the precise ExcCode 15 path for Invalid, sticky
  Cause/Flags, and suppressed FPR commit. This extends the FPE evidence beyond
  Divide-by-zero but does not close overflow/underflow/inexact policy.
- `make fpu-fpe-overflow-gate` passes finite-single overflow (`MAX_FINITE * 2`)
  with FCSR Enable[overflow], precise ExcCode 15, Overflow Cause/Flags and
  suppressed FPR commit.
- `make fpu-fpe-underflow-gate` passes the selected finite-single subnormal
  boundary vector using the minimum positive subnormal operand. The bit-level
  classification records the selected underflow/inexact Flags/Cause behavior
  without relying on host `shortreal` preservation of subnormals. This does not
  close the complete tininess, rounding, inexact, double-precision, or OS ABI
  policy.
- This is a behavioral simulation primitive. Complete IEEE-754 flags/rounding,
  complete FPE class coverage, Linux FPU ABI and synthesizable FPU hardware
  remain open. The bounded FCSR model now keeps Flags[6:2] sticky
  and updates Cause[16:12] from the latest completed FPU operation, matching
  the QEMU system differential corpus without claiming precise trap delivery.

- Added `make mips-fpu-flags-gate`: the primitive now classifies single
  `Inf-Inf`, double `Inf/Inf`, double `0*Inf` as invalid and the
  minimum-normal-times-half double result as underflow. The gate passes
  `REGRESSION_TEST_SUCCESS mips_fpu_flags invalid=3 underflow=1`. This is a
  primitive boundary extension, not complete IEEE-754 or double precise FPE
  signoff.

- `make mips-fpu-compare-gate` closes the behavioral COP1 C.* predicate
  matrix: all 16 conditions are checked for single- and double-precision
  ordered less-than, equal, and quiet-NaN inputs, including unordered-inclusive
  and inverted predicates.
  The existing `fpu-branch-gate` and
  `qemu-system-fpu-branch-differential-gate` cover the condition-bit branch
  path, ordinary delay slots, and likely annul behavior. This closes the
  predicate-result slice only; precise signaling/quiet NaN exception policy,
  IEEE-754 rounding, FPE traps, and FPU OS context/ABI remain open.
- The compare unit gate now covers the same 16 predicates for both single and
  double precision. The real CPU executes the immediate `CFC1`/`SRL`/`ANDI`/
  branch consumer chain without explicit bubbles, and the same path now passes
  QEMU system retire differential. Arbitrary untested COP1/GPR forwarding
  combinations remain outside this bounded contract.

### 2026-08-24 QEMU FPU conversion boundary

- Added the project-owned QEMU patch and included it in
  `scripts/qemu/build_mips32_soc_ref.sh` input hashing and source-marker
  validation. The custom machine rebuild is therefore reproducible and does
  not depend on an untracked build-directory edit.
- `make fpu-single-gate` passed with `FPU PASS` and
  `make qemu-system-fpu-single-differential-gate` passed with
  `QEMU system RTL retire differential: PASS`.
- Scope is limited to the opt-in conversion invalid-result boundary. Full
  IEEE-754 NaN/signaling, inexact/rounding policy, complete FPE classes, OS
  FPU context/ABI and full ISA remain open.

### L1 nonblocking CPU integration: COMPLETE (opt-in, multi-response staging)

- `make l1-nonblocking-gate`: PASS for the standalone 2-MSHR/4-entry-WB line block.
- `SOC_L1_NONBLOCKING_ENABLE=1` now selects a 4-entry ROB in `mips_cpu`.
- `tb/unit/run_rtl_frontend_compile.sh` includes the `l1_nonblocking` SoC elaboration configuration.
- `mips_core` now selects the opt-in `l1_cache_nb_cpu_axi` adapter. It preserves
  the legacy dcache for uncached/maintenance traffic and bridges cacheable
  line traffic to AXI. The adapter uses the SoC 64-set geometry and keeps AXI
  ownership through writeback transactions.
- The CPU-facing adapter and ROB FIFO elaborate on the real CPU path.
  `make l1-nonblocking-cpu-compat-gate` passes after keeping the ROB FIFO
  disabled unless CPU nonblocking is also enabled; default blocking behavior
  remains unchanged.
- Cacheable CPU stores now enter the same opt-in L1 as cacheable loads. This
  removes the previous split-cache stale-data failure (stores in legacy dcache,
  loads in L1); uncached and maintenance traffic remains on the legacy path.
  Store requests are single-accepted while outstanding, and stores use an
  untagged response ID so an older tagged load cannot replay them.
- The CPU path now carries an explicit response-valid tag and a four-slot
  load-use scoreboard; legacy store/uncached responses cannot complete a ROB
  load slot. This is implementation progress, not closure evidence.
- The FIFO WB bundle is a fully registered interface: commit data and
  `wb_valid` advance together, and commits are no longer suppressed by PC
  de-duplication. The adapter holds L1 responses while the legacy owner is
  active, and the load scoreboard is released only after architectural WB
  retirement.
- The L1 occupancy counter reset/counting bug was fixed; standalone evidence
  remains `REGRESSION_TEST_SUCCESS l1nb mshr=2 wb=4`.
- L1 responses now use a four-entry FIFO (`MSHR_COUNT + 2`) shared by hits,
  primary refills, and secondary responses. This preserves two independent
  refill responses when the CPU-side response is backpressured; the standalone
  gate covers out-of-order distinct-line returns.
- Nonblocking load ROB allocation is now gated by an actual data-request
  handshake (or completion/fault), so a cache-backpressured load cannot create
  an unmatchable unready ROB entry. The legacy adapter also latches accepted
  store requests and keeps dcache ownership explicit.
- The CPU integration now tracks GPR destinations admitted to the nonblocking
  ROB and stalls only dependent ID operands until retire. This closes the
  previously observed ALU-WB visibility error (`$a1` in the cache sweep).
  Blocking/uncached loads that wait in EX/MEM after `data_ok` are allocated as
  ready entries; `mem_done` is part of the ready-at-allocation contract.
- The legacy AXI adapter now records the actual muxed AW handshake before
  exposing WREADY/WVALID to the dcache. Fresh accepted requests clear the
  latch, and a new request has priority over clearing the previous response.
  This prevents an earlier writeback's WREADY from consuming a later W beat.
- The crossbar has a provisional same-cycle AW+W owner for slaves that sample
  both channels together, plus an opt-in SoC integration guard that serializes
  a master's next AW until its previous W completes. Direct crossbar
  multi-outstanding tests keep their original setting.
- Fresh `make l1-nonblocking-cpu-multi-gate` reaches
  `REGRESSION_TEST_SUCCESS`.
- Fresh `make l1-nonblocking-cpu-stress-gate` passes 3 seeds and 3 reset runs.
- The fresh CPU rerun also reports `D-CACHE EVICTION OK` and
  `LOAD SUB-WORD OK`. It fixed two retirement timing defects: GPR writes are
  gated by the nonblocking ROB `wb_valid` pulse, and a same-cycle head
  completion bypasses old slot data before the slot update.
- Fresh `make l1-nonblocking-cpu-error-gate` passes precise CPU AXI refill
  error recovery; `make rob-fifo-gate` and `make rtl-frontend-compile` also
  pass after the integration fixes.
- The 2026-08-17 rerun found and fixed a real FIFO boundary defect: when a
  failed tagged response completed and retired the full ROB head in the same
  cycle that reused its tag, the old bypass omitted `complete_error` and could
  first retire the fault as normal, then poison the reused slot. The FIFO now
  carries CacheErr metadata through the same-cycle completion bypass and
  suppresses completion writes to the reused tag. The CPU error gate passes
  after the fix.
- `make l1-nonblocking-cpu-error-gate` passes a real CPU/D-cache AXI refill
  fault: the DDR model injects one SLVERR at `0x00008000`, write-through L2
  drains and propagates the error without installing the line, and the ROB
  retires precise `CacheErr`/ExcCode 30 before ErrorEPC recovery.
- `make l1-nonblocking-cpu-two-error-gate` adds two distinct cache-line
  SLVERR injections at `0x00008000` and `0x00009000`. The real opt-in CPU/L1/
  ROB path issues both misses before either response. The first CacheErr is
  retired precisely; the younger request is flushed and replayed after ERET,
  while the second injected response is observed without corrupting state.
  This closes the selected simultaneous-response precise-flush/replay
  contract, not a claim that two younger/older synchronous faults retire in
  one architectural stream.
- `make dma-axi-error-gate` now covers a real DMA source read receiving a
  behavioral DDR-model SLVERR. The DMA reports `ERR_AXI_READ`, asserts channel
  0 IRQ and PIC source 3, and clears DONE/ERR through the combined W1C
  re-arm. DMA reset-in-flight and physical DDR fault behavior remain open.
- `make dma-reset-inflight-gate` now asserts the actual SoC reset after DMA
  channel 0 is busy, then requires the restarted firmware to complete and
  verify a 256-byte uncached transfer plus DONE/W1C. Physical DMA/DDR reset
  policy and arbitrary multi-channel reset interleavings remain open.
- `make qemu-system-dma-reset-inflight-gate` now covers the matching opt-in
  custom-machine boundary. The QEMU reference requests one reset before the
  first transfer copies data, clears DMA busy/status/IRQ state in its reset
  callback, and the restarted guest completes the same 256-byte transfer and
  DONE/W1C check. This remains a reference-machine contract, not physical
  DDR reset timing or multi-channel reset signoff.
- The opt-in L1 AXI bridge now accepts two refill reads with IDs 0/1 and
  routes each burst response by ID; the behavioral DDR model gives slots
  independent latency so the second read may complete first. Existing CPU
  multi/stress/error gates pass after this change. Simultaneous CPU exception
  recovery and maintenance/coherence contracts remain open.
- Fresh post-fix verification also passes `make l1-nonblocking-cpu-two-error-gate`,
  `make l1-nonblocking-cpu-two-error-reset-gate`, `make cache-concurrency-gate`,
  and `make l1-nonblocking-cpu-stress-gate` (3 seeds plus 3 reset runs). The
  selected opt-in error/retirement contract is green; three-or-more faults,
  arbitrary error/reset timing, maintenance/coherence, and default-path
  switching remain explicitly open.
- Added `make l1-nonblocking-cpu-error-reset-gate`. Its testbench waits for a
  real L1 MSHR, asserts reset before the injected refill response, verifies
  reset release precedes the post-reset SLVERR injection, and requires precise
  CacheErr/ErrorEPC recovery to the success mailbox. This closes the selected
  CPU error-plus-reset-in-flight vector; arbitrary reset timing, simultaneous
  independent faults, maintenance/coherence, and default-path switching stay
  open.
- Added `make l1-nonblocking-cpu-two-error-reset-gate`. Its testbench waits for
  both CPU-path MSHRs, asserts reset, then requires both independent SLVERR
  addresses to be injected again after reset release before precise recovery
  reaches the mailbox. This closes the selected two-MSHR reset/error
  interleaving vector; three-or-more faults and arbitrary timing remain open.
- Added `make l1-nonblocking-maintenance-compat-gate`. It combines the CPU
  CACHE completion/stall and CP0 TagLo/TagHi/SYNC regressions with a source
  audit of the adapter's explicit legacy-maintenance routing. The adapter now
  waits for line traffic, queued responses, active requests and outstanding
  count to drain before issuing maintenance, so an in-flight MSHR cannot be
  invalidated. This closes the compatibility boundary; a nonblocking
  maintenance protocol, full concurrent maintenance semantics, full ordering,
  and OS cache ABI remain open.
- Added `tb/sva/l1_maintenance_props.sv` and its bind. `make sva-gate` passes,
  and `SVA_ENABLE=1 make l1-nonblocking-cpu-two-error-reset-gate` passes with
  the opt-in CPU path. The assertions enforce the maintenance-idle guard and
  verify raw maintenance is held while L1 traffic is live; this remains
  simulation assertion evidence, not formal signoff.
- Added `tb/sva/l1_resource_props.sv`, bound to every `l1_cache_nb` instance.
  It checks the four-entry response FIFO, two-MSHR and four-entry writeback
  bounds, plus reset clearing of all three occupancy counters. This remains
  simulation assertion evidence, not formal signoff.
- Updated `current-contract-signoff` prerequisites to execute the L1
  maintenance compatibility, CPU error/reset, and SVA gates before the
  existing full-chip UVM and coverage stages. Coverage thresholds and
  exclusions were not changed.
- Added the vendor-neutral `qspi-soc-quad-gate` and `ddr4-complete-gate` to
  `current-contract-signoff`. The aggregate still does not claim physical
  QSPI/DDR PHY, JEDEC timing, Linux drivers, or board-level signoff.
- Added `qspi-vendor-neutral-complete-gate`, which consolidates the existing
  QSPI command, flash, timeout/retry, pad/arbiter, x1/quad XIP and SoC
  integration gates. It is now the QSPI prerequisite of the unified signoff;
  default x1 behavior remains unchanged.
- `make l1-nonblocking-axi-bridge-gate` now directly instantiates the bridge
  and proves two AR handshakes with IDs 0/1, ID 1 completing before ID 0,
  independent error association, and reset flushing both read slots. This
  closes the bridge-level OOO routing evidence only; CPU simultaneous-fault,
  maintenance/coherence, and arbitrary reset/error interleavings remain open.

### ISA boundary audit

- `make isa-implementation-audit` checks the machine-readable status matrix in
  `docs/isa_implementation_matrix.md` and emits
  `build/isa_audit/isa_implementation_audit_report.md`.
- The matrix deliberately records the current integer/R2 and opt-in single
  precision slices as implemented or partial, while double-precision/IEEE-754
  and full privileged/compliance behavior remain deferred. This is an
  auditable boundary, not a full ISA signoff.
- Branch-likely control flow is now implemented in the decoder, ID and IF
  path. `make branch-likely-gate` covers BEQL/BNEL/BLEZL/BGTZL and BLTZL/BGEZL
  with taken delay-slot execution and not-taken annulment, plus BLTZALL/BGEZALL
  link-on-taken and no-link-on-annul behavior. Full reserved-field compliance,
  complete privileged ISA and full FPU remain open.
- `make mips-control-special3-gate` passes SPECIAL3 EXT/INS/RDHWR boundaries
  and the complete supported BSHFL encoding matrix: WSBH/SEB/SEH are checked
  as valid operations, all 29 other `sa` sub-op values are reserved, and the
  fixed BSHFL `rs=0` field is enforced. Invalid encodings raise decoder RI
  without a register write, memory request, cache operation, CP0 write,
  branch, or jump side effect. BITSWAP is covered by the separate RTL
  firmware gate; full ISA compliance remains open.
- `make bitswap-gate` passes the real CPU/DDR firmware path for two byte-wise
  bit-reversal vectors, including the `0x800100ff -> 0x018000ff` boundary;
  the test's failure mailbox was corrected after observing the RTL result.
  QEMU R2 differential remains intentionally excluded because the available
  QEMU profile gates this legacy encoding behind R6.

- `make qemu-system-wait-differential-gate` passes the selected WAIT contract:
  WAIT retires, a replayed software interrupt wakes the core, the handler
  clears Cause and returns through ERET, and the post-WAIT path reaches the
  mailbox on both RTL and `mips32-soc-ref`. Physical interrupt timing and
  broader privileged ISA remain open.
- `make mips-control-cache-gate` passes the decoder contract for all 10
  implemented CACHE operations, five reserved CACHE encodings, SYNC, and
  PREF. Invalid CACHE encodings raise RI without maintenance, GPR, or memory
  side effects; full cache ordering and OS cache ABI remain open.
- `make mips-control-cp0-gate` passes eleven supported COP0/COP1 boundary
  encodings and twenty-two malformed/reserved encodings. It checks ERET/MFMC0,
  COP0 sel/transfer, COP1 double even-pair, and MFC1/CFC1/MTC1/CTC1 transfer
  fields. Full privileged ISA remains open.

- `make fpu-double-gate` passes the opt-in double-precision pair path through
  the real CPU and SoC: even-numbered FPR pairs, ADD.D/SUB.D/MUL.D/DIV.D/
  ABS.D/MOV.D/NEG.D, `MOVZ.D`/`MOVN.D`, the selected S/D/W conversions, and
  fixed-rounding vectors reach the success mailbox. Exact
  IEEE-754 flags/rounding modes, precise FPE traps, Linux FPU ABI and Linux use
  remain open; the bounded scheduler FPR/FCSR context save/restore slice is
  covered by `fpu-context-gate`; the QEMU system differential companion is
  tracked in the evidence registry.

### Verification Evidence (2026-08-13 fresh run)

- QEMU DMA v2 event contract is CLOSED for the captured behavioral corpus
  through
  `make qemu-system-dma-v2-event-contract-gate`. It captures ordered
  START/DONE/W1C/IRQ events from the RTL and `mips32-soc-ref`, compares
  semantic fields strictly, and intentionally ignores status-poll latency.
  The gate corpus includes legacy alias, v2 direct, zero-length, W1C/re-arm,
  DMA IRQ, and a real two-descriptor SG chain. The fresh SG comparison passes
  with `DMA_EVENT_CONTRACT_PASS events=23` under
  `build/isa_ref/qemu_system_dma_v2_event_contract_fresh_20260814/`.
  Physical AXI fault/reset-in-flight coverage remains residual risk and is not
  claimed closed.

- `make fabric-unit-gate`: PASS (5/5).
- `make soc-smoke`: PASS with the default blocking/write-through configuration.
- `make rtl-frontend-compile`: PASS (8/8), including CPU nonblocking and FPU
  opt-in elaboration.
- `make l1-nonblocking-cpu-multi-gate`: PASS on the fresh rerun; the real
  CPU/D-cache path reaches the success mailbox. The companion 3-seed stress,
  precise AXI error, ROB FIFO, and RTL frontend gates also pass.
- `RUN_DIR=build/soc_test/mmu_refill_permission_final
  tb/soc_test/run_mmu_refill.sh`: PASS with the software PTE/Mod evidence
  above.
- `make mmu-ipi-shootdown-pressure-gate`: PASS with 35 total protocol events.
- `make phase3-regression`: PASS (8/8). The APB bit-pattern sweep now uses
  `build/firmware/apb_bit_sweep_idle/firmware.hex`, an idle CPU guest that
  leaves GPIO/timer APB state exclusively to the directed sequence. This
  avoids false failures caused by concurrent smoke-firmware peripheral writes.
- `make current-contract-signoff`: all functional stages pass, including
  Phase 2, Phase 3A/3B/3C, CPU/CP0, and 10/10 multi-seed stress tests. The
  gate remains FAIL only at the explicit coverage threshold stage: UVM merged
  SCORE 71.99%, COND 97.08%, TOGGLE 66.18%, FSM 37.07%, BRANCH 59.67%, and
  Product CPU/CP0 SCORE 69.85% (99% thresholds). Exclusions were not changed
  to mask uncovered objects; the authoritative report is
  `build/signoff/current_contract/current_contract_signoff_report.md`.

- Fresh rerun on 2026-08-16: Phase 2 directed/coverage `16/16`, Phase 3A
  directed/coverage `8/8`, Phase 3B `1/1`, Phase 3C `1/1`, CPU/CP0 firmware,
  and 10-seed stress all passed. The same run still stops at
  `COVERAGE_THRESHOLDS`; UVM merged metrics were SCORE 71.16%, COND 97.48%,
  TOGGLE 66.47%, FSM 37.50%, BRANCH 54.41%, and Product CPU/CP0 SCORE
  68.79% (99% thresholds). This remains a genuine coverage residual, not a
  functional regression.

- `make coverage-strict-clean-gate` currently fails before URG because the
  fresh generated `.el` files contain rules that do not cleanly match the
  mixed merged VDB. The keyed manifest synchronization is now fixed and the
  audit passes with 138 entries; strict URG still reports checksum mismatch,
  invalid-signal, and invalid-vector/condition residuals. Exclusion rules and
  coverage thresholds were not deleted or reduced to manufacture a pass.

- Fresh `make qemu-system-current-contract-gate` passed after rebuilding the
  QEMU 9.2 `mipsel-softmmu` binary. The selected peripheral, DMA-v2, QSPI,
  DDR, retire-capture, and dependent system-mode differential corpus remains
  green. This is selected-corpus evidence and does not upgrade the project to
  full ISA/MMU/Linux/physical-device signoff.

- Fresh QEMU system architecture rerun passes all currently executable
  selected gates: `qemu-system-isa-r2-differential-gate`,
  `qemu-system-mmu-contract-gate`,
  `qemu-system-mmu-process-pressure-gate`,
  `qemu-system-fpu-single-differential-gate`, and
  `qemu-system-fpu-cu1-exception-differential-gate`. The aggregate
  `qemu-system-current-contract-gate` also passes. Reports are retained under
  `build/isa_ref/qemu_system_{isa_r2_differential,mmu_contract,mmu_process_pressure,fpu_single_differential,fpu_cu1_exception_differential,current_contract}/`.
- `make dual-core-frontend-compile` and `make dual-core-soc-gate`: PASS.
  The opt-in dual-core wrapper elaborates and the SoC guest observes core-1
  execution, IPI invalidate routing in both directions, isolated exception,
  and core-1 reset behavior.
- `make coherency-stress-gate`: PASS on the fresh real two-core path. Core 0
  and core 1 each complete 8 shared-memory rounds, including word and
  sub-word updates, and the guest reports
  `COH_STRESS_SHARED_MEMORY_PASS`. This closes the selected dual-core cache
  coherency stress slice; it does not claim Linux scheduler/VM ownership or
  arbitrary multicore shootdown behavior.

### QEMU system-mode RTL retire differential: COMPLETE for selected corpus

- Fresh `make qemu-system-isa-r2-differential-gate` passes with
  `TRACE_COMPARE_PASS records=308`.
- Fresh `make qemu-system-fpu-single-differential-gate` and
  `make qemu-system-fpu-cu1-exception-differential-gate` both pass with
  `SOC_FPU_ENABLE=1`.
- These are selected system-mode retire differentials through the mailbox
  boundary. They do not constitute full ISA, full MMU, Linux, or arbitrary
  interrupt/device differential signoff.

- Fresh `qemu-system-trap-differential-gate` and
  `qemu-system-trap-imm-differential-gate` pass the RTL/reference comparison
  for all six register traps and six immediate traps, including signed and
  unsigned predicates, ExcCode 13 and ERET recovery. This closes the selected
  integer trap contract only; full ISA and privileged compliance remain open.

### CPU helper load/return forwarding: GATED (default blocking path)

- `make cpu-load-return-gate` builds a minimal hand-written guest that writes
  an APB UART scratch register, performs the load inside a `jal`/`jr $ra`
  helper, and immediately consumes the returned value through `xor` and
  `bne` before writing the success mailbox.
- The fresh run passes on the default blocking/write-through SoC path. This
  closes the previously reported helper-return reproducer for this APB
  contract; it does not claim all compiler-generated call/return hazards,
  nonblocking ROB behavior, or full ISA compliance.

- `make qemu-system-vic-differential-gate`: PASS after fixing a real precise-
  retirement race in the CPU blocking/APB path.  The APB/VIC response was
  returned correctly, but an unrelated IF/exception stall could prevent the
  one-cycle blocking response from entering MEM/WB; the CPU now prioritizes
  blocking response commit and defers asynchronous interrupt acceptance while
  MEM is active.
- The VIC corpus compares both simultaneous software sources through the
  first and second handler `VEC_ID` reads (9 then 8), ACK/SOFT_CLR, ERET, and
  mailbox retirement.  This is selected system-mode differential evidence,
  not full ISA/MMU/Linux signoff.
- The QEMU Linux-user default path is now the built project artifact at
  `build/deps/src/qemu-9.2.0/build-mipsel-user/qemu-mipsel`; missing guest ELF
  input remains an intentional gate blocker rather than an implicit fallback.

## Gate Status And Next Work

### ISA R2 EXT/INS slice: COMPLETE (implemented-subset extension)

- `mips_control` decodes valid SPECIAL3 `EXT`/`INS` encodings and rejects an
  invalid `msbd < pos` field.
- The ALU receives the preserved `rd` field; `EXT` treats it as `size-1` and
  extracts from `rs`, while `INS` treats it as `msb`, preserves `rt`, and
  inserts the low field from `rs`.
- `make isa-r2-gate` passes with independent firmware checks for
  `EXT(0x12345678, pos=4, size=16) == 0x567` and
  `INS(0xffff0000, pos=8, size=8) == 0xffff7800`.
- This closes only the added R2 instruction slice. Full MIPS32 ISA compliance
remains open.

### Unaligned merge memory slice: COMPLETE (selected system differential)

- `make qemu-system-unaligned-gate` passes the real CPU/DDR path for
  little-endian `LWL`/`LWR` and `SWL`/`SWR` merge operations at unaligned byte
  offsets, with a precise success mailbox.
- `make qemu-system-unaligned-differential-gate` compares the same guest
  against `mips32-soc-ref` through the mailbox boundary.
- The comparator intentionally compares architectural GPR results for merge
  loads. RTL exposes the formatted merge result as `mem_rdata`, while the
  QEMU plugin exposes the raw aligned bus word in that field. Full ISA,
  cross-page merge faults and Linux unaligned-access policy remain open.

### PREF hint slice: COMPLETE (implemented-subset extension)

- Main opcode `PREF` is decoded as an ordered, non-trapping architectural
  no-op with no register or memory side effect in the current cache contract.
- `make isa-r2-gate` passes with `CPU_CP0_SUMMARY ... ri=0`; the ISA sweep
  also compares equal against QEMU for 324 retire records at
  `build/isa_ref/qemu_system_isa_r2_pref_final/completion_report.md`.
- Cache-specific prefetch policy remains implementation-defined; this does
  not expand the claim to full ISA compliance.

`BITSWAP` is implemented and directed-tested in the RTL as an R2-compatible
SPECIAL3 BSHFL operation. It is deliberately excluded from the QEMU
MIPS32r2 differential corpus because QEMU 9.2 gates the legacy SPECIAL3 case
behind `ISA_MIPS_R6`; this is a reference-model limitation, not an RTL
failure. Full ISA compliance remains open.

1. **CPU-facing ROB completion contract: COMPLETE (unit/single visible response)**
   - `SOC_ROB_FIFO_ENABLE=1` selects `mips_rob_fifo` on the real CPU path when
     L1 nonblocking is enabled.
   - Late completion updates the allocated slot's load data and converts a
     response error to a retiring CacheErr; retirement remains head-ordered.
   - Flush cancels all queued entries and the empty-queue path preserves the
     legacy MEM/WB bubble semantics.
   - `make rob-fifo-gate` passes, and the SoC compatibility gate passes with the
     blocking CPU contract.
   - RTL frontend coverage now includes the explicit
     `SOC_CPU_NONBLOCKING_ENABLE=1` configuration; `make rtl-frontend-compile`
     passes 8/8 elaboration configurations.
2. **True CPU hit-under-miss / multiple visible outstanding responses: COMPLETE (selected opt-in contract)**
   - The line-cache slice passes with 2 MSHRs, 4 writeback entries, and a
     4-entry response FIFO; the fresh CPU multi and stress gates pass.
   - WB-before-refill ordering, CPU/adapter SRAM-address eligibility, tagged
     ROB completion, reset-in-flight, and selected response-error contracts
     are covered. Three-or-more simultaneous error injection and broader
     random coverage remain residual items.
3. **Remaining opt-in CPU stress:** three-or-more simultaneous response errors,
   arbitrary reset timing, and broader random traffic. The selected two-MSHR
   reset/error interleaving is covered by a dedicated gate.

4. **L1 nonblocking error/reset contract: COMPLETE (standalone line slice)**
   - `make l1-nonblocking-errors-gate` passes with
     `REGRESSION_TEST_SUCCESS l1nb_errors mshr=2 wb=4`.
   - The new checker covers a failed refill returning errors to both primary
     and merged secondary IDs, two independent MSHRs completing failed and
     out-of-order, and reset flushing queued response/MSHR/WB state under
     response backpressure.
   - Evidence: `build/unit_tb/cache_concurrency/l1nb_errors/compile.log`,
     `sim.log`, and `l1_nonblocking_errors_report.md`.
   - This closes the standalone line-cache error/reset contract only; CPU
     three-or-more-error injection, coherence, and broad random traffic remain
     open.

5. **Dual-core coherency and IPI integration: COMPLETE (selected opt-in slice)**
   - Dual-core frontend and SoC boot gates pass with core-1 execution,
     bidirectional IPI routing, exception isolation, and reset isolation.
   - The shared-memory coherency stress guest passes 8 rounds on both cores,
     including byte-lane merge behavior and peer visibility.
   - Linux scheduler integration, OS-owned page tables, full multicore TLB
     shootdown, and unrestricted concurrent random traffic remain open.

## Deferred Architecture Tracks

### QEMU system peripheral differential: COMPLETE (selected contract)

- `make qemu-system-peripheral-differential-gate` passes in the fresh run
  `build/isa_ref/qemu_system_peripheral_differential_ddr_status_fix2/`.
- The UVM opt-in `SOC_ENABLE_DDR4_STATUS` define is now consumed by
  `soc_verif_top.sv`, so the RTL DDR status block is actually enabled for this
  gate while the default UVM/SoC path remains disabled.
- QEMU `mips32-soc-ref` matches the image-backed RTL QSPI status contract
  (`controller_present=0`) and the DDR VERSION/STATUS/ERROR/CONTROL contract.
- QEMU and RTL compare 115 retire records through mailbox completion.
- This closes the selected QEMU peripheral-model/differential slice only.
  The corresponding RTL/vendor-neutral QSPI command/FIFO/quad, DMA v1/v2
  product firmware, and DDR protocol/refresh/ECC slices are closed below;
  they are not yet QEMU custom-machine claims. Physical timing, external GPIO
  pin behavior, and full ISA/MMU/Linux differential remain open.

### Vendor-neutral QSPI/DDR controller slice: COMPLETE (behavioral contract)

- Fresh QSPI command, flash behavioral, x1 XIP, quad XIP, pad wrapper,
  shared-pin arbiter, SoC pad mux, and SoC quad/status gates pass.
- Fresh DDR4 controller functional/stress, status/PIC integration, PHY
  behavioral, and contract-entry audit gates pass.
- This closes the vendor-neutral behavioral/interface slice. Real JEDEC PHY
  training, board timing, device endurance, Linux MTD, DDR full-space memtest,
  STA/DFT, and ASIC signoff remain outside this contract.

### QEMU DMA v2 model: EVENT CONTRACT CLOSED, PHYSICAL RESIDUALS OPEN

- `mips32-soc-ref` now models the four-channel DMA v2 direct-copy CSR window,
  alignment/descriptor errors, zero-length completion, DONE/ERR W1C and
  channel IRQ sources.
- The RTL `dma_cpu` product gate passes and both RTL/QEMU producers reach the
  success mailbox. `make qemu-system-dma-v2-event-contract-gate` compares 20
  ordered semantic events across legacy alias, v2 direct, zero-length,
  W1C/re-arm and IRQ cases. Status-poll completion latency varies with
  AXI/cache transaction context and is intentionally outside the event
  contract. SG long-form data, physical AXI fault injection and reset-in-flight
  remain open.

### RDHWR SYNCI_Step system-mode differential: COMPLETE (selected R2 slice)

- The first mnemonic form was rejected by the RTL as RI because gas emitted
  the wrong SPECIAL3 `rs` field; this was corrected to the architectural
  `rs=3` encoding and the firmware enables HWREna before use.
- `make isa-r2-gate` passes with `CPU_CP0_SUMMARY ... ri=0`.
- `make qemu-system-isa-r2-differential-gate` passes with
  `TRACE_COMPARE_PASS`.
- The same selected corpus also checks deterministic `RDHWR CPUNum=0` and
  `RDHWR CCRes=2`; dynamic Count is intentionally excluded.
- This covers the selected standard RDHWR targets only; complete privileged
  access policy and full ISA compliance remain open.

### QEMU system-mode MMU contract: COMPLETE (selected contract)

- `make qemu-system-mmu-contract-gate` now runs the RTL
  `product_mmu_asid_context` gate and the same firmware under the project
  `mips32-soc-ref` QEMU machine.
- The selected workload passes ASID-specific software refill, ASID reuse,
  wired APB mapping, shootdown busy/done acknowledgement, and post-shootdown
  refill. Evidence is in
  `build/isa_ref/qemu_system_mmu_contract/`, including the RTL log, firmware
  hash, QEMU build identity, and CPU trace.
- QEMU's reference machine flushes its translated shadow TLB when the
  shootdown ACK reaches the architectural done state, while preserving the
  guest-owned CP0 TLB entries. This makes the next access take the guest
  software refill path, matching the selected RTL contract.
- This is a selected MMU contract gate, not full RTL/QEMU differential. OS
  page-table ownership, demand paging, multicore shootdown, Linux boot, and
  full privileged/ISA differential remain open.

### Closure boundary after the 2026-08-14 rerun

### 2026-08-16 execution update

- `make cpu-mmu-complete` passed with the fresh CPU/MMU aggregate report at
  `build/cpu_mmu_complete/cpu_mmu_completion_report.md`.
- `make rtl-frontend-compile` passed all `8/8` configurations after the TLB
  exception-precision changes.
- `make product-mmu-micro-tlb-gate` passed. The product vector corpus now
  covers the nested refill-handler `SYSCALL` into the general vector, BEV to
  EBase transition, invalid classification, and an I-side micro-TLB hit.
  CPU exception redirection remains active for a valid nested WB exception;
  CP0 still preserves EPC/EXL state while already in EXL.
- The earlier current-contract rerun exposed a real `cp0_sweep` firmware
  contract error: the user-mode re-enable path wrote only HWREna bit 29 while
  immediately testing standard RDHWR targets 0..3. The firmware now restores
  `0x2000000F`; fresh direct SoC and UVM runs reach `mailbox=deadbeef` and
  terminate normally. The full signoff is being rerun after this correction.
- URG exclusion checksum/vector warnings remain audit items and are not
  coverage signoff evidence.

The executable selected architecture gates are green. The remaining items are
scope boundaries rather than missing evidence for those gates: full MIPS32
ISA compliance, complete double-precision/IEEE-754 and Linux FPU ABI, per-retire
RTL/QEMU MMU differential, Linux kernel boot with OS-owned page tables,
multicore scheduler/shootdown stress, deterministic replay of all physical
interrupt/device timing, and production DDR/QSPI PHY/JEDEC/device signoff.
DMA v2 event-contract evidence is closed for the captured corpus. SG long-form
data, physical AXI fault injection and reset-in-flight remain open; no full
DMA physical signoff is claimed.

- Linux software TLB refill, page-table ownership beyond the bounded demand
  paging slice, scheduler integration, and multicore end-to-end shootdown.
- MIPS32r2 COP1 double precision beyond the selected pair/conversion slice,
  complete IEEE754/OS ABI implementation, configurable rounding modes,
  precise FPE behavior, and full COP1 reference differential. The new BC1
  compare/branch slice is separately gated, but is not a full COP1 compliance
  claim.
- Fixed-version Buildroot/Linux QEMU boot, RTL boot, deterministic device-event replay, and full architectural retire differential.
- The latest fresh `qemu-system-vic-cpu-differential-gate` run passes 736
  retire records after the VIC replay EPC boundary was aligned to the RTL.
  Source traces contain 737 records on each side; the comparator drops one
  producer-specific asynchronous boundary record. The generic CPU
  subroutine-return/load forwarding bug remains a separate residual and is not
  hidden by this corpus-specific workaround.

### 2026-08-20 execution update

- `make fpu-fpe-double-gate` passes with the fresh real CPU/SoC gate. The
  corpus covers enabled double divide-by-zero, invalid `0/0`, and finite
  overflow; each checks ExcCode 15, one-hot FCSR Cause/Flags, no destination
  pair commit, and ERET recovery.
- The gate intentionally classifies the three sequential vectors from FCSR
  Cause. An exception trace confirmed CP0 receives the faulting PCs `0x38`,
  `0x60`, and `0xa0`; the earlier `cp0_epc=0` observation was a same-edge
  testbench read before the nonblocking CP0 update, not an RTL EPC loss.

### 2026-08-21 execution update

- Added `qspi-vendor-neutral-boot-gate` as the explicit development-boot
  aggregate for both x1 and quad manifest handoff. The fresh x1 and quad
  runs pass the valid image, rejection matrix, and XIP timeout-to-DBE paths.
- `current-contract-signoff` now requires `rtl-frontend-compile`, the QSPI
  vendor-neutral boot aggregate, `ddr-contract-entry-audit`,
  `ecc-secded-gate`, and the existing DDR4 functional aggregate. This makes
  the dependency graph reflect the evidence already required by the current
  contract instead of relying on standalone commands.
- Fresh checks pass: RTL frontend `8/8`, ECC SECDED, and DDR contract entry
  audit. The DDR audit remains intentionally `BLOCKED` for missing physical
  PHY/DFI, DRAM-part, board-timing, and power-good inputs; the audit itself
  exits successfully as a documented external-input boundary.
- The current-contract signoff still does not claim full ISA, Linux boot,
  full RTL/QEMU differential, physical DDR/QSPI, formal/CDC/RDC/lint, or
  synthesis/STA/DFT signoff.

### 2026-08-21 QEMU execution update

- `make isa-implementation-audit` passes with all 19 matrix rows valid and
  explicit full-ISA, double-precision and branch-likely residual markers.
- Rebuilt the patched QEMU 9.2 `mipsel-softmmu` binary successfully. The
  build found the required GLib and Pixman dependencies and produced
  `qemu-system-mipsel` for the `mips32-soc-ref` machine.
- Added an input-hash stamp to `scripts/qemu/build_mips32_soc_ref.sh` so the
  five-child QEMU aggregate reuses an unchanged patched binary instead of
  reconfiguring/recompiling QEMU for every child gate.
- Fresh `make qemu-system-current-contract-gate` passes all five children:
  peripheral contract, DMA v2 model, QSPI, DDR behavioral window, and retire
  capture. This remains selected system-mode evidence; it does not close
  full RTL/QEMU per-retire differential, full ISA/MMU, Linux boot, or
  physical device timing.

### 2026-08-22 QEMU differential harness update

- The new selected differential aggregate reached DI/EI but exposed a harness
  timeout, not an RTL mismatch: the cold VCS compile/elaboration consumed
  almost the entire historical 30-second `RTL_TIMEOUT`, and the command exited
  with status 124 despite the existing trace corpus being valid.
- Increased the generic differential harness default timeout to 120 seconds;
  the value remains overridable per corpus. This accounts for compile and
  elaboration time without changing comparison rules or accepting stale logs.
- The next rerun identified the companion capture limit: QEMU retire capture
  still defaulted to 10 seconds, so the DI/EI child could return 124 before a
  fresh trace was written. Increased that default to 30 seconds, retaining
  `QEMU_TIMEOUT` override and mailbox-based normal completion.

## Non-claims

The selected L1 multi-response gate and selected QEMU system differential do
not prove all hit-under-miss/error/reset combinations, full ISA/FPU compliance,
Linux boot, or full MMU/QEMU/RTL differential. Default blocking behavior
remains the compatibility baseline.

### 2026-08-22 closure rerun

- Fresh ordinary QEMU system VIC retire differential passed. The previously
  fixed CPU IRQ replay preserves `Cause.IP2` until the RTL-compatible VIC ACK;
  this is recorded separately from the full ISA/Linux claims.
- Fresh UART external RX SoC and UART CTS SoC gates passed. Fresh DMA
  reset-in-flight and QEMU system peripheral-contract gates also passed.
- Fresh `current-contract-signoff` completed every functional stage: RTL
  frontend, micro-TLB/page-scale checks, L1 nonblocking error/reset checks,
  SVA, QSPI/DDR/ECC gates, Phase 2 `16/16`, Phase 3A `8/8`, Phase 3B `1/1`,
  Phase 3C `1/1`, and 10/10 stress seeds. The signoff failed only at the
  explicit coverage threshold stage; no threshold or exclusion semantics were
  changed. Evidence is under
  `build/signoff/current_contract_continue/`.
- Fresh threshold residuals are UVM SCORE `69.72%`, COND `95.18%`, TOGGLE
  `61.56%`, FSM `37.50%`, BRANCH `54.44%`; Product CPU/CP0 SCORE `68.80%`,
  LINE `87.20%`, TOGGLE `64.20%`, FSM `36.97%`, BRANCH `55.75%` against the
  current `99%` policy. This remains an honest coverage blocker, not a
  functional RTL failure.

### 2026-08-23 CPU performance counter APB slice

- Added `apb_perf_counters` at `0x4000_C000`, connected through the real
  `mips_cpu -> mips_core -> soc_core_subsystem -> mips_soc_impl ->
  soc_peripheral_subsystem -> axi2apb_bridge` path.
- The window exposes cycle, retire, I-cache miss, D-cache miss, branch
  mispredict, MDU stall, and version registers. It is read-only and does not
  alter the existing CP0 ABI or counter ownership.
- The standalone counter gate remains `make perf-counters-gate`. The new
  `make perf-cpu-gate` enables `SOC_PERF_COUNTERS=1`, runs real CPU firmware,
  and checks version plus monotonic cycle/retire deltas.
- This closes the bounded CPU performance-counter observability contract. It
  is not a CoreMark/Dhrystone performance signoff, CPI accuracy claim, or
  commercial performance model.

### 2026-08-23 VIC CPU nested interrupt slice

- Added a dedicated `vic_nested` firmware gate. Source 9 is accepted first,
  the handler clears EXL and re-enables IE, then higher-priority source 8 is
  delivered through a second real exception entry and acknowledged before
  the outer handler resumes and clears source 9.
- The gate checks the observed `9 -> 8 -> 9` sequence, nested progress, and
  zero ACTIVE state after both acknowledgements. This closes one bounded
  re-entrant CPU/VIC path without claiming arbitrary nesting depth or a full
  operating-system interrupt ABI.

### 2026-08-23 CPU performance workload observation slice

- Added `perf_workloads` firmware and `make perf-workloads-gate`. The real
  CPU/APB counter path now emits four repeatable workload records covering
  sequential, strided, branch-mixed and MDU-heavy activity.
- The gate checks the counter version, success marker and exactly four
  workload records. Each record includes cycle/retire and cache/branch/MDU
  deltas, providing a configuration-comparison baseline.
- Fresh VCS evidence passed with version `0x50430001`: sequential
  `cycles=0x17bb/retire=0x201`, strided `0x2487/0x401`, branch-mixed
  `0x1f90/0x401`, and MDU `0x1c1/0x40`; all four records were emitted and the
  firmware reached `REGRESSION_TEST_SUCCESS`.
- No official CoreMark/Dhrystone/STREAM source is present in the repository.
  The available MIPS cross compiler is sufficient to build this firmware, but
  this slice remains an observation harness only; standard benchmark and
  performance signoff remain open.

### 2026-08-23 Opt-in FPU scheduler context slice

- The scheduler context image now includes all 32 FPRs and FCSR in addition
  to the existing PC/SP/Status/ASID/GPR state. `mips_cpu` exports the live
  FPR/FCSR image on save and loads the selected task image on restore; it no
  longer clears FPU state on every task switch.
- `make fpu-context-gate` passes with `SOC_FPU_ENABLE=1`. The integration
  test checks task-0 FPR[1:2]/FCSR preservation and task-1 FPR[1:2]/FCSR
  restoration, and `make rtl-frontend-compile` remains `8/8`.
- This closes the bounded hardware context-transfer contract. Linux lazy-FPU
  ownership, signal frames, ABI save area, preemption policy and full COP1
  compliance remain open.

### 2026-08-24 Hardware walker four-page-size extension

- Added opt-in `SOC_HARDWARE_WALKER_PAGE_MASK`, defaulting to 4KB and
  supporting 16KB (`0x0003`), 64KB (`0x000f`) and 256KB (`0x003f`).
- The walker now derives the L2 PTE address and physical page offset from the
  selected mask, rejects misaligned large-page PFNs, and the CPU refill path
  carries the same PageMask and MIPS even/odd selector into the TLB.
- `make page-table-walker-page-sizes-gate` and
  `make cpu-hardware-walker-page-sizes-gate` pass all four parameterized
  instances. Default TLB refill, CPU I/D walker integration, TLB/micro-TLB
  regressions and full RTL frontend compile also pass.
- This closes only the four-page-size hardware walker contract. General
  demand paging, OS page-table ownership, Linux VM, long-term shootdown and
  complete privileged/MMU compliance remain open.

### 2026-08-23 L1 nonblocking CPU stress rerun

- Fresh `make l1-nonblocking-cpu-multi-gate` passed through the real
  `mips_core -> L1 nonblocking D-cache -> AXI` path.
- Fresh `make l1-nonblocking-cpu-stress-gate` passed all three requested seeds
  (`11`, `29`, `47`); each run reached `REGRESSION_TEST_SUCCESS` and exercised
  the testbench AXI mid-flight reset sequence.
- Evidence is under
  `build/soc_test/l1_nonblocking_cpu_multi/` and
  `build/soc_test/l1_nonblocking_cpu_stress/`, including the aggregate
  `l1_nonblocking_cpu_stress_report.md`.
- This strengthens repeatability for the selected smoke corpus only. It does
  not close arbitrary error/reset timing, nonblocking maintenance ordering,
  coherence, default-path switching, or physical DDR failure behavior.

### 2026-08-23 QEMU current-contract rerun

- Fresh `make qemu-system-current-contract-gate` passed all five children:
  peripheral contract, DMA v2 model, QSPI, behavioral DDR, and retire capture.
- The patched `mips32-soc-ref` binary was reused from the input-hash-validated
  build at `build/deps/src/qemu-9.2.0/build-mipsel-softmmu/`.
- Evidence is under `build/isa_ref/qemu_system_current_contract/`.
- This remains selected QEMU system-mode contract evidence; full RTL/QEMU
  per-retire differential, full ISA/MMU, Linux boot, and physical device
  timing remain open.

### 2026-08-23 QEMU selected differential rerun

- Fresh `make qemu-system-selected-differential-gate` passed the aggregate:
  ISA R2, branch-likely, exceptions, break/traps, DI/EI/WAIT, BD/EPC,
  unaligned memory, peripheral/VIC, and opt-in FPU single/double/CU1.
- Evidence is under `build/isa_ref/qemu_system_selected_differential/`, with
  RTL and QEMU retire streams plus child logs and completion reports.
- This confirms the selected bare-metal mailbox-boundary corpus only. Full
  MIPS32 compliance, complete privileged/MMU differential, IEEE-754/OS FPU
  ABI, Linux boot and physical device signoff remain open.

### 2026-08-24 Linux boot dependency audit and source provenance

- `make linux-boot-dependency-gate` now recognizes the project-built
  `qemu-system-mipsel` custom-machine binary and the three installed MIPS
  cross-tools.
- The gate initially reported the absent external sources. The project now
  provides `tb/linux_boot/sources.lock` and
  `tb/linux_boot/fetch_sources.sh`, pinning official Linux v6.6 commit
  `ffc253263a1375a65fa6c9f62a893e9767fbebfa` and U-Boot v2024.10 commit
  `f919c3a889f0ec7d63a48b5d0ed064386b0980bd`. `make
  linux-boot-fetch-sources linux-boot-dependency-gate` passes after marker
  verification. This closes source provenance only; Linux-specific platform
  support, DTB/U-Boot image flow and a real boot regression remain open.

### 2026-08-23 QEMU linux-user build closure

- `make qemu-linux-user` now builds the official QEMU 9.2 `mipsel-linux-user`
  target at `build/deps/src/qemu-9.2.0/build-mipsel-linux-user/qemu-mipsel`.
- The project patch script handles the host `sched_attr` header collision and
  keeps system-only SRS helpers out of linux-user, including the shared
  microMIPS decoder cases. The build completed and `qemu-mipsel --version`
  reports `9.2.0`.
- `make linux-boot-dependency-gate` recognizes both QEMU binaries and remains
  blocked only by the absent `third_party/linux` and `third_party/u-boot`
  sources. Linux boot, kernel/user ABI, and RTL/QEMU Linux differential remain
  open.

### 2026-08-23 ISA R2 control/special sweep extension

- `make isa-r2-gate` passes after adding real CPU firmware checks for
  `BITSWAP`, `JR.HB`, `JALR.HB`, and `EHB`; the run emits no
  `ISA_R2_SPECIAL_FAIL`, `ISA_R2_EXT_INS_FAIL`, or RI summary.
- The decoder now validates the fixed fields of JR/JALR and accepts the R2
  hazard-barrier form (`sa=16`) on the same in-order control path. Ordinary
  JR/JALR remain covered by the same gate.
- This closes an implemented-subset evidence gap only. Full MIPS32
  compliance, privileged/MMU differential, and complete FPU/OS semantics
  remain open.

### 2026-08-23 QEMU BITSWAP R2 differential repair

- The first system differential run exposed a real reference-model mismatch:
  QEMU 9.2 routed the legacy R2 BITSWAP encoding through its R6-only decoder
  and raised RI while the RTL executed it.
- The project QEMU build helper now applies the local R2 decode override with
  an explicit source-tree edit and requires the `SOC_REF_BITSWAP_R2` marker
  before accepting the cached build as current. This also fixes the prior
  false cache-hit path for a non-Git extracted QEMU tree.
- Fresh `make qemu-system-isa-r2-differential-gate` passes with
  `TRACE_COMPARE_PASS records=375` and `QEMU system RTL retire differential: PASS`. The evidence is a selected
  ISA R2 implemented-subset corpus through the mailbox boundary; it does not
  extend claims to full ISA, privileged/MMU, FPU, Linux, or product signoff.

### 2026-08-23 current-contract coverage rerun and file-list audit

- A fresh `make current-contract-signoff` reran the RTL frontend, current
  contract gates, Phase 2/3/3B/3C coverage, and ten-seed stress regression.
  The functional stages and all ten stress seeds passed.
- The final aggregate remains `FAIL` at the unchanged 99% code-coverage
  threshold: UVM SCORE 61.74% and product CPU/CP0 SCORE 59.70%, with branch,
  toggle and FSM metrics also below threshold. This is not coverage signoff;
  exclusions were refined from the fresh VDBs and the residual threshold gap
  remains open.
- Two explicit subsystem gate file lists were missing the newly instantiated
  `apb_perf_counters` RTL and were fixed in the QSPI status and DDR4 PIC
  integration runners. The WDT peripheral runner also required the APB MMU/
  DDR status and allocator/shootdown dependencies; those were corrected too.
  `make soc-filelist-audit` now passes, and the WDT gate reaches
  `REGRESSION_TEST_SUCCESS wdt_peripheral`.

### 2026-08-23 Hardware walker refill handshake closure

- Fixed `mips_page_table_tlb_refill` so a successful walker response always
  creates a held TLB write transaction, including when `tlb_wr_ready` is
  already high in the response cycle. The previous condition could consume
  a response without exposing `tlb_wr_valid` to the TLB owner.
- Added a permanently-ready consumer case to the TLB refill unit test.
  `make page-table-tlb-refill-gate` passes, as do
  `make page-table-walker-gate`, the CPU hardware-walker integration gate,
  and `make rtl-frontend-compile` (8/8).
- This closes a valid/ready timing hole in the bounded opt-in hardware walker
  integration. The walker remains a two-level, 4KB-only, one-outstanding-read
  implementation; Linux VM ownership, general demand paging, and complete OS
  shootdown semantics remain open.

### 2026-08-23 QEMU system-mode MMU retire differential closure

- Added the custom-machine `software-mmu-guest` callback consumed by the
  patched QEMU TLB/exception helper, fixing software-managed TLB misses to
  enter the RTL-compatible `0x80000180` general exception vector.
- Widened the QEMU reference TLB to 64 entries only for this opt-in guest;
  the default `24Kc`/identity-TLB path is unchanged. This matches the RTL
  64-entry TLB and prevents firmware indices 16/17 from aliasing entry 0.
- Fresh `make qemu-system-mmu-refill-differential-gate` passes with
  `TRACE_COMPARE_PASS records=3288`; RTL and QEMU both report
  `mmu_refill: PASS` and the mailbox completion marker. Larger page sizes,
  OS-owned VM, multicore shootdown, full privileged/MMU compliance, and Linux
  remain open.

### 2026-08-23 QEMU system MMU PageMask architectural boundary

- Added `make qemu-system-mmu-pagemask-gate`. The custom `mips32-soc-ref`
  machine now has an explicit opt-in `software-mmu-bootrom-guest=on` mode that
  routes software-managed TLB misses to the RTL-compatible boot-ROM PageMask
  handler.
- The gate passes 4KB, 16KB, 64KB and 256KB PageMask phases with ASIDs 4-7,
  even/odd halves, non-zero offsets, PFN folding and mailbox completion.
- Evidence is under
  `build/isa_ref/qemu_system_mmu_pagemask_differential/`. The boot-ROM
  testbench now emits the shared trace with `TB_RETIRE_TRACE=1`, and the gate
  passes `TRACE_COMPARE_PASS records=276`. The closure required a real RTL fix:
  address exceptions now update EntryHi.VPN2 while preserving ASID, matching
  QEMU and the MIPS refill contract. `cpu-cp0-gate` and `tlb-invalidate-gate`
  also pass after the change. This item is now `SYSTEM_DIFFERENTIAL` for the
  bounded four-page-size firmware corpus; Linux VM ownership, multicore
  shootdown and full privileged/MMU compliance remain open.

### 2026-08-23 QEMU system MMU process-pressure RTL differential

- Reused the standalone retire bind for `tb_product_mmu_process_pressure` and
  ran the same firmware through RTL and `mips32-soc-ref`.
- `make qemu-system-mmu-process-pressure-gate` passes with
  `TRACE_COMPARE_PASS records=1555`; the RTL side reports
  `REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8`.
- The comparison covers four software ASIDs, distinct PFNs, context reuse,
  dynamic TLB shootdown, wired mapping retention and post-shootdown refills.
  This upgrades the previous pass-boundary evidence to bounded
  `SYSTEM_DIFFERENTIAL`; OS scheduler/page-table ownership, multicore IPI
  shootdown and Linux VM remain open.

### 2026-08-24 QEMU system MMU context/shootdown differential

- `make qemu-system-mmu-contract-gate` passes with a fresh RTL/QEMU retire
  comparison and the context completion report.
- The gate covers ASID-specific refill, ASID reuse, wired APB mapping, sticky
  invalidate+done status, shootdown ACK and the required post-shootdown refill.
- The mismatch exposed a real QEMU model defect: ACK previously flushed only
  QEMU's translated host cache, leaving the guest-installed ASID TLB entry
  architecturally valid. The custom machine now marks matching non-global
  entries invalid at ASID-scope ACK and then flushes the translated cache;
  global/wired entries are retained.
- This closes the bounded single-core context differential boundary. OS page
  table ownership, scheduler integration, multicore IPI shootdown, Linux VM,
  and complete privileged/MMU compliance remain open.

### 2026-08-24 QEMU system MMU OS page-table pressure differential

- Added an opt-in `SOC_MMU_OS_PRESSURE` workload and
  `make qemu-system-mmu-os-pressure-gate`.
- The workload owns three independent root/L2 page tables, switches ASID
  contexts over the same virtual pages backed by task-specific PFNs, and
  performs an explicit current-task TLB invalidation followed by demand refill.
- RTL and `mips32-soc-ref` retire traces compare successfully. RTL evidence is
  `mmu_os_pressure: PASS`, with `refills=0x15`, six allocations and two pages
  allocated for each of the three tasks.
- This closes bounded single-core OS-style page-table ownership pressure. A
  Linux VM, production allocator/scheduler ABI, multicore shootdown and full
  privileged/MMU compliance remain open.

### 2026-08-24 L1 nonblocking real-CPU regression refresh

- Re-ran `l1-nonblocking-cpu-multi-gate`, the three-seed reset-in-flight stress,
  the two-response error/reset gate and maintenance compatibility gate.
- All passed on the real opt-in `mips_core -> l1_cache_nb_cpu_axi -> AXI`
  path. This refreshes the existing 2-MSHR/ROB/error/reset evidence; it does
  not close the explicitly retained arbitrary multi-error, full coherence,
  nonblocking maintenance protocol or default-path switching contracts.

### 2026-08-24 Dual-core MMU shootdown target ACK

- Corrected the dual-core SoC IPI completion path so a sender no longer ACKs
  its own invalidate issue pulse. Each direction now registers the target-side
  invalidate event and returns the latched target/generation one cycle later.
- `make dual-core-soc-gate` passes with the opt-in dual-core firmware, and
  `make mmu-ipi-shootdown-pressure-gate` passes its repeated request, stale
  generation, busy re-entry and missing-target timeout cases. The complete
  default RTL frontend compile remains `8/8` passing.
- This closes the target-acceptance handshake at the current dual-core RTL
  contract boundary. It does not claim a Linux scheduler/page-table owner,
  multicore MESI/directory protocol, or full OS shootdown policy.

### 2026-08-24 L1 nonblocking real DDR window

- Added opt-in `SOC_L1_NONBLOCKING_DDR_ENABLE`. The CPU-facing adapter now
  recognizes the translated DDR physical window `0x0800_0000..0x0fff_ffff`
  while retaining the established SRAM-only default.
- Added `l1_ddr_nonblocking` firmware and `make l1-nonblocking-ddr-gate`.
  The real CPU/L1/AXI/DDR4-controller path passes two stores, same-line
  store-merge/readback, a second-line refill and a final cache hit.
- `make l1-nonblocking-cpu-multi-gate` and `make rtl-frontend-compile` also
  pass after the extension. This closes DDR-window integration for the
  bounded nonblocking L1 contract; physical DDR PHY timing, full coherence,
  maintenance ordering and Linux cache ABI remain open.

### 2026-08-24 Nonblocking L1/QEMU differential closure

- Added a custom `qemu_system_l1_ddr` bare-metal workload to exercise the same
  DDR addresses through the QEMU `mips32-soc-ref` machine and the RTL CPU.
- The first probe exposed a real bug: while an IF-side stall held EX/MEM, the
  ROB allocation predicate reallocated the held bundle every cycle. The fix
  separates pre-ROB stall state and binds allocation to the actual EX/MEM
  advance condition, while preserving the tagged-load address-handshake
  exception.
- `make qemu-system-l1-ddr-differential-gate` now passes with
  `QEMU system RTL retire differential: PASS`. The custom guest covers two
  stores, same-line data, a second-line refill, a final hit and mailbox
  completion through the opt-in CPU/L1/AXI/DDR path.
- This closes the bounded nonblocking L1 DDR RTL/QEMU differential contract;
  arbitrary multi-error, full coherence, maintenance ordering and Linux cache
  ABI remain open.

### 2026-08-24 Hardware page-table walker backpressure/reset closure

- Extended `tb/unit/mmu/tb_page_table_walker.sv` with stalled L1/L2 memory
  responses and reset-in-flight cases. The test checks that `mem_valid`
  remains asserted until `mem_ready`, and that reset clears the outstanding
  walk, response, fault and request ownership state.
- `make page-table-walker-gate`, `make page-table-tlb-refill-gate`,
  `make cpu-hardware-walker-gate`, and `make cpu-dside-hardware-walker-gate`
  all pass on the current RTL.
- This closes the valid/ready and reset-in-flight behavior of the existing
  bounded hardware walker. It remains a two-level, single-outstanding-read
  implementation; arbitrary demand paging, OS page-table ownership, Linux VM
  and complete privileged/MMU compliance remain open.

### 2026-08-24 LL/SC reservation boundary closure

- Added the exception-boundary rule in `mips_cpu`: reset, context restore,
  accepted exception/interrupt flush, ordinary completed stores and peer line
  notifications clear the reservation.
- The firmware gate now verifies `LL -> SYSCALL -> ERET -> SC=0`, while the
  dual-core coherency gate verifies peer notification invalidation and no
  memory write from the failed `SC`.
- The coherency testbench synchronization was corrected to wait for the
  fourth reservation (the dedicated peer test); injecting after the third
  reservation tested a later LL and could falsely report `SC=1`.
- Passing evidence: `make llsc-gate llsc-coherency-gate
  dcache-coherency-gate rtl-frontend-compile`.
- This closes the bounded reservation lifecycle contract only. Full MIPS
  memory ordering, arbitrary atomic interleavings, MESI/directory coherency
  and Linux atomic ABI remain open.

### 2026-08-24 LL/SC interrupt-boundary directed evidence

- Added `make llsc-interrupt-boundary-gate`, which drives an external interrupt
  through the CPU's real CP0 interrupt acceptance path with a pre-existing
  LL reservation.
- The gate passes with `REGRESSION_TEST_SUCCESS llsc_interrupt_boundary`,
  confirming `interrupt_accept` uses the common exception flush and clears the
  reservation before handler/ERET activity.
- This remains a directed lifecycle slice; nested interrupts, architectural
  memory ordering and full atomic/coherency protocol behavior are open.

### 2026-08-24 MMU/FPU/selected differential refresh

- Fresh `make mmu-refill-gate` passes the bounded software-owned two-level
  demand-refill workload with `refills=7`, `demand_faults=6`, `page_allocs=4`
  and `permission_faults=1`.
- Fresh `make qemu-system-mmu-os-pressure-gate` passes RTL/QEMU retire
  comparison for the three-ASID OS-style page-table pressure workload.
- Fresh `make fpu-fpe-double-gate` passes the real opt-in CPU/SoC double FPE
  slice for divide-by-zero, invalid and overflow; each reaches ExcCode 15 and
  suppresses the destination pair commit.
- Fresh `make qemu-system-selected-differential-gate` passes the selected
  QEMU system-mode RTL retire corpus. This is evidence for the frozen
  implemented subset only; it does not close full MIPS32 ISA, full privileged
  MMU, complete IEEE-754/FPU ABI, Linux VM/boot, or product signoff.

### PREFX system-mode differential: COMPLETE (implemented-subset extension)

- The RTL decoder accepts MIPS32 R2 COP1X `PREFX` as an ordered no-op even
  when `SOC_FPU_ENABLE=0`; other COP1X arithmetic remains FPU-gated.
- `make isa-r2-gate` passes with `ri=0`.
- The QEMU system-mode retire differential passes with `TRACE_COMPARE_PASS`
  for the same guest and RTL retire trace.
- The QEMU helper repairs partially patched build trees and uses
  `ISA_MIPS_R2` for this no-FPU instruction. This closes only the PREFX
  implemented-subset evidence; full ISA/QEMU, privileged/MMU, IEEE-754/FPU
  ABI and Linux boot remain open.

### SYNCI system-mode differential: COMPLETE (selected R2/cache slice)

- The existing ISA R2 sweep now executes `SYNCI 0(base)` on the real RTL
  cache-maintenance path.
- `make isa-r2-gate qemu-system-isa-r2-differential-gate` passes with
  `CPU_CP0_SUMMARY ... ri=0` and `TRACE_COMPARE_PASS`.
- This closes only the selected SYNCI instruction/differential slice; full
  cache ordering, Linux cache ABI, privileged ISA and full ISA compliance
  remain open.

### 2026-08-24 architecture aggregate refresh

- `make p1-current-complete` passes the current RTL/simulation extension bundle,
  including frontend variants, dual-core coherency stress, walker/refill,
  CPU/MMU, ISA R2, PageMask and DDR4 functional gates.
- `make qemu-system-current-contract-gate` passes peripheral, DMA v2, QSPI,
  DDR behavioral and retire-capture children.
- `make qemu-system-selected-differential-gate` passes the selected RTL/QEMU
  system retire corpus, including the refreshed ISA R2 guest.
- These are current-contract and selected-corpus results only. Full ISA,
  privileged/MMU/Linux VM semantics, complete IEEE-754/FPU ABI, MESI/directory
  coherency, physical DDR/QSPI timing and formal/CDC/RDC/lint signoff remain
  open.

### 2026-08-24 FPU inexact enabled exception

- RTL/SoC gate: `make fpu-fpe-inexact-gate` PASS.
- Contract: enabled `CVT.W.S 1.5` raises precise ExcCode 15, sets Cause/Flags
  Inexact, and does not commit the FPR destination.
- QEMU model: custom machine capture reports `FCSR=0x00001084`; the project
  QEMU build now carries the sticky-Flags-on-enabled-FPE patch.
- Differential: `make qemu-system-fpu-fpe-inexact-differential-gate` passes with
  `TRACE_COMPARE_PASS records=43` in
  `build/isa_ref/qemu_system_fpu_fpe_inexact_differential_v2/`. The dedicated
  run directory avoids reusing an older VCS elaboration compiled without the
  opt-in FPU define.

### 2026-08-24 differential gate diagnostics and storage hygiene

- `run_qemu_system_retire_capture_gate.sh` now records the exact QEMU command
  in `qemu_command.txt` and reports a non-zero/timeout status together with
  stdout and stderr paths. This is infrastructure observability only; it does
  not change the trace comparator or completion semantics.
- Standalone capture with the same firmware and QEMU binary remains reproducible
  at 44 instruction events and 44 retire records; the preserved differential
  evidence above remains the functional result for this slice.
- Old debug/retry trace directories were removed only after checking their
  names and completion status; passing evidence directories were retained.

### 2026-08-24 double-precision FPE Inexact slice

- Added the opt-in `fpu_fpe_double_inexact` firmware workload. It executes
  `CVT.W.D 1.5` with only Inexact enabled, checks ExcCode 15, FCSR
  `0x00001084`, and no commit to either word of the destination pair.
- `make fpu-fpe-double-inexact-gate` passes on the real CPU/SoC path.
- An independent system-mode QEMU capture produces 50 retire records; strict
  RTL/QEMU comparison passes with `TRACE_COMPARE_PASS records=49`.
- The generic wrapper can still observe a host timeout after QEMU has emitted
  complete artifacts. This remains an infrastructure residual; it does not
  weaken the comparator or upgrade the slice to full IEEE-754/FPU ABI closure.

### 2026-08-24 double-precision FPE Underflow boundary

- Added `fpu_fpe_double_underflow`, using minimum positive double subnormal
  times `0.5` with only Underflow enabled.
- The first real CPU run exposed host-real flush-to-zero behavior. RTL now
  preserves the Underflow classification from IEEE operand fields when the
  simulator result is zero; the rerun passes `REGRESSION_TEST_SUCCESS` and
  verifies no double-pair commit.
- This remains an RTL behavioral boundary slice. The QEMU underflow reference
  path and complete tininess/inexact/IEEE-754 policy are still open.

### 2026-08-24 CPU load-return and FPU context recheck

- `make cpu-load-return-gate rtl-frontend-compile` passes. The real default
  blocking CPU/SoC guest performs an MMIO load in a helper and consumes the
  returned value at the first useful caller instruction after the delay slot;
  the pass mailbox proves the bounded load-use/return path.
- `make fpu-context-gate` passes with
  `REGRESSION_TEST_SUCCESS cpu_scheduler_integration`. The opt-in scheduler
  integration preserves task-0 FPR/FCSR state and restores task-1 state.
- These results do not close arbitrary multi-outstanding load forwarding,
  Linux lazy-FPU or signal-frame ABI, full ISA compliance, or OS scheduling
  semantics. The existing QEMU double-underflow differential remains open.

### 2026-08-24 VIC full-source priority differential

- Added `vic_full_sources` firmware and the opt-in
  `vic-full-sources-gate`. The real RTL path passes all 32 software-pending
  sources, 4-bit priorities, highest-priority selection, lower-ID tie-break,
  ACTIVE/RUNNING_PRIO state, ACK/W1C draining and source-31 enable masking.
- `qemu-system-vic-full-sources-differential-gate` compares the same guest
  against `mips32-soc-ref` and passes `TRACE_COMPARE_PASS records=1166`.
- This closes the bounded 32-source interrupt-controller contract only;
  arbitrary nested depth, multicore ownership, external electrical timing,
  Linux IRQ ABI and formal interrupt proof remain open.

### 2026-08-24 D-cache parity/CacheErr slice

- `make dcache-parity-gate` passes with `REGRESSION_TEST_SUCCESS dcache`.
- The gate injects tag and data-line parity faults through simulation-only
  ports, checks `cpu_data_ok` suppression plus `cpu_cache_error`, and verifies
  recovery after clearing the injection.
- Residual: no SECDED correction, multi-bit ECC, L2 propagation, physical
  reliability model, or OS cache-error policy is closed by this slice.

### 2026-08-24 QEMU double-underflow differential and capture guard

- The QEMU system retire capture now rejects boundedness failures before the
  JSONL converter materializes records, with event/state/count and byte caps;
  this prevents the previous pathological guest loop from exhausting host
  memory.
- The underflow guest was corrected to encode `$f3` correctly and to enable
  Underflow after operand setup. The custom QEMU reference raises the same
  bounded Underflow|Inexact FCSR contract as RTL.
- `make qemu-system-fpu-fpe-double-underflow-differential-gate` passes with
  `QEMU system RTL retire differential: PASS`.
- Residual: this is a selected FPU boundary only; complete IEEE-754 tininess,
  full COP1 compliance, OS FPU ABI, Linux boot and formal signoff remain open.

### 2026-08-24 QEMU DMA fault classification

- Added opt-in `dma-fault-mode=1/2` properties to `mips32-soc-ref` to force
  vendor-neutral DMA AXI read/write response failures while leaving mode `0`
  unchanged.
- `make qemu-system-dma-fault-gate` passes both firmware cases with distinct
  `ERR_AXI_READ=2` and `ERR_AXI_WRITE=3`, channel IRQ and PIC propagation, and
  DONE/ERR W1C re-arm. The QEMU DMA `IRQ_STATUS` readback is part of this
  evidence.
- This closes the reference-model fault classification slice only. Physical
  DDR/AXI timing, reset-in-flight, arbitrary multi-channel error interleavings
  and production DMA signoff remain open.

### 2026-08-24 QEMU GPIO input and timer IRQ model

- Added the opt-in `gpio-input` machine property and mixed-direction GPIO
  readback to `mips32-soc-ref`; `GPIO_DIR=0` now observes the configured
  external input value while output bits retain the driven value.
- Corrected timer source mapping to VIC source 2, honored timer interrupt
  enable, preserved sticky INT state when disabling the timer, implemented
  periodic reload behavior, and added APB INT W1C clearing. Legacy DMA and
  QSPI source mappings now match the RTL source vector as well.
- `make qemu-system-gpio-input-gate` passes the GPIO input, timer IRQ, timer
  W1C and peripheral-model checks. The existing
  `qemu-system-peripheral-differential-gate` also passes after the mapping
  correction.
- This closes the selected QEMU peripheral-model slice only; external GPIO
  synchronization, physical clock/timer accuracy and board-level I/O remain
  open.

### 2026-08-24 QEMU DDR fault/status model

- Added opt-in `ddr-fault-mode=1/2` properties to `mips32-soc-ref`, producing
  distinct sticky AXI (`0x00040004`) and geometry (`0x00040005`) error codes
  with the APB status error bit set.
- `make qemu-system-ddr-fault-gate` passes both cases, verifies APB W1C
  clearing, and continues through cached and uncached DDR window accesses.
- Default `ddr-fault-mode=0` remains the READY/no-error behavior. Physical
  PHY/JEDEC fault timing, ECC injection, refresh scheduling and board-level
  DDR signoff remain open.

### 2026-08-24 RDHWR implemented-subset closure

- `make cp0-rdhwr-gate` passes on the real CPU/SoC path.
- The gate covers `RDHWR $0/$1/$2/$3/$29`, HWREna-disabled user CpU
  exceptions, re-enabled user-mode reads, and UserLocal/TLS read/write.
- This closes only the bounded MIPS32 R2 RDHWR slice. Full privileged ISA,
  dynamic Count semantics, OS TLS/scheduler ABI and Linux boot remain open.

### 2026-08-24 cache FSM SVA integration

- Bound `cache_state_props.sv` to the default blocking D-cache and included it
  in the `SVA_ENABLE` SoC compile path.
- The checker covers known FSM state and a 4096-cycle refill completion bound;
  the bound includes legal SoC backpressure and is verified by `make sva-gate`.
- The SVA runner now treats the checker error text as a failure marker. This
  remains simulation assertion evidence, not formal/CDC/RDC/lint signoff.

- The unified SVA path also binds `mips_page_table_walker` for state-known,
  request/memory handshake hold and one-cycle response properties. The default
  SoC smoke passes; translation semantics remain in the directed walker gates.

- The unified SVA SoC compile also enables `vic_priority_checker` and its bind;
  the smoke run passes without a priority/vector/pending mismatch. This does
  not claim a formal interrupt-priority proof.
# 2026-08-24 execution update: SPECIAL3 ALIGN

- Added RTL decode and ALU support for MIPS32r2 `ALIGN` byte positions 0..3.
- Added true source-register hazard tracking for SPECIAL3 merge operations and
  a firmware sweep with independent expected results:
  `AABBCCDD`, `BBCCDD11`, `CCDD1122`, `DD112233`.
- Tightened `tb/soc_test/run_isa_r2_gate.sh` so `ISA_R2_SPECIAL_FAIL` is a
  hard failure; the gate passes with the current RTL.
- Fixed the QEMU system capture wrapper to remove run-owned event/state files
  before every invocation, so a timeout cannot reuse stale QEMU events.
- Added the project QEMU 9.2 patch that selects the MIPS32r2 32-bit ALIGN
  generator for the legacy SPECIAL3 encoding; upstream QEMU routes this
  encoding through the MIPS32r6-only path on `24Kc`.
- Fresh `make qemu-system-isa-r2-differential-gate` now passes with
  `TRACE_COMPARE_PASS records=454`, including all four ALIGN positions and
  the WSBW retirement result. The custom machine's bare-metal CP0 PRId and
  Config1 values are aligned with the RTL contract.
  Full ISA, privileged/MMU and Linux differential remain open.

### 2026-08-27 execution update: WSBW and differential gate integrity

- Added MIPS32 R2 `WSBW` decode/ALU support and a firmware assertion covering
  the architectural halfword swap result.
- Added the corresponding QEMU 9.2 custom-machine patch and included it in
  the build input hash/marker checks. The project build uses `git apply` from
  the repository root because the vendored QEMU source tree is not an
  independent worktree.
- Corrected the custom-machine bare-metal CP0 identity (`PRId=0x00019300`)
  and cache geometry (`Config1=0xfe231180`) to match the actual RTL retire
  contract.
- Fixed the differential wrapper to remove the prior completion report before
  a run. A failed comparator can therefore no longer leave an old PASS report
  that is mistaken for current evidence.
- Fixed an idempotence predicate that repeatedly inserted the weak IRQ replay
  declaration into the generated QEMU source. This removes the repeated
  declaration growth that had increased build memory and log volume.
- Fresh evidence: `make qemu-system-isa-r2-differential-gate` passes with
  `TRACE_COMPARE_PASS records=454`.

### 2026-08-24 QEMU UHI/DTB handoff

- Added opt-in opaque DTB loading to `mips32-soc-ref`. The machine validates a
  1..64 KiB blob, places it below the guest RAM limit, and initializes reset
  registers using the MIPS UHI contract (`a0=-2`, kseg0 `a1`).
- `make qemu-system-uhi-dtb-gate` passes with the guest checking the FDT magic
  and reaching the QEMU success mailbox. The completion report is written to
  `build/linux_boot/uhi_dtb/completion_report.md`.
- This closes only the QEMU handoff boundary. A SoC-specific Linux DTS,
  U-Boot/QSPI image loading, and RTL system-mode Linux differential remain
  open.
### 2026-08-25 Linux kernel-to-userspace marker

- Added the opt-in `make linux-boot-build-gate` flow: pinned Linux v6.6
  `32r2el_defconfig`, project DTS, little-endian initramfs assembly and QEMU
  `mips32-soc-ref` UHI/DTB boot.
- The gate passes the kernel-to-userspace marker. `qemu_stdout.log` contains
  the Linux version, `Run /init as init process`, and
  `MIPS32_SOC_LINUX_BOOT_SUCCESS`.
- This does not close product Linux boot. U-Boot, real QSPI/DDR boot, RTL
  Linux differential, and OS-owned VM/shootdown remain open.

### 2026-08-25 QEMU architecture closure aggregate

- Added the serial `make qemu-system-architecture-closure-gate` entry point.
- The aggregate passes the current QEMU peripheral contract, selected
  ISA/FPU/privileged and peripheral RTL/QEMU retire differential, MMU
  refill/PageMask/OS-pressure differential, and the Linux userspace marker
  gate. Its child logs and QEMU binary identity are retained under
  `build/isa_ref/qemu_system_architecture_closure/`.
- This closes a reproducible bounded architecture integration milestone. It
  does not claim full ISA/IEEE-754/OS VM semantics, unrestricted multicore
  shootdown, full RTL system-mode Linux differential, U-Boot/real QSPI-DDR
  boot, physical timing, or formal/CDC/RDC/lint signoff.

### 2026-08-25 TLB SVA and verification-tool audit

- Added a bind-based TLB checker to `make sva-gate`; it asserts that the real
  I/D main-TLB multi-hit flags correspond to at least two matching entries.
- `make sva-gate` passes after compiling the checker in the SoC SVA path, and
  `make verification-foundation-gate` records the required assets and waiver
  audit.
- The environment has VCS available but no Verilator/Yosys/SBY/SpyGlass/
  Questa CDC/VC Static/JasperGold binaries. The result is simulation assertion
  and tool-status evidence only; formal/CDC/RDC/lint signoff remains open.

### 2026-08-25 Official U-Boot build prerequisite

- Added `make linux-uboot-build-gate`, which verifies the locked U-Boot
  source marker and builds `maltael_defconfig` with the MIPS32LE cross
  toolchain. The gate passes and retains the binary hashes under
  `build/linux_boot/uboot/`.
- This closes source/build reproducibility only. The Malta configuration is
  not a port of `mips32-soc-ref`; QSPI image loading, DDR initialization,
  SoC-specific U-Boot support, Linux handoff and RTL Linux differential remain
  open.
### 2026-08-25 QEMU custom-machine U-Boot boundary probe

- Added the opt-in `malta-u-boot-compat` property to `mips32-soc-ref`. It
  supplies the Malta revision probe value and a byte-spaced legacy UART alias
  without changing the default SoC UART/APB contract.
- Added `make linux-uboot-custom-machine-probe`. A separate U-Boot build with
  `CONFIG_SKIP_LOWLEVEL_INIT` now executes through the kseg1 flash boot alias
  and reaches `board_init_f` under the custom machine.
- The probe remains `INCOMPLETE`: the image is still Malta board code and
  stops in board initialization. A SoC-specific U-Boot port, DDR/QSPI boot,
  Linux handoff and a boot prompt remain open.

### 2026-08-25 QEMU explicit peripheral MMIO windows

- The custom machine now exposes explicit high-priority UART, legacy DMA,
  QSPI and DDR-status windows over the shared APB model. Each endpoint calls
  the existing canonical CSR implementation, so state and error semantics
  remain single-sourced.
- Fresh `make qemu-system-sram-uart-mailbox-gate` and
  `make qemu-system-peripheral-contract-gate` pass. The peripheral firmware
  reports `GPIO_PASS`, `TIMER_PASS`, `DMA_PASS`, `PIC_PASS`, `QSPI_PASS` and
  `DDR_PASS`.
- This closes the bounded QEMU behavioral peripheral contract only; physical
  QSPI/DDR timing, PHY/device behavior and full RTL system differential remain
  open.

### 2026-08-25 QEMU DMA v2/PIC and current-contract rerun

- Added explicit DMA v2 and PIC CSR windows over the custom machine APB map;
  both wrappers call the canonical v2 state/PIC implementation.
- Fixed the v2 status-read completion edge so an already-DONE transfer with
  `INT_EN` still raises the deterministic channel PIC source. Fresh
  `make qemu-system-dma-v2-model-gate` passes, including direct copy,
  zero-length, SG, W1C/re-arm and PIC checks.
- Fresh `make qemu-system-current-contract-gate` passes all five children:
  peripheral contract, DMA v2, QSPI, DDR and retire capture. The broader
  architecture aggregate remains bounded by the selected differential corpus
  and is not full ISA/MMU/Linux signoff.

### 2026-08-25 QEMU VIC MMIO overlap and architecture aggregate rerun

- Fixed the custom-machine PIC endpoint to cover the complete
  `0x4000_4000..0x4000_423f` CSR span. The prior 0x40-byte endpoint left
  priority registers and VEC/ACK registers at equal priority with the flash
  boot alias, so priority writes could be decoded as flash-backed RAM.
- Fresh `make qemu-system-vic-differential-gate` passes the 48-record RTL/QEMU
  retire comparison, including VEC_ID 9 then 8 and ACK/SOFT_CLR.
- Fixed `run_qemu_system_current_contract_gate.sh` to give each child an
  independent evidence directory. Fresh current-contract and architecture
  closure aggregates pass; the latter includes selected differential, MMU
  refill/PageMask/OS pressure and Linux kernel-to-userspace marker gates.

### 2026-08-26 DMA v2 SG data contract

- Added `qemu_system_dma_sg`, a bounded custom-boot guest with two linked
  16-byte descriptors and an eight-word post-transfer comparison.
- `make qemu-system-dma-sg-data-gate` passes the real RTL/UVM path and the
  `mips32-soc-ref` machine; the guest writes the success mailbox only after
  all destination words match.
- The generic retire-plugin attempt with the larger polling firmware was
  rejected as unbounded rather than relaxing the comparator. Full per-retire
  DMA differential, physical AXI fault/reset timing and Linux DMA ABI remain
  open.
- The dedicated SG corpus now passes strict RTL/QEMU retire comparison with
  `TRACE_COMPARE_PASS`; `make qemu-system-dma-sg-differential-gate` is the
  reproducible entry. A fixed 512-iteration delay makes the RTL bus-complete
  STATUS observation deterministic against the immediate reference model.

### 2026-08-26 QEMU dual-mailbox MMU IPI contract differential

- Added explicit `0x4000_A000` and `0x4000_B000` IPI windows to
  `mips32-soc-ref`. The model implements target/generation/payload latching,
  bounded ACK, target-absent timeout, stale-ACK timeout, rejected-while-busy,
  sticky status and W1C behavior.
- Added `make qemu-system-mmu-ipi-contract-gate`. The gate runs the real
  dual-core RTL firmware path and the same guest on QEMU, then compares the
  24 APB control writes and required done/timeout/rejected/stale outcomes.
  Fresh result: `IPI_CONTRACT_COMPARE_PASS writes=24`.
- This closes the bounded RTL/QEMU mailbox/event contract. QEMU remains a
  single-vCPU reference machine; full SMP scheduling, OS-owned page tables,
  architectural multicore TLB shootdown, coherency ordering and Linux VM
  behavior remain open.

### 2026-08-26 QEMU WDT/boot-status reset contract

- Added the custom-machine WDT registers at APB offsets `0x7000..0x7010`
  and retained boot-status registers at `0x8000..0x8008`. Expiry requests a
  guest reset, clears the running counter/enable in the reset callback, and
  preserves expiry, boot stage, failure code and reset cause.
- Added a deterministic read-side virtual tick for tight TCG polling loops;
  normal virtual-clock timer scheduling remains the primary behavior.
- The QEMU firmware gate uses KSEG1 `0xA0007000/0xA0008000` to reach the
  reference machine's narrow low-physical compatibility aliases while RTL
  continues to use the canonical `0x40007000/0x40008000` APB addresses.
  Fresh `make qemu-system-wdt-gate` and `make wdt-boot-failure-gate` pass.
- This closes the bounded reference/RTL WDT boot-failure contract only; real
  always-on reset-domain retention, physical clock/reset behavior and product
  board signoff remain open.

### 2026-08-26 MMU IPI shootdown pressure evidence

- Fresh `make mmu-ipi-shootdown-pressure-gate` passes with 35 RTL shootdown
  requests, including 32 repeated generation/ASID/VPN invalidations plus busy
  rejection, stale ACK, timeout recovery and request sequencing.
- This strengthens the bounded shootdown protocol evidence but does not close
  OS page-table ownership, scheduler coordination, multicore execution or
  Linux VM behavior.

### 2026-08-26 Linux TLB ownership boundary probe

- Fixed the QEMU reset path so a DTB/UHI Linux guest does not receive the
  bare-metal prototype wired TLB entries; Linux owns TLB refill state after
  handoff, while bare-metal guests retain the existing fixed mappings.
- A four-page BSS probe was rejected because it terminates before its marker.
  A controlled four-page user-stack probe now passes: `/init` stores at
  `SP`, `SP-0x1000`, `SP-0x2000` and `SP-0x3000` before the existing success
  marker. The same init now forks one child, execve's the separate
  `/bin/vm_child` image, observes its marker, and the parent reaps it with
  `wait4` before emitting `MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS`. Full
  anonymous/file-backed demand paging, scheduler shootdown and RTL
  system-mode Linux differential remain open.

### 2026-08-26 Linux dual-child scheduler/process pressure

- Extended the verified initramfs `/init` workload to fork two children in
  sequence, execve `/bin/vm_child` in both children, and wait4 both returned
  PIDs before the parent completion marker.
- Fresh `make linux-boot-build-gate` passes. The QEMU console contains two
  `MIPS32_SOC_LINUX_EXEC_SUCCESS` markers and one
  `MIPS32_SOC_LINUX_FORK_WAIT_SUCCESS` marker; the gate now requires the exec
  marker count to be at least two.
- This strengthens the generic Linux scheduler/process handoff evidence only.
  Anonymous/file-backed demand paging ownership, a production scheduler ABI,
  multicore shootdown, U-Boot/QSPI/DDR boot, and RTL system-mode Linux
  differential remain open.

### 2026-08-26 Current-contract signoff audit

- Fresh `make current-contract-signoff` completed the directed, coverage and
  stress test stages successfully, then stopped at the required 99% coverage
  threshold without changing exclusions.
- Authoritative merged results were UVM SCORE `36.27%`, LINE `53.62%`, COND
  `41.20%`, TOGGLE `11.28%`, FSM `28.36%`, BRANCH `46.88%`; Product CPU/CP0
  SCORE `37.10%`, LINE `54.46%`, COND `41.10%`, TOGGLE `9.25%`, FSM `31.36%`,
  BRANCH `49.31%`.
- Current RTL contract signoff therefore remains open. The failure is a real
  coverage gap, not a simulation or license failure; exclusions and the 99%
  policy remain unchanged.

### 2026-08-26 Linux anonymous/file-backed demand-paging pressure

- Extended the Linux initramfs workload with MIPS O32 `mmap2`/`munmap` calls:
  five writable anonymous pages are written at page offsets 0..4, and one
  file-backed page from `/bin/vm_child` is mapped and read before unmapping.
- Fresh `make linux-boot-build-gate` passes with
  `MIPS32_SOC_LINUX_MMAP_SUCCESS`, followed by two exec markers and the
  dual-child wait marker. The gate requires the mmap marker in addition to the
  existing boot/process markers.
- This is stronger generic Linux VM evidence, but it does not close Linux
  page-table ownership, swap/file-cache policy, scheduler ABI, multicore
  shootdown, RTL system-mode Linux differential, or product boot.

### 2026-08-26 Linux heap brk demand-paging pressure

- Extended the initramfs workload with MIPS O32 `brk` growth and shrink:
  it grows the process heap by five pages, writes one word per page to force
  anonymous heap faults, restores the original break, and emits
  `MIPS32_SOC_LINUX_BRK_SUCCESS`.
- Fresh `make linux-boot-build-gate` passes with the mmap marker, heap marker,
  two exec markers, and dual-child wait marker. The generated completion report
  was also made shell-safe so literal paths are not evaluated while writing it.
- This remains bounded single-CPU Linux VM/process evidence. Full page-table
  ownership policy, swap/file-cache behavior, scheduler ABI, multicore
  shootdown, RTL Linux differential and product boot remain open.

### 2026-08-26 Linux scheduler clocksource sleep/wakeup pressure

- Added an O32 `nanosleep` call for 1 ms after the VM/heap phases. The gate
  requires `MIPS32_SOC_LINUX_SLEEP_SUCCESS`, which is emitted only after the
  syscall returns successfully and execution resumes.
- Fresh `make linux-boot-build-gate` passes with the boot, mmap, brk, sleep,
  dual-exec and dual-wait markers. Kernel logs show the MIPS clocksource is
  selected; this is a real blocking/wakeup path rather than a polling delay.
- The evidence remains single-CPU generic Linux integration. SoC timer driver
  binding, full scheduler policy/ABI, multicore shootdown and RTL system-mode
  Linux differential remain open.

### 2026-08-26 Linux explicit scheduler-yield pressure

- Added O32 `sched_yield` after the two-child fork and before the parent
  `wait4` calls. The parent emits `MIPS32_SOC_LINUX_YIELD_SUCCESS` only after
  the syscall returns successfully.
- Fresh `make linux-boot-build-gate` passes with the existing mmap, brk,
  nanosleep, dual-exec and dual-wait evidence plus the yield marker.
- This remains bounded single-CPU scheduler evidence; it does not establish
  Linux scheduler policy/ABI, SMP scheduling, shootdown coordination, or RTL
  system-mode Linux differential.

### 2026-08-26 Linux mmap permission-transition pressure

- The anonymous five-page mapping is now changed to read-only with O32
  `mprotect`, read at every page offset, restored to read/write, and then
  unmapped. The gate requires `MIPS32_SOC_LINUX_MPROTECT_SUCCESS`.
- Fresh `make linux-boot-build-gate` passes with the mmap, mprotect, brk,
  nanosleep, sched_yield, dual-exec and dual-wait markers.
- This verifies a bounded user-visible VMA permission transition and clean
  recovery. It now also forks a child that writes the read-only VMA and
  verifies the resulting `SIGSEGV` status before restoring permissions. It does
  not claim complete Linux page-table policy, SMP shootdown, or RTL Linux
  differential.

### 2026-08-26 Linux child exit-status verification

- The parent now supplies separate status pointers to both `wait4` calls and
  requires each returned PID and normal exit status to match. It emits
  `MIPS32_SOC_LINUX_WAIT_STATUS_SUCCESS` before the final parent marker.
- Fresh `make linux-boot-build-gate` passes with both exec children observed,
  both status words equal to zero, and all prior VM/scheduler markers intact.
- This is bounded process-lifecycle evidence; complete Linux scheduler/VM ABI,
  SMP semantics, and RTL system-mode Linux differential remain open.

### 2026-08-26 QEMU peripheral retire differential timing closure

- `make qemu-system-peripheral-differential-gate` passes in the fresh
  independent run `build/isa_ref/qemu_system_peripheral_differential_repro4/`.
- The guest adds a fixed architectural settling delay after starting the
  four-word legacy DMA transfer. The QEMU reference model now completes small
  legacy transfers at the same architectural boundary as RTL, while larger
  transfers retain bounded BUSY-poll behavior.
- The strict comparator reports
  `QEMU system RTL retire differential: PASS`; the guest emits GPIO, timer,
  DMA, PIC, QSPI and DDR markers before the mailbox.
- This closes the selected peripheral differential slice only. Full DMA
  fault/reset timing, Linux device drivers, physical QSPI/DDR timing and full
  system-mode Linux differential remain open.

### 2026-08-26 RTL Linux DDR fast-mode diagnosis

- Added the Linux-only `DDR_FAST_MODE` path through `mips_soc_impl` and
  `soc_memory_subsystem` into `axi_ddr4_controller`. It suppresses synthetic
  periodic refresh stalls only for `SOC_LINUX_BOOT_ENABLE`; the default DDR4
  controller contract remains unchanged. The controller initialization loop
  was also corrected to initialize both backing arrays.
- `make ddr4-controller-gate ddr4-controller-stress-gate rtl-frontend-compile`
  passes, including the default refresh/backpressure stress cases and all
  frontend configurations.
- The first implementation missed the combinational `refresh_due` gate, so
  `s_arready` remained low even after the sequential refresh state was
  suppressed. That was corrected and rechecked: S3 accepts the Linux refill,
  and the later S0 L2 backing read exits `R_WAIT` normally.
- A fresh marker-only Linux RTL run still timed out before
  `MIPS32_SOC_LINUX_BOOT_SUCCESS` (120 seconds), so Linux boot and
  RTL/QEMU Linux differential remain OPEN. The next diagnosis must follow the
  post-refill CPU/cache progress rather than refresh or initial DDR admission.

### 2026-08-26 Linux kseg0 direct-map correction

- The first Linux RTL instruction fetch was observed with `VA=0x88a55c78`
  unchanged at the AXI boundary, so the crossbar synthesized `DECERR` and the
  CPU entered a repeating CacheErr path before kernel initialization.
- `SOC_LINUX_BOOT_ENABLE` is now an explicit configuration default and selects
  the kseg0/kseg1 direct-map path in `mips_mmu`, while Linux also uses the
  product-style exception-vector selection. The ordinary default remains
  identity-mapped with the legacy vector path.
- A 300-cycle VCS probe showed the corrected physical request
  `0x08a55c60`, `read_bad=0`, `rresp=OKAY`, and the expected kernel words,
  including the entry instruction at `0x08a55c78`; the previous first
  CacheErr was absent. RTL frontend compile remains PASS (`8/8`).
- The full marker-only Linux RTL run still exceeded the current 150-second
  host budget without a marker, so RTL Linux userspace boot and the full
  RTL/QEMU Linux differential remain OPEN. The next run must continue from
  this post-entry state with a bounded progress/watchdog diagnostic.

### 2026-08-26 L1 nonblocking legacy request replay guard

- Added transaction identity tracking to `l1_cache_nb_cpu_axi`. After a
  legacy/uncached response completes, the adapter suppresses only an identical
  still-asserted request; a changed address or write payload remains eligible
  for back-to-back acceptance. This prevents duplicate uncached stores at the
  adapter boundary without stalling consecutive CPU memory operations.
- Fresh `make rtl-frontend-compile`, default `make soc-smoke
  SOC_TEST_RUN_DIR=build/soc_test/smoke_legacy_rearm`,
  `make l1-nonblocking-cpu-compat-gate`, and
  `make l1-nonblocking-cpu-multi-gate` pass. The opt-in L1 contract remains
  bounded; full coherence, arbitrary reset/error timing and Linux cache ABI
  are still open.

### 2026-08-26 Linux diagnostic trace OOM guard

- The Linux testbench's optional vector-store trace was previously enabled by
  default and had no line limit. Linux exception-vector activity therefore
  produced duplicate store lines continuously and could exhaust memory or
  disk during a long RTL run.
- The trace now defaults to disabled and accepts the bounded
  `LINUX_VECTOR_TRACE_LIMIT` plusarg (default 1000) when explicitly enabled.
  A 2000-cycle Linux RTL probe produced zero vector-store lines and an 8-KiB
  simulation log; the RTL frontend gate remains PASS (`8/8`).
- This closes the diagnostic resource-safety issue only. Linux RTL userspace
  boot, post-refill I-cache progress, and RTL/QEMU Linux differential remain
  open.

### 2026-08-26 Linux S3 DDR line trace diagnosis

- Added the opt-in `LINUX_DDR_TRACE` diagnostic with an independent line-count
  limit. It follows physical line `0x08026760` through the actual S3 DDR4
  controller, including the controller backing array, downstream AXI state and
  I-cache refill buffer.
- The bounded run reached the target refill at cycle `2228861`. The backing
  words and the eight-word refill buffer contained the expected instruction
  line, including `0x8f83000c` at `0x08026774`; the controller returned all
  eight beats with `OKAY` and `RLAST` on the final beat. The earlier hypothesis
  that S3 DDR returned corrupted data is therefore not reproduced by the
  current RTL.
- Linux RTL still does not emit `MIPS32_SOC_LINUX_BOOT_SUCCESS` within the
  bounded run and remains open. The next diagnosis must follow CPU retirement
  and D-cache progress after the correct refill, rather than add more DDR
  traffic or increase unbounded trace duration.

### 2026-08-26 Linux D-cache writeback and diagnostic bounds

- The target line was later observed being overwritten by a D-cache dirty
  writeback. At cycle 2264401, the controller accepted AW=0x08026760;
  the following eight W beats were 0x80026760, 0x80026760, zeros,
  0xffffffff, 0x00000001, and zero. The controller therefore performed
  the AXI write correctly; the corruption is upstream of the DDR backing RAM.
- The D-cache emitted the writeback address as low alias 0x00026760, which
  the Linux crossbar maps to 0x08026760. This identifies the remaining
  Linux failure as an alias/dirty-line or page-mapping interaction, not an
  I-cache last-beat assembly problem. Linux RTL boot and RTL/QEMU Linux
  differential remain OPEN pending the originating D-side request.
- Added independently bounded LINUX_DDR_WRITE_TRACE and
  LINUX_TARGET_DSIDE_TRACE plusargs. Also bounded LINUX_CACHEOP_TRACE at
  2000 lines (override with LINUX_CACHEOP_TRACE_LIMIT) so diagnostic
  options cannot recreate the prior OOM. These are verification-only and
  default off.

### 2026-08-26 RTL Linux image relocation and DDR capacity contract

- The RTL-only Linux image builder now derives the kernel backing offset from
  the ELF kseg0 load address. It no longer assumes that the first kernel byte
  belongs at DDR offset zero, and it rejects kernel/DTB overlap or backing
  window overflow before generating `ddr.hex`.
- `build_linux_boot.sh` accepts `KERNEL_PHYSICAL_START`; non-default relocated
  builds enable the required `CONFIG_CRASH_DUMP` dependency so
  `CONFIG_PHYSICAL_START` is not silently discarded. Output directories are
  normalized to absolute paths for reliable `scripts/config` operation.
- The RTL bring-up layout uses kernel VA `0x88800000` / physical
  `0x08800000` (backing offset `0x00800000`) and DTB VA `0x89f00000`.
  `mips32_soc_ref_rtl.dts` declares the corresponding 32 MiB DDR resource.
  QEMU's generic Linux layout remains unchanged.
- DDR backing capacity is now independently parameterized. Linux opt-in uses
  32 MiB while the default RTL contract remains 16 MiB.
- Evidence: relocated kernel build and image generation pass; a fresh 5M-cycle
  RTL run reaches the relocated kernel and observes the formerly conflicting
  access as `VA=0x88026760 -> PA=0x08026760`, with no Linux success marker yet.
  Full RTL system-mode userspace boot and RTL/QEMU Linux differential remain
  OPEN; this change closes the image address/capacity precondition only.

### 2026-08-27 bounded RTL Linux progress gate

- Added `make rtl-linux-progress-gate` as a reproducible, host-time-bounded
  RTL Linux probe. It builds the Linux kernel and relocated Boot ROM/DDR image
  in one run directory, compiles the Linux opt-in SoC configuration, and
  requires a post-reset CPU progress trace before passing.
- The gate disables all verbose diagnostic streams by default and bounds the
  testbench heartbeat with `RTL_CYCLE_LIMIT`, so an incomplete Linux run cannot
  recreate the earlier trace-driven OOM condition.
- This gate intentionally does not require `MIPS32_SOC_LINUX_BOOT_SUCCESS`.
  It closes the repeatable progress/evidence infrastructure only; RTL Linux
  userspace boot, full RTL/QEMU Linux differential, and the remaining OS/ISA
  boundaries are still open.

### 2026-08-27 bounded RTL Linux probe without coverage database

- Added explicit `SKIP_COVERAGE=1` handling to `tb/soc_test/run.sh`. It omits
  VCS coverage instrumentation and URG database/report generation only for an
  explicit caller opt-in; ordinary unit, SoC, UVM and signoff paths retain the
  existing coverage and exclusion checks.
- `SKIP_COVERAGE=1 make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_nocov`
  passed with `REGRESSION_TEST_SUCCESS`; the VCS simulation reported 1.1 MiB
  of data structure usage.
- A fresh relocated RTL Linux run with the existing kernel image completed
  15,000,000 cycles in `build/linux_boot/rtl_progress_nocov_15m/` and passed
  the bounded post-reset progress check. It observed no Linux userspace
  success marker, so RTL Linux userspace boot and RTL/QEMU Linux differential
  remain OPEN. This confirms the long diagnostic path avoids coverage-database
  growth and remains memory-bounded; it does not alter the default signoff
  configuration.

### 2026-08-27 bounded RTL Linux UART probe

- Added opt-in `LINUX_UART_TRACE` and `LINUX_UART_TRACE_LIMIT` controls to the
  RTL Linux progress gate. The testbench samples the actual APB UART transmit
  transaction at `soc_peripheral_subsystem -> apb_uart_16550`, in addition to
  the external UART pin observation.
- A fresh no-coverage 2M-cycle probe passed with a 1.1 MiB VCS data structure;
  a fresh 10M-cycle run also completed without simulator failure. Neither run
  observed a UART APB transmit transaction or
  `MIPS32_SOC_LINUX_BOOT_SUCCESS`. The longer trace shows the CPU progressing
  through kernel initialization and timer exception handling, so the current
  evidence does not support a UART pin-wiring failure as the userspace blocker.
- RTL Linux userspace boot, OS-owned page-table boot, and RTL/QEMU Linux
  differential remain OPEN. The next implementation diagnosis must isolate the
  kernel initialization/exception path before adding a UART model workaround.

### 2026-08-27 synchronous MMU fault versus IRQ priority

- Fixed `mips_cpu` so an IF/MEM address or translation fault blocks
  asynchronous interrupt acceptance until the synchronous fault reaches WB.
  Previously a timer IRQ could flush an outstanding Linux TLB miss, causing
  the faulting high-address store to retry indefinitely without entering the
  refill path.
- Added the `SVA_ENABLE` assertion
  `p_sync_translation_fault_priority`, which checks that an active IF/MEM
  translation fault and `interrupt_accept` are never simultaneous.
- Verification: `make rtl-frontend-compile`, `make cpu-mmu-complete`,
  `make product-mmu-boot-gate`, and `make sva-gate` pass. A no-coverage
  18M-cycle relocated Linux probe now reports a real `TLBS (code=3)` at
  `0xc0000000` before later progress, rather than silently losing the fault
  to an interrupt.
- Boundary: Linux's runtime-generated refill vector still does not complete
  the OS-owned page-table refill, so RTL Linux userspace boot and full
  RTL/QEMU system-mode differential remain OPEN.

### 2026-08-27 D-side fault VA retention

- `mips_cpu` now retains the first D-side translation-fault virtual address
  through the MEM/WB/ROB flush edge and supplies it to CP0 when the exception
  is consumed. This prevents `BadVAddr` and `EntryHi` from observing the
  post-flush bubble instead of the faulting operation.
- The `mmu_refill` firmware now treats the read-only page's `Mod` exception
  as a negative architectural check: `permission_badvaddr_ok=1` requires
  `BadVAddr=0x00022000`. Fresh `make mmu-refill-gate` evidence passes with
  `refills=7`, `demand_faults=6`, `permission_faults=1`, and
  `unexpected_exc=0`; frontend compile and CPU/CP0 regression also pass.
- This closes the selected D-side `BadVAddr` precision slice. Linux's
  runtime-generated refill handler, OS page-table ownership, and full RTL
  Linux/QEMU differential remain open.

### 2026-08-29 asynchronous IRQ branch-delay ownership

- Corrected `mips_cpu` asynchronous interrupt `Cause.BD` selection. The
  previous pipeline-wide OR allowed a stale younger delay-slot marker to
  classify an older ordinary instruction as a branch-delay exception. The
  updated logic selects the oldest valid flushed stage and requires adjacent
  MEM->EX->ID PCs before propagating a delay-slot marker from the younger ID
  stage.
- Verification: `make rtl-frontend-compile` passes all 8 configurations;
  `make cpu-irq-delay-slot-gate` and `make cpu-cp0-gate` pass; the VIC CPU
  RTL/QEMU retire differential passes with `TRACE_COMPARE_PASS records=736`;
  and the selected system differential aggregate passes.
- A no-coverage RTL Linux progress run reusing the existing kernel image
  completes 17,000,000 cycles with bounded memory and post-reset progress.
  It observes no `MIPS32_SOC_LINUX_BOOT_SUCCESS` marker. RTL Linux userspace
  boot, full RTL/QEMU Linux differential, and full ISA/privileged/MMU/FPU
  compliance therefore remain open; this change closes only the IRQ BD
  ownership bug and its bounded evidence.

### 2026-08-29 Linux progress gate kernel reuse safety

- Fixed `run_rtl_linux_progress_gate.sh` so supplying an existing `KERNEL`
  automatically reuses that image. Previously a caller could provide a valid
  kernel path while the wrapper still rebuilt the full Linux tree, creating a
  large temporary build and increasing OOM/disk-pressure risk. Explicit
  `SKIP_LINUX_BUILD=1` remains supported and still requires `KERNEL`.
- `bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh` passes. The fresh
  no-coverage run using the existing kernel completes 17,000,000 RTL cycles
  with bounded simulator memory. The progress gate passes, but no userspace
  success marker is observed; Linux userspace boot and full RTL/QEMU Linux
  differential remain open.

### 2026-08-29 Linux progress Make entry parameter forwarding

- Fixed the `rtl-linux-progress-gate` Make target to forward the wrapper's
  kernel/build, cycle/timeout, and bounded trace controls. GNU Make command
  line variables are not implicitly exported to the recipe, so before this
  fix `RTL_CYCLE_LIMIT`, `HOST_TIMEOUT`, `KERNEL`, and
  `SKIP_LINUX_BUILD` could be silently ignored when invoking the documented
  Make entry.
- A fresh `KERNEL=... SKIP_LINUX_BUILD=1 RTL_CYCLE_LIMIT=2000000` run through
  `make rtl-linux-progress-gate` passed with the requested low-log settings
  and a normal simulator exit. The run observed post-reset progress and zero
  userspace markers, so the Linux boot boundary remains open; this closes the
  reproducibility/resource-control defect in the Make entry.

### 2026-08-29 Linux progress Make coverage forwarding

- The same Make entry now forwards `SKIP_COVERAGE` and
  `SKIP_URG_EXCLUSION_CHECK` as well. Without this forwarding, a caller could
  request a low-resource probe while `tb/soc_test/run.sh` still enabled VCS
  coverage and URG processing.
- Fresh evidence: `SKIP_COVERAGE=1 KERNEL=... SKIP_LINUX_BUILD=1
  RTL_CYCLE_LIMIT=2000000 make rtl-linux-progress-gate` completes in 24.2 s,
  exits normally at the explicit cycle limit, and reports a 1.1 MiB VCS data
  structure. No userspace marker is observed; this remains resource-control
  evidence rather than Linux boot closure.

- A follow-up 10M-cycle no-coverage run through the same Make entry completes
  in 105.7 s with a 1.1 MiB VCS data structure and continuous post-reset
  heartbeat through cycle 9.9M. It still observes zero userspace markers,
  confirming that the remaining Linux RTL issue is not merely the former
  coverage/timeout configuration defect.

### 2026-08-29 Linux RTL panic-loop diagnosis

- Extended the bounded Linux delay trace with IF-PC selection and live
  `v0/ra/gp` values, and initialized its previously uninitialized sample
  counter. The old X counter made the trace condition false and could hide
  the target loop entirely.
- A fresh 30M-cycle no-coverage capture reaches the Linux delay loop at
  cycle `19884206`. The return address `0x89246004` resolves to the
  `panic()` delay loop, while `v0=0x00106256` then decreases monotonically
  (`0x4000`, `0x3fff`, `0x3ffe`, ...). This proves the observed late loop is a
  kernel panic wait, not a stuck Count decrement or a TLB refill loop.
- The run still exits normally at the explicit 30M limit with 1.1 MiB VCS
  data structure size and zero userspace markers. The next Linux closure
  step is to capture the panic entry/reason text or the preceding failing
  initialization contract; no timer/Count RTL change is justified by this
  evidence.

### 2026-08-29 Linux RTL return-path stack diagnosis

- Parameterized the Linux target D-side and DDR write traces by physical
  cache-line address and cycle window. Defaults retain the existing directed
  diagnostic target, while Linux callers can select a stack line without
  changing RTL behavior.
- A 20M-cycle no-coverage capture selected the `alloc_inode` stack line
  (`PA 0x08423d60`) and window `18.6M..18.72M`. It shows a real store from
  `lookup_one_len` writing `0x895b0000` to `PA 0x08423d64`; the subsequent
  `alloc_inode` return-path load reads that value and jumps into
  `udp_encap_needed_key` at `0x895b0484`.
- Earlier capture showed a correct `lw ra,28(sp)` D-side response and WB
  commit, so this is not a load-use or random D-cache response corruption.
  The remaining RTL Linux blocker is the interrupt/exception recovery stack
  frame/control-flow interaction; userspace boot remains open.

### 2026-08-29 Linux fatal-interrupt panic capture

- Added opt-in, bounded `LINUX_PANIC_TRACE` support to the Linux RTL
  progress probe. The trace samples the kernel panic entry window and live
  GPR/CP0 context without changing RTL behavior or enabling a default
  high-volume stream.
- A fresh 14M-cycle, no-coverage run using the existing relocated kernel
  captured the first failure chain. At cycle `13490880`, an asynchronous
  interrupt was accepted while Linux was executing `die()` at
  `0x88808c34` (`ehb` immediately after `ei`); the associated trace reports
  `Cause=0x40808008` and the pre-update EPC is the preceding TLB exception
  (`0x8923af20`). Linux then reaches `0x88808cac`, which calls
  `panic("Fatal exception in interrupt")`.
- The panic context was captured at cycle `13517530`; the call site is the
  `die()` fatal-interrupt path, not the `__udelay` loop itself. This rules out
  the earlier timer/Count-deadlock hypothesis, but does not by itself prove
  whether the remaining contract defect is IRQ acceptance timing, nested
  exception state propagation, or Linux's expected `die()` recovery policy.
- Verification for this diagnostic change: `bash -n
  tb/linux_boot/run_rtl_linux_progress_gate.sh` and
  `make rtl-frontend-compile` (`8/8`) pass. The bounded Linux run exits at
  the explicit cycle limit with a 1.1 MiB VCS data structure and no OOM.
- Boundary: the run remains a progress/diagnostic gate. RTL Linux userspace
  boot, OS-owned demand paging/shootdown, and full RTL/QEMU Linux
  differential signoff remain open. No CPU semantic change is justified
  until the interrupt's saved frame and Linux `die()` policy are compared
  against the architectural reference.

### 2026-08-29 EI/interrupt retirement ordering check

- Added an architectural ordering guard in `mips_cpu`: a pending interrupt is
  deferred when the WB stage is retiring `EI`. This allows CP0 to commit the
  `Status.IE` update before an interrupt can be accepted on the following
  boundary; otherwise CP0's exception-priority branch could suppress the
  same-edge `EI` state update.
- Verification: `make rtl-frontend-compile`,
  `make cpu-irq-delay-slot-gate`, `make cpu-cp0-gate`, and
  `make qemu-system-di-ei-differential-gate` pass. A 14M-cycle no-coverage
  Linux probe through `make rtl-linux-progress-gate` also passes its bounded
  progress criterion with a 1.1 MiB VCS data structure.
- Negative evidence: the Linux probe still reaches the same first failure at
  cycle `13490880` (`die()` at `0x88808c34`, then
  `panic("Fatal exception in interrupt")`), so this ordering fix does not
  close the Linux boot blocker. The remaining exception-frame/interrupt
  interaction needs a separately controlled reproducer or reference trace.
- Boundary: this closes only the DI/EI retirement ordering slice. It is not
  full privileged-ISA, Linux userspace, or RTL/QEMU Linux differential
  signoff.

### 2026-08-29 Linux exception-request versus interrupt-accept trace

- Extended `LINUX_EXCEPTION_TRACE` with the CPU's actual
  `interrupt_accept`, `wb_ei`, `wb_reg_write`, and `wb_mem_to_reg` signals.
  The previous `intr=1` field was CP0's combinational pending request and was
  insufficient to prove that the CPU accepted an interrupt on that edge.
- The resulting bounded trace preserves the same failure chain: a TLB load
  exception at `0x8923af20` with `BadVAddr=0x0000006c` is followed by Linux's
  `die()` path at `0x88808c34` and then the fatal-interrupt panic. This keeps
  the active investigation focused on the originating kernel data/exception
  path and its saved frame, rather than treating CP0 pending-IP state as an
  accepted interrupt.
- `make rtl-frontend-compile` passes after the trace extension. The trace is
  opt-in and bounded; it has no effect on RTL behavior or default regression
configuration.

# 2026-08-29 QEMU aggregate gate path and resource closure

- Fixed the QEMU system aggregate Make targets so child gates receive the
  caller's `BUILD_DIR`; current-contract, selected-differential, and
  architecture-closure runs no longer silently mix temporary traces with
  stale artifacts under the repository `build/` tree.
- Fixed the unaligned RTL and differential targets to pass explicit `RUN_DIR`
  and `FW_DIR`, and fixed the opt-in FPU system differential targets to use
  the matching `BUILD_DIR` firmware directory.
- Evidence before cleanup: selected system differential passed all 15 child
  gates in an isolated `/tmp` build; unaligned and FPU-invalid differential
  gates passed independently; current-contract and MMU pressure children
  passed. The architecture aggregate reached the FPU boundary and then hit
  host `ENOSPC` while VCS created `binmap.sdb`, so that aggregate was not
  claimed as passed.
- The repository `build/` and stale temporary verification trees were then
  removed through the project clean target. Source, git metadata, and the
  generated QEMU source/build inputs remain reproducible but must be rebuilt
  before the next full aggregate run.

# 2026-08-29 isolated QEMU selected differential rerun

- Propagated the caller's `BUILD_DIR` through the remaining system-mode
  differential Make targets and wrapper defaults. This prevents selected
  differential children from rebuilding firmware under the repository
  `build/` directory when an isolated build root is requested.
- Fixed the QEMU retire plugin's shutdown boundary. A mailbox write can stop
  QEMU before `vcpu_exit`, so the pending terminal instruction is now flushed;
  its final state snapshot is duplicated from the last valid vCPU snapshot
  without calling the plugin register API after the vCPU has gone away.
- Fresh evidence: `SKIP_COVERAGE=1 BUILD_DIR=/tmp/mips32-qemu-selected-pathfix2
  HOST_TIMEOUT=600 RTL_TIMEOUT=120 make
  qemu-system-selected-differential-gate` passes all 15 serial child gates,
  including the immediate-trap, unaligned, VIC, opt-in FPU, and DMA SG
  differentials. The isolated trap-imm child passes after comparing 92
  terminal records.
- This closes reproducibility and terminal-event integrity for the selected
  bare-metal system differential. It does not close full ISA/privileged/FPU
  compliance, RTL Linux userspace boot, full Linux RTL/QEMU differential, or
  physical DDR/QSPI signoff.

# 2026-08-29 software-MMU vector and LL/SC differential repair

- Fixed the custom QEMU reset contract for SRAM-linked software-MMU guests:
  reset now clears `Status.BEV`, while Boot-ROM MMU guests retain BEV for
  `BFC00200`.
- Fixed the QEMU TLBL/TLBS refill offset split. SRAM guests enter the RTL
  handler at `EBase+0x180`; Boot-ROM guests retain the fixed Boot-ROM refill
  offset. The build script applies this patch idempotently.
- Fresh evidence: `make qemu-system-mmu-refill-differential-gate` passes for
  both the normal MMU refill and `OS_PRESSURE=1` paths. The architecture
  aggregate reached all later children; its only failure was the pre-existing
  LL/SC hook detection issue.
- Corrected the QEMU build-script LLAddr hook check to require the complete
  marker/body, not merely the weak callback declaration. The generated QEMU
  model now exposes the aligned virtual LL address required by the RTL.
- Fresh evidence: `SKIP_COVERAGE=1 BUILD_DIR=/tmp/mips32-qemu-llsc-fix
  HOST_TIMEOUT=30 RTL_TIMEOUT=120 make qemu-system-llsc-differential-gate`
  passes. Current-contract, selected-differential, MMU PageMask, MMU refill,
  MMU OS pressure, and FPU boundary children also passed in the aggregate.
- Remaining boundary is unchanged: full RTL Linux userspace boot and
  full RTL/QEMU Linux differential still require separate OS/privileged-ISA
  work; this is not a claim of full MIPS ISA or commercial physical signoff.

# 2026-08-29 Linux fork/wait userspace closure

- The architecture aggregate exposed a test-image issue after the kernel had
  already reached userspace: both `execve` children emitted their success
  markers, but the parent checked Linux's implementation-specific child PIDs.
- Updated the freestanding initramfs image to use `wait4(-1, ...)` for both
  reaps while retaining exit-status validation. This removes the PID
  allocation assumption without weakening the fork/exec/wait contract.
- Fresh incremental evidence: `RUN_DIR=/tmp/mips32-linux-forkwait-fix
  QEMU_TIMEOUT=30s tb/linux_boot/run_linux_boot_gate.sh` passes, including
  kernel-to-userspace, mmap/mprotect/brk, sleep/yield, two exec markers,
  both wait4 reaps and wait-status validation.
- An experimental `WNOHANG` polling version was rejected because it did not
  complete the same gate; it was reverted and is not part of the change.

# 2026-08-29 final bounded architecture aggregate rerun

- Fresh final-source run: `source /etc/profile.d/modules.sh && module load vcs
  && SKIP_COVERAGE=1 BUILD_DIR=/tmp/mips32-linux-forkwait-fix
  HOST_TIMEOUT=900 RTL_TIMEOUT=180 make
  qemu-system-architecture-closure-gate` passes.
- The aggregate covers current-contract, selected system-mode retire
  differential, MMU refill/PageMask/OS-pressure, FPU exception boundaries,
  LL/SC, and the QEMU generic Linux kernel-to-userspace/fork/wait gate.
- This is the final bounded architecture evidence for the current source
  line. It does not close RTL system-mode Linux userspace boot, full ISA or
  privileged-ISA compliance, unrestricted OS page-table/shootdown semantics,
  full RTL/QEMU Linux differential, physical DDR/QSPI PHY/device timing, or
  formal/CDC/RDC/lint/synthesis/STA/DFT signoff.

# 2026-08-29 retire differential resource bound

- The RTL `retire_trace_capture` sink now accepts `+RETIRE_TRACE_MAX_RECORDS`
  and stops with a nonzero simulator status before writing record N+1 when a
  nonzero limit is reached. The default is 1,000,000 records; `0` is reserved
  for an explicitly reviewed unbounded capture.
- `run_qemu_system_differential_gate.sh` passes its existing
  `MAX_TRACE_RECORDS` threshold into the RTL run, while retaining the
  post-run byte/record integrity check. When `QEMU_CAPTURE_TMPDIR=1`, an EXIT
  trap removes the exact temporary directory created by that invocation on
  success and failure.
- Fresh `qemu-system-wait-differential-gate` evidence passes with the change.
  This closes verification resource safety for the retire differential runner
  only; it does not close RTL Linux userspace boot, full ISA/privileged
  compliance, full RTL/QEMU Linux differential, or product signoff.

# 2026-08-29 VCS gate log separation

- Updated `tb/soc_test/run.sh` so VCS writes its runtime `-l` file to
  `sim_runtime.log`, while simulator stdout/stderr is captured in the stable
  `sim.log` consumed by gate checks.
- This removes the two-writer log collision that made wrapper-invoked long
  diagnostics susceptible to truncation/interleaving, without changing RTL,
  default configuration, or coverage behavior.
- Fresh evidence: `make rtl-frontend-compile` passes all 8 configurations;
  `SKIP_COVERAGE=1 make cpu-load-return-gate` and `SKIP_COVERAGE=1 make
  soc-smoke` both pass with `REGRESSION_TEST_SUCCESS` in `sim.log`.
- This closes diagnostic artifact integrity only; RTL Linux userspace boot,
  full ISA/privileged/FPU compliance, and full plan signoff remain open.

# 2026-08-29 VCS log publication race correction

- Corrected the first log-separation implementation: Linux callers redirect
  `run.sh` stdout to `sim.log`, so `run.sh` must not write that path while the
  command is running. VCS now writes only `sim_runtime.log`; after exit,
  `run.sh` copies that complete file to `sim.log` and then applies the original
  simulator status to the gate.
- Fresh evidence: `SKIP_COVERAGE=1 make soc-smoke` and
  `SKIP_COVERAGE=1 make l1-nonblocking-cpu-two-error-reset-gate` pass, with
  `REGRESSION_TEST_SUCCESS` and the two injected `SLVERR` paths preserved in
  the published logs.

# 2026-08-29 RTL Linux coverage propagation

- Fixed `tb/linux_boot/run_rtl_linux_progress_gate.sh` to forward
  `SKIP_COVERAGE` into the nested SoC runner. Long Linux diagnostics therefore
  honor explicit no-coverage mode and do not allocate VCS coverage databases
  accidentally.
- Fresh evidence: a 100k-cycle probe using the existing kernel passes with
  post-reset CPU progress and stable `sim.log`/`sim_runtime.log` artifacts.
  It observes zero userspace success markers, so this closes runner resource
  behavior only; RTL Linux userspace boot remains an open functional item.

# 2026-08-29 Linux link-instruction overflow false positive

- Diagnosed the first post-reset Linux loop: `start_kernel`'s `jal
  smp_setup_processor_id` was carrying the ALU's default-add overflow bit,
  and the old `ex_overflow && ex_reg_write && !mem_read && !mem_write` gate
  incorrectly converted that link instruction into `ExcCode=12`.
- Restricted the overflow exception to the architectural `ADD`, `SUB`, and
  `ADDI` encodings. `JAL/JALR` link writes no longer inherit arithmetic
  overflow state.
- Fresh evidence: `make qemu-system-exception-differential-gate` passes, and
  the 20M-cycle no-coverage RTL Linux probe advances beyond the old
  `start_kernel` loop. It still reports no userspace marker; the next blocker
  is a distinct `0x0100101c` MMU/address fault around cycle 19.8M.

# 2026-08-29 RTL Linux GPR source diagnosis

- Added default-off, register/cycle-filtered `LINUX_GPR_TRACE` support to the
  RTL Linux progress runner and testbench. It also records the context-restore
  request and restored `$s0` image when applicable.
- A bounded 20M-cycle capture proves `$a0` is written as `0x01001000` by
  `0x889aa6f4: lw a0,4(a0)` at cycle `19808323`, then copied to `$s0` by
  `0x889f0b5c: or s0,a0,zero`. No context-restore write is observed in the
  target window.
- This is evidence about the source memory/data path and does not justify an
  exception, forwarding, or MMU semantic change. RTL Linux userspace boot and
  full RTL/QEMU Linux differential remain open.

# 2026-08-29 RTL Linux dirty-line ownership diagnosis

- Added bounded, default-off `LINUX_CACHE_OWNER_TRACE` support. It records
  only real CPU store acceptance and D-cache refill/writeback handshakes,
  with the target line, CPU MEM PC, request buffer and line words.
- A fresh 5.7M-cycle no-coverage probe shows the target line `0x08402100`
  initially refills as zero. Linux then performs the real store
  `0x889f12e0: sw a1,4(s2)` with `a1=0x01001000` at cycle `5348440`; the
  subsequent D-cache writeback emits the same value at word 1, and the later
  refill returns it unchanged. No cache-generated value or writeback data
  corruption is observed.
- This closes the dirty-line ownership diagnosis for this target and moves
  the open RTL Linux blocker upstream to Linux runtime/control-flow or a
  different CPU architectural contract. It does not close RTL Linux userspace
  boot, OS VM ownership, or full RTL/QEMU Linux differential.

# 2026-08-29 Linux system-mode retire capture plumbing

- Extended `run_qemu_system_retire_capture_gate.sh` with opt-in
  `QEMU_KERNEL`, `QEMU_DTB`, `QEMU_MEMORY` and `QEMU_APPEND` inputs. Existing
  bare-metal `FW_ELF` invocations retain their defaults and behavior.
- Added opt-in `LINUX_RETIRE_TRACE=1` support to the RTL Linux progress runner;
  `tb/soc_test/run.sh` passes `RETIRE_TRACE` only when explicitly requested.
- Fresh checks pass: the bare-metal QEMU retire capture gate passes, a QEMU
  Linux kernel/DTB capture probe completes conversion under explicit event and
  byte limits, and a 100k-cycle RTL Linux probe emits 20,000 valid retire
  records. These are capture-plumbing proofs; Linux userspace boot and full
  RTL/QEMU Linux differential remain open.

# 2026-08-29 D-cache CACHE writeback alias consistency

- The blocking `dcache` recognized only `0x19` for `Hit_Writeback_D`, while
  the decoder, opt-in nonblocking L1, and maintenance contract also expose the
  MIPS32 R2 `0x1d` alias. This caused the blocking maintenance regression to
  skip the writeback and fail its error, memory-visibility, and retention
  checks.
- Added `0x1d` as a writeback-only alias in the blocking cache and corrected the
  unit test's writeback+invalidate case to use the documented `0x15` encoding.
  The alias clears dirty only after a successful writeback and preserves valid;
  `0x15` still invalidates after writeback.
- Fresh evidence: `make dcache-parity-gate cpu-cache-op-gate` and isolated
  `make rtl-frontend-compile` pass (`8/8`). This closes encoding consistency
  for the bounded CACHE maintenance contract only; complete cache ordering,
  coherency and OS cache ABI remain open.

# 2026-08-30 Linux diagnostic trace resource bound

- Root-cause audit found that `LINUX_EXCEPTION_TRACE` was enabled by default
  but had no record limit. A repeated exception/interrupt loop could therefore
  append indefinitely to the simulator log and create host disk/memory
  pressure, even though the RTL itself remained bounded.
- Added `LINUX_EXCEPTION_TRACE_LIMIT` (default `256`) and a testbench counter;
  the Linux progress runner forwards the limit through `LINUX_EXTRA_SIM_ARGS`.
  The default functional path and all RTL configuration defines are unchanged.
- Verification: `bash -n tb/linux_boot/run_rtl_linux_progress_gate.sh`,
  `git diff --check`, isolated `make rtl-frontend-compile` (`8/8`), and a
  20M-cycle no-coverage Linux run with
  `LINUX_EXCEPTION_TRACE_LIMIT=7` produced exactly seven exception records,
  a 5.4 KiB simulator log, and a 1.1 MiB VCS data structure. The runner's
  progress criterion was intentionally disabled for this diagnostic-only
  run; VCS exited normally at the explicit cycle limit.
- This fixes the diagnostic OOM/log-growth risk only. RTL Linux userspace boot,
  full RTL/QEMU Linux differential, and the underlying Linux exception/control
  flow blocker remain open.

# 2026-08-30 Linux exception-frame before/after trace

- Added opt-in, bounded `LINUX_EXCEPTION_FRAME_TRACE` support to the RTL Linux
  progress testbench. For each selected exception, interrupt acceptance, ERET,
  or context-restore event it emits a `LINUX_EXCEPTION_FRAME_BEFORE` record and
  the following-cycle `LINUX_EXCEPTION_FRAME_AFTER` record. The pair includes
  event PC/code, interrupt acceptance, WB exception metadata, Status, Cause,
  EPC, ErrorEPC, BadVAddr and the exception-vector base. The runner forwards
  both the enable and limit controls through `LINUX_EXTRA_SIM_ARGS`; default
  operation remains disabled and bounded to 64 event pairs.
- This separates the pre-NBA event view from the post-CP0 architectural frame,
  which is required to distinguish a bad saved frame from a later Linux
  handler/control-flow decision. `make rtl-frontend-compile` passes all 8/8
  configurations; `SKIP_COVERAGE=1 make cpu-irq-delay-slot-gate cpu-cp0-gate`
  also passes.
- Boundary: no CPU semantic change was made and no Linux userspace success
  marker was produced by this infrastructure change. RTL Linux userspace boot,
  OS-owned demand paging/shootdown and full RTL/QEMU Linux differential remain
  open pending a bounded frame capture and comparison with Linux's handler
  expectations.

### 2026-08-30 Linux exception-frame window capture

- Added cycle-window controls `LINUX_EXCEPTION_FRAME_TRACE_CYCLE_START` and
  `LINUX_EXCEPTION_FRAME_TRACE_CYCLE_END` so a long Linux run can capture a
  specific exception/IRQ/ERET interval without producing a broad trace.
- A fresh 14M-cycle no-coverage run passed the bounded progress gate and
  captured the suspected fatal-interrupt neighborhood at cycle 13,506,661:
  the accepted IRQ occurred at `0x88852ddc`, the delay slot of a branch at
  `0x88852dd8`. The before/after pair shows `Status.EXL` changing 0->1,
  `EPC=0x88852dd8`, `Cause.BD=1`, and a later ERET clearing EXL while retaining
  the saved EPC. This is consistent with the MIPS branch-delay exception
  contract and does not justify a CPU semantic change by itself.
- The first probe exposed and fixed an undeclared Linux-testbench trace counter
  that the ordinary RTL frontend target does not compile. The Linux-specific
  testbench then compiled and the windowed run completed with a 1.1 MiB VCS
  data structure; userspace marker count remained zero. Linux userspace boot,
  OS-owned demand paging/shootdown and full RTL/QEMU Linux differential remain
  open.
- Added `scripts/check_linux_exception_frame_trace.py` and the
  `make linux-exception-frame-check LOG=...` entry point. The checker pairs the
  event and post-CP0 records and enforces EXL, EPC, and Cause.BD invariants;
  ERET records remain trace-visible but are excluded from the frame-save check.
  It passes the fresh window capture with `pairs=1`.

### 2026-08-30 QEMU MMU differential stale-firmware fix

- The QEMU system architecture aggregate exposed an early retire mismatch in
  `qemu-system-mmu-refill-differential-gate`: RTL retired `JAL 0x000005f0`,
  while QEMU retired `JAL 0x00008240`. The child gate had rebuilt the RTL
  workload under its run-local firmware directory but passed the repository's
  older source ELF to QEMU. The gate now explicitly passes the freshly
  generated RTL-run ELF to the reference machine.
- The isolated rerun passes the MMU refill RTL/QEMU differential. The fix also
  prevents future temporary `BUILD_DIR` runs from silently mixing firmware
  generations.

### 2026-08-30 generic Linux wait4 PID selection

- A fresh aggregate Linux run reached the boot, mmap, mprotect, brk, sleep,
  yield, and both exec markers, but the parent did not complete `wait4(-1)`
  before the gate timeout. A longer isolated run reproduced the same boundary.
- Updated the freestanding initramfs parent to pass the two PIDs returned by
  its `fork` calls to the corresponding `wait4` calls while retaining status
  validation. This keeps the wait/reap contract deterministic without assuming
  fixed PID allocation. A full rebuilt-kernel rerun was not completed because
  the environment's independent Linux kernel rebuild was still compiling after
  ten minutes; the source change remains pending that verification. Linux RTL
  boot and full RTL/QEMU Linux differential remain open.

### 2026-08-30 Linux TLB-fault neighborhood frame check

- A fresh 20M-cycle no-coverage run with a narrow `19.57M..19.61M` cycle
  window captured the next suspected failure boundary and passed the frame
  checker. The event at `0x8925dccc` is an accepted branch-delay-slot IRQ;
  CP0 records `EXL=1`, `EPC=0x8925dcc8`, `Cause.BD=1`, and preserves
  `BadVAddr=0xc0000020`, followed by the normal ERET recovery sequence outside
  the selected window.
- This is additional negative evidence against CP0 frame corruption or bad
  delay-slot EPC handling as the immediate Linux blocker. The probe still has
  zero userspace success markers, so no Linux boot or full RTL/QEMU differential
  closure is claimed; the remaining issue is still in the Linux exception/
  refill/control-flow interaction.

### 2026-08-30 generic Linux wait4 PID verification

- Rebuilt the Linux v6.6 kernel and embedded initramfs from the updated
  `tb/linux_boot/init.S`, then ran
  `RUN_DIR=/tmp/linux_gate_pid_repro QEMU_TIMEOUT=60s JOBS=2
  tb/linux_boot/run_linux_boot_gate.sh`.
- The fresh `mips32-soc-ref` run passed the complete generic userspace gate:
  boot, mmap/mprotect and protection fault, brk, nanosleep, sched_yield, two
  fork/exec children, exact-PID `wait4`, and both normal exit-status checks.
- The earlier standalone image passed this gate, but a fresh isolated image
  used by the architecture aggregate stalled after the intentional SIGSEGV
  child fault. Repeating the same image reproduced the stall; changing that
  first wait to bounded `wait4(WNOHANG)` polling did not advance it. The exact
  final fork/exec PID change therefore remains useful but is not declared
  closed until the custom-machine signal/child-exit path is reproducible.

### 2026-08-30 deterministic Linux image and SIGSEGV boundary

- `build_linux_boot.sh` now fixes Kbuild metadata, linker build-id metadata,
  and initramfs file mtimes so isolated kernel/initramfs images are not
  needlessly different across build roots.
- The first epoch value (`0`) was rejected by Linux `gen_init_cpio`; it was
  corrected to `2000-01-01`. The resulting image builds successfully.
- A bounded `wait4(WNOHANG)` poll around the intentional read-only child fault
  still stalls after Linux reports the SIGSEGV. This isolates the remaining
  issue to the custom QEMU/Linux signal-exit or scheduler path; no comparator,
  timeout relaxation, or Linux success claim was added.

### 2026-08-30 Linux guest LL/SC A/B conclusion

- The attempted `linux-guest=on` machine-property isolation was reverted.
- With the same fresh kernel, physical reservation identity stalled Linux
  after the intentional SIGSEGV child fault; the existing virtual `LLAddr`
  behavior completed the full boot, VM, fork/exec, and wait4 marker set.
- The custom machine and both Linux runners therefore retain the existing
  virtual-`LLAddr` contract. Linux userspace closure and full RTL/QEMU
  system-mode differential remain open.

### 2026-08-30 Linux single-vCPU TCG scheduling containment

- The same kernel and rebuilt custom machine were compared under default
  multi-threaded TCG and `-accel tcg,thread=single`.
- Multi-threaded TCG reproducibly stalled in the Linux `wait4` path after the
  intentional SIGSEGV child fault. Single-threaded TCG completed both exec
  children, both wait-status checks, and the final fork/wait marker.
- The generic Linux boot and bounded Linux differential runners now select
  single-threaded TCG explicitly. This contains a host execution-mode issue
  for the single-vCPU contract; it does not close SMP, Linux VM ownership, or
  full RTL/QEMU Linux differential.

### 2026-08-30 EDA host-OOM containment

- Kernel OOM records identified the previous high-water event as a VCS
  compiler process reaching roughly 2 GiB inside an `eda-*` cgroup, with
  separate historical global OOM events caused by concurrent Python jobs.
  The long RTL Linux simulator itself was observed at roughly 160 MiB and
  was not the source of that event.
- The high-load SoC, UVM single-test, UVM regression, UVM directed-test,
  SVA, and current-contract coverage/URG entry points now run VCS, `simv`,
  and URG through `scripts/run_eda_cgroup.sh`. VCS compilation defaults to
  `VCS_JOBS=1`; `EDA_MEMORY_MAX`, `EDA_SWAP_MAX`, `VCS_JOBS`, and
  `EDA_RUNNER` remain explicit overrides.
- Isolated no-coverage `soc-smoke` and all three SVA scenarios passed under
  temporary roots. This closes resource containment and exit-code propagation
  for the aggregate entry points; it does not make arbitrary standalone unit
  scripts resource-isolated, nor does it change architectural coverage or
  Linux closure status.

### 2026-08-30 RTL Linux 100M-cycle delay boundary

- Ran a fresh relocated kernel image with coverage disabled and bounded
  resources: `VCS_JOBS=1 EDA_MEMORY_MAX=1500M EDA_SWAP_MAX=512M
  SKIP_COVERAGE=1 RTL_CYCLE_LIMIT=100000000 HOST_TIMEOUT=600s
  make rtl-linux-progress-gate`.
- The simulator reached approximately 62.5M cycles before the 600-second
  host timeout, with stable RSS near 158 MiB and no simulator OOM. The final
  progress records repeatedly show the legal Linux `__udelay` loop at
  `0x89243530/0x89243534`; no Linux userspace success marker was observed.
- This rules out the old short-budget explanation for the current boundary,
  but does not yet identify whether the delay value, CP0 Count/clockevent
  calibration, or RTL pipeline throughput is responsible. The next diagnostic
  must capture the loop's `v0`, CP0 Count/Compare and timer interrupt boundary
  in one run before any CP0 or Linux timing semantic change. RTL Linux
  userspace boot and full RTL/QEMU Linux differential remain open.

### 2026-08-30 RTL Linux delay/CP0 correlation probe

- Ran the existing 20M-cycle no-coverage probe with the narrow
  `LINUX_DELAY_TRACE` window at `0x89243530..0x89243534` and a bounded CP0
  trace. The simulator completed normally and produced a 1.1 MiB VCS data
  structure; the wrapper returned a diagnostic failure only because progress
  heartbeat output was intentionally disabled for this trace-only run.
- The captured `__udelay` sequence shows `v0=0x00106256` and then a normal
  decrement on each loop iteration (two RTL cycles per decrement). CP0 Count
  advances continuously, Linux Compare writes are visible, and the timer
  `Cause.TI`/interrupt state changes at the expected compare boundaries.
- This rules out a stopped Count or a missed Compare event as the immediate
  cause. The remaining RTL Linux boundary is repeated/long delay activity
  relative to RTL throughput or a higher-level Linux initialization path. No
  CP0 timing semantic change is justified by this evidence; userspace boot
  and full RTL/QEMU Linux differential remain open.

### 2026-08-30 blocking MEM transaction IRQ barrier

- Tightened `mips_cpu` interrupt acceptance so an active MEM data transaction
  (`data_req_raw`) cannot be flushed by an asynchronous IRQ before its
  response and architectural retirement. `stall_req_mem` alone did not cover
  the address-accepted/waiting-response boundary.
- RTL frontend compile (`8/8`), CPU/CP0 firmware, and IRQ delay-slot gates
  pass. A fresh 14M-cycle no-coverage RTL Linux progress probe also passes;
  userspace marker count remains zero, so this is a targeted recovery fix and
  not Linux boot closure.
- Corrected the Linux build script's reversed `CONFIG_CRASH_DUMP` dependency
  condition and added an ELF load-address check. A rebuilt kernel now reports
  `0x88000000`, and the RTL Boot ROM/DDR image generator passes with the
  relocated image.

### 2026-08-30 blocking MEM/IRQ directed regression

- Added `make cpu-irq-mem-pending-gate`, a direct `mips_cpu` test which accepts
  a blocking load address, delays its response for four cycles while IP2 is
  asserted, and checks that no interrupt is accepted during the live request.
- The same test checks the load data is retired exactly once and that the
  pending interrupt is accepted after the response. This is a narrow unit
  contract for the asynchronous interrupt/MEM handshake; Linux userspace,
  arbitrary reset-in-flight timing, and complete exception recovery remain
  open.

- The RTL now also asserts `p_blocking_mem_irq_barrier` under `SVA_ENABLE`,
  enforcing the same invariant on every SoC simulation cycle. An isolated
  `SKIP_COVERAGE=1 make sva-gate` rerun passed all three SVA scenarios.
- Added the corresponding `p_blocking_mem_irq_barrier` simulation assertion
  under `SVA_ENABLE`; the isolated SVA gate and direct unit gate remain
  required evidence for this boundary.

### 2026-08-30 SPECIAL2 reserved-field enforcement

- Corrected `rtl/cpu/mips_control.v` so canonical MIPS32 R2 SPECIAL2 encodings
  are accepted while reserved fields are rejected before any architectural
  side effect: MADD/MADDU/MSUB/MSUBU require `rd=0, sa=0`, MUL requires
  `sa=0`, and CLZ/CLO require `rt=rd, sa=0`.
- Added `make mips-control-special2-gate`, including positive coverage for all
  five MDU encodings and CLZ/CLO plus seven negative reserved-field cases.
  The gate passed with VCS; `rtl-frontend-compile` passed all 8 configurations,
  `mdu-cpu-gate` and `cpu-cp0-gate` also passed, and ISA matrix audit reported
  `ISA_IMPLEMENTATION_AUDIT_PASS rows=19`.
- A fresh `qemu-system-isa-r2-differential-gate` also passed after correcting
  the CLZ/CLO field interpretation, confirming RTL/QEMU retire agreement for
  the existing ISA R2 corpus.
- This closes the SPECIAL2 decoder reserved-field slice only. Complete
  MIPS32/privileged ISA compliance, FPU ABI, Linux boot and full differential
  remain open.

### 2026-08-30 SPECIAL fixed-field enforcement

- Extended `rtl/cpu/mips_control.v` fixed-field checks to SPECIAL ALU,
  shifts, variable shifts, compares, traps, MOVZ/MOVN, MFHI/MFLO, MTHI/MTLO,
  and MULT/DIV instructions. Invalid reserved fields now produce RI without
  control side effects; the architectural R2 `SLL $0,$0,3` EHB alias remains
  accepted.
- Expanded `mips-control-special2-gate` with valid ADD/SLL/SLLV/EHB cases and
  eight invalid SPECIAL encodings. The gate passed, as did a fresh
  `qemu-system-isa-r2-differential-gate`.
- This closes only the tested SPECIAL fixed-field slice. Other privileged and
  FPU semantics, Linux RTL boot, and full ISA compliance remain open.

### 2026-08-30 branch fixed-field enforcement

- Added the MIPS32 rule that BLEZ/BLEZL/BGTZ/BGTZL require `rt=0`; malformed
  encodings now raise RI before branch control is emitted.
- Added four negative cases to `mips-control-special2-gate`; the gate and the
  QEMU system ISA R2 retire differential remain passing.
