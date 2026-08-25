# Architecture Closure Execution Tracking

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
- The latest fresh `qemu-system-vic-cpu-differential-gate` run passes 735
  retire records after the VIC corpus changed its readbacks to direct caller
  MMIO loads. The generic CPU subroutine-return/load forwarding bug remains a
  separate residual and is not hidden by this corpus-specific workaround.

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
  `TRACE_COMPARE_PASS records=447`, including all four ALIGN positions.
  Full ISA, privileged/MMU and Linux differential remain open.

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
