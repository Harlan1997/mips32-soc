# Refactor Roadmap

## Phase 0: Freeze Contracts

Deliverables:
- product top definition
- verification top definition
- address map freeze
- interface width freeze
- feature list freeze
- architecture migration plan

Exit criteria:
- no ambiguous decode rules
- no test-only path in product top
- no hardcoded paths in scripts
- product and verification entry points are separated on paper before RTL split

## Phase 1: Normalize Architecture

Deliverables:
- shared constants/package
- cleaned interconnect boundaries
- consistent reset policy
- build-time feature switches
- product top cleanup
- verification top cleanup

Current status:
- Product and verification top split is in place.
- Shared address decode constants are started in `rtl/include/soc_config.vh`.
- UVM AXI roles are split into passive monitor, active master, and active slave
  interfaces, removing structural multi-driver warnings in VCS.
- `rtl/soc_fabric.v` extracts the AXI arbiter/decode fabric from
  `mips_soc_impl`.
- `axi_decoder_1x3` now implements explicit SRAM/alias/APB/flash decode and
  returns AXI `DECERR` for unmapped accesses.
- The 2x1 arbiters now use round-robin, single-outstanding arbitration with
  address-channel payload locking while downstream ready is low.
- `axi_stress_seq` no longer corrupts firmware SRAM while running background
  traffic.
- Verification-side AXI protocol checkers are now connected to the external
  UVM master port, the observed SRAM port, and the internal `soc_fabric`
  `axim`, `axim2`, `axim3`, and `axim4` links through verification-only binds.
  They check payload stability, single outstanding behavior, burst beat counts,
  WLAST/RLAST placement, and responses without outstanding requests.
- `axi_spi_flash` now honors AXI read burst length and returns a completed
  `SLVERR` write response for the read-only flash window.
- AXI monitor transaction reconstruction is enabled for the external UVM master
  and SRAM observation agents.
- `soc_scoreboard` checks mapped/unmapped response contracts, flash write
  `SLVERR`, and SRAM observation-window legality.
- `soc_flash_write_error_test` directly verifies the flash write error path.
- `soc_bus_coverage` is connected to the monitor streams and samples source,
  direction, address window, response, burst length, transfer size, burst type,
  and core crosses.
- `soc_fabric_contract_test` provides a compact directed coverage test for boot
  SRAM, SRAM alias, APB, flash, and unmapped windows.
- GPIO APB register data checking is implemented in `soc_scoreboard`, and
  `soc_gpio_reg_model_test` verifies `DATA`/`DIR` write-read consistency.
- UART, timer, and PIC APB register checking is implemented in
  `soc_scoreboard`, and `soc_apb_reg_model_test` verifies UART status/TX,
  timer disabled-mode `CTRL`/`LOAD`/`VAL`/`INT`, and PIC `MASK`/zero-mask
  `ACTIVE` behavior.
- SRAM byte-lane data checking is implemented in `soc_scoreboard`, and
  `soc_sram_data_integrity_test` verifies SRAM alias burst write/read, a masked
  byte-strobe update, a 9-beat long INCR burst, and boot-window write/readback.
- `axi_monitor` and `axi_master_monitor` now use channel-parallel, ID-aware
  transaction reconstruction. AW/AR handshakes are queued, W/R/B channels are
  merged by transaction order and response ID, and same-cycle AW/W or AR/R
  handshakes are handled without monitor races.
- `soc_bus_coverage` now samples transaction ID bins and crosses them with
  source and direction. `soc_axi_id_sweep_test` deterministically covers ID0,
  ID1-3, ID4-7, and ID8-15 bins through legal and error-response paths.
- `axi_protocol_checker` now uses the same ID-aware queue model internally.
  Current top-level instances still set `REQUIRE_SINGLE_OUTSTANDING=1`, but the
  checker can be switched to legal multi-outstanding response checking when the
  active master and RTL fabric are upgraded.
- The external AXI master BFM now has a default-off overlap mode. When enabled,
  AW, W, B, AR, and R channel workers run independently and response completion
  is tracked per AXI ID.
- `soc_axi_overlap_probe_test` enables overlap mode and drives back-to-back
  SRAM, flash, and unmapped transactions across multiple IDs. The test passes in
  the current regression and proves the verification infrastructure can generate
  overlapping traffic even though the product fabric is still signed off as
  single-outstanding.
- Flash read data checking is implemented in `soc_scoreboard` for the current
  zero-filled SPI flash model, and is hit by the fabric contract, ID sweep, and
  overlap probe tests.
- `soc_bus_coverage` now tracks the current supported bus contract: OKAY,
  SLVERR, and DECERR responses; word-sized INCR bursts; representative IDs; and
  legal address-window/response crosses. EXOKAY, non-word sizes, FIXED/WRAP
  bursts, and architecturally unreachable source/window or window/response
  crosses are ignored until the RTL contract expands.
- Internal fabric checker binding exposed an APB bridge read-burst bug where an
  APB-window AXI read with `ARLEN>0` completed after one beat. The bridge now
  latches read burst attributes and performs one APB read per AXI read beat,
  holding `RVALID/RLAST/RRESP` until `RREADY`.
- `soc_apb_reg_model_test` now includes a directed 4-beat INCR timer-register
  read burst, checking every returned APB beat and response.
- `soc_timer_irq_test` now covers the timer interrupt path through PIC bit 2,
  including timer enable, PIC mask enable, PIC STATUS/ACTIVE assertion, timer
  interrupt clear, PIC deassertion, and mask restore. It adds
  `timer_irq_event_cg` and `timer_irq_latency_cg`.
- The RTL-level multi-outstanding fabric is now delivered (see "Phase C.3" below):
  the single-outstanding arbiter cascade was replaced by a true M×N crossbar with
  concurrent cross-slave transactions, ID-tagged in-order response routing, QoS
  arbitration, and per-slave outstanding depth. Remaining fabric-adjacent work:
  broader interrupt/exception coverage, richer flash-image traffic, and the
  remaining peripheral data scoreboards.

Exit criteria:
- RTL and TB use the same contract
- boot flow is documented
- illegal access behavior is defined
- debug hooks are build-gated

## Phase 2: Harden Verification

Deliverables:
- protocol assertions
- scoreboard coverage
- deterministic regressions
- code coverage and functional coverage plan

Current known gaps:
- AXI monitors, checkers, and the active master can now operate with ID-aware
  transaction tracking. Normal regression still signs off the current RTL fabric
  as a single-outstanding contract until the interconnect is upgraded.
- Protocol checkers cover the UVM external master, SRAM observation port, and
  internal `soc_fabric` links `axim`, `axim2`, `axim3`, and `axim4`. The
  current checker configuration still enforces the single-outstanding contract,
  even though the checker implementation can track ID-aware multi-outstanding
  responses.
- `soc_axi_overlap_probe_test` is available as a focused overlap-generation
  probe for the verification BFM. It is not yet an RTL multi-outstanding
  signoff test because the fabric contract has not been widened.
- The first response-contract scoreboard, functional coverage model, GPIO APB
  data scoreboard, and UART/timer/PIC APB register scoreboard are connected.
- `soc_dma_copy_test` now covers the basic DMA programming path and SRAM alias
  copy datapath: the external UVM master seeds source words, configures
  SRC/DST/LENGTH/CTRL over APB, polls DONE, reads the destination burst, and
  compares copied data in the sequence. The scoreboard also models DMA APB
  registers, predicts destination data from known SRAM source words, checks
  ID=2 DMA writes at the SRAM observation port, and makes DMA-written bytes
  visible to later SRAM read checks.
- `soc_dma_irq_test` extends the DMA path with interrupt observation: it enables
  PIC mask bit 3, starts DMA with INT_EN, checks PIC STATUS/ACTIVE assertion,
  clears DMA DONE, and checks PIC STATUS/ACTIVE deassertion.
- `soc_timer_irq_test` extends interrupt observation beyond DMA: it enables PIC
  mask bit 2, starts the APB timer with interrupt enable, checks PIC
  STATUS/ACTIVE assertion, clears timer `INT`, checks PIC deassertion, and
  contributes dedicated event/latency functional coverage.
- Flash read data checks are connected for zero-filled reads and for the
  Phase 3A loadable AXI flash-image model. SPI-serial flash protocol timing and
  boot-from-flash signoff remain separate future work.
- The SRAM data scoreboard covers external master-owned byte lanes, directed
  alias-window and boot-window write/read traffic, masked byte writes, long INCR
  bursts, and DMA-written bytes when the source data is known. Directed DMA/PIC
  and timer/PIC interrupt behavior is covered. The timer+DMA combined PIC case
  is now covered through `soc_pic_combined_irq_test`, including timer-only,
  both-active, DMA-only, and all-clear active states. Phase 3A covers UART TX
  IRQ, loadable flash-image reads, APB wait/PSLVERR stress, and a CPU/CP0
  firmware smoke gate. Phase 3B closes UVM-visible CPU exception/interrupt
  entry/return coverage. Phase 3C closes the actual PIC multi-source mask
  arbitration contract for UART, timer, and DMA. Priority-order signoff remains
  unclaimed because the current PIC has no priority encoder output.
- `soc_apb_burst_stress_test` extends APB read-burst coverage across UART,
  timer, GPIO, DMA, PIC, and an unused APB slot. The APB register scoreboard now
  checks every read beat in a burst, so multi-beat APB register traffic is
  covered by both sequence-level expected data checks and scoreboard checks.
- `soc_jtag_reset_recovery_test` now gates the fixed JTAG debug stimulus and
  reset recovery path. It checks that JTAG AXI commands complete, reset is
  pulsed during AW/W/AR states, TAP reset recovery completes, and at least nine
  recovery reset pulses are observed. The passive AXI monitor is reset-aware so
  async reset pulses do not splice pre-reset and post-reset bursts together.
  The test now also contributes dedicated functional coverage through
  `jtag_reset_event_cg` and `jtag_recovery_pulse_cg`; both groups are 100.00%
  in the latest coverage regression.
- The Phase 2 directed regression gate is scripted. `make phase2-regression`
  builds firmware, compiles the UVM testbench once, runs
  `tb/uvm_tb/phase2_directed_tests.txt`, and writes an archived summary at
  `build/uvm/directed/directed_summary.txt`. The latest internal-checker
  baseline used `UVM_DIRECTED_DIR=build/uvm/directed_apb_burst_stress_closed`
  and passed 16/16 tests.
- The single-test and directed testlist runners now fail on simulator exit
  failures, SystemVerilog/VCS `Error`/`Fatal` messages, direct UVM
  error/fatal reports, nonzero UVM summary counts, checker/scoreboard errors,
  and missing firmware artifacts. Firmware-driven mailbox success remains an
  accepted completion path for legacy `$finish` tests.
- The coverage-enabled Phase 2 gate is now scripted through
  `make phase2-regression UVM_ENABLE_COV=1`. The flow removes stale
  `directed.vdb`, runs the same 16-test directed list with coverage enabled,
  generates `urgReport`, and appends the URG dashboard to
  `directed_summary.txt`. The current
  `directed_cov_apb_burst_stress_closed` baseline passed 16/16 with total score
  55.46%, line 45.19%, condition 52.60%, toggle 40.58%, FSM 49.38%, branch
  45.04%, and functional group 100.00%. Module definition coverage is score
  82.68%, line 75.52%, condition 89.24%, toggle 74.60%, FSM 94.44%, and branch
  79.59%. `soc_bus_coverage::bus_contract_cg`, the two JTAG/reset covergroups,
  `timer_irq_event_cg`, `timer_irq_latency_cg`, `pic_combined_irq_event_cg`,
  `pic_combined_irq_state_cg`, and `apb_burst_stress_cg` are all 100.00%. The
  low top-level instance score is expected until full SoC/CPU paths, broader
  SRAM stress, and CPU-level interrupt/exception scenarios are covered. UART TX
  IRQ and loadable flash-image reads are closed by the Phase 3A gate; UART RX
  IRQ remains future because there is no RX datapath.
- `make phase2-complete` is the final Phase 2 closure entry point. It runs the
  non-coverage and coverage Phase 2 directed gates, scans logs for project
  failure patterns, checks required URG groups, and writes
  `build/uvm/phase2_complete/phase2_completion_report.md`.

Exit criteria:
- directed regressions run without hierarchy hacks: complete
- failures are attributable: complete
- coverage gaps are tracked or explicitly deferred beyond the current RTL
  contract: complete

## Phase 3: Productization

Deliverables:
- lint cleanups
- CDC/RDC closure plan
- synthesis-friendly wrappers
- release checklist

Phase 3A status:
- `apb_uart` now exposes `tx_int`/`rx_int`; TX writes set a pending TX IRQ,
  `IRQ_STATUS` reports it, and `IRQ_CLEAR` clears it. RX IRQ remains zero until
  an RX datapath exists.
- `mips_soc_impl` maps UART TX/RX IRQs into PIC bits 1/0 and keeps the hooks
  behind the existing product/verification boundary.
- `axi2apb_bridge` now propagates APB `PSLVERR` into write `BRESP=SLVERR`.
- `mips_soc_impl.ENABLE_APB_FAULT_INJECTOR` adds a verification-only APB slot
  for wait-state and `PSLVERR` stress.
- `mips_soc_impl.ENABLE_FLASH_IMAGE_MODEL` selects a verification-only
  loadable AXI flash model driven by `+FLASH_IMAGE=<hex>`.
- `soc_uart_irq_test`, `soc_apb_fault_stress_test`, and
  `soc_flash_image_test` form `tb/uvm_tb/phase3_directed_tests.txt`.
- `make cpu-cp0-gate` runs firmware through timer interrupt, syscall,
  reserved-instruction, AdEL, and ERET paths and checks `CPU_CP0_SUMMARY`.
- `make phase3-complete` passed: 3/3 directed, 3/3 coverage, all required
  Phase 3A groups at 100.00%, and CPU/CP0 firmware gate pass.

Still outside Phase 3A:
- RTL multi-outstanding support. The checker and BFM can track IDs, but normal
  fabric signoff still enforces the single-outstanding product contract.
- SPI-serial flash protocol timing and boot-from-flash signoff.

Phase 3B CPU/CP0 UVM coverage status:
- `soc_verif_top` exposes verification-only CPU/CP0 observation signals for
  exception request/code, interrupt request, ERET, EXL, and EPC.
- `tb_top` records CPU/CP0 exception-entry, interrupt, syscall, RI, AdEL, ERET,
  EXL set/clear, EPC update, and mailbox-success observations without changing
  product RTL behavior.
- `soc_cpu_cp0_exception_test` disables the legacy mailbox `$finish`, waits for
  firmware success, and samples `cpu_cp0_exception_event_cg` and
  `cpu_cp0_exception_count_cg`.
- `make phase3b-complete` passed: 1/1 directed, 1/1 coverage, required Phase 3B
  CPU/CP0 groups at 100.00%, with dynamic counts
  `intr=8 syscall=1 ri=7 adel=1 eret=16`.

Phase 3C PIC mask arbitration status:
- `soc_pic_mask_arbitration_test` drives UART TX, timer, and DMA pending
  sources at the PIC at the same time.
- `axi_pic_mask_arbitration_seq` checks `ACTIVE = STATUS & MASK` for zero mask,
  UART-only, timer-only, DMA-only, UART+DMA, timer+DMA, and all-source masks.
- `make phase3c-complete` passed: 1/1 directed, 1/1 coverage, required Phase 3C
  PIC groups at 100.00%.
- No priority-order claim is made because `apb_pic` exposes raw status, mask,
  active bits, and an OR-reduced `cpu_int`, not a priority-encoded source ID.

Phase 3D architecture hardening plan:
- Make the product wrapper explicitly disable every verification-only
  `mips_soc_impl` feature parameter. The product build must not depend on
  inherited defaults for the external AXI master, APB fault injector, or
  loadable flash-image model.
- Keep `soc_verif_top` as the only integration view that enables those hooks for
  UVM stress, APB fault testing, and loadable XIP-window data checks.
- Start retiring `mips_soc_impl` as the long-term integration owner by splitting
  stable product subsystems in this order:
  1. peripheral subsystem around the APB bridge, UART, timer, GPIO, DMA, PIC, and
     interrupt-source wiring;
  2. memory subsystem around SRAM/DDR model selection, boot window, SRAM alias,
     and future boot ROM/flash source selection;
  3. debug subsystem around JTAG AXI master wiring and reset recovery policy;
  4. core subsystem around CPU/cache interfaces and a stable verification-only
     exception/trace observation boundary.
- Do not widen the fabric to multi-outstanding as part of this cleanup. That is a
  separate contract-expansion phase.
- Do not claim SPI boot-from-flash as closed while the current passing tests sign
  off the AXI flash-image/XIP verification window only.

Phase 3D exit criteria:
- `rtl/mips_soc.v` explicitly disables all verification-only hooks.
- Documentation identifies `mips_soc_impl` as a transitional integration module
  and lists the target subsystem partition.
- `rtl/soc_peripheral_subsystem.v` owns the APB/peripheral interrupt boundary.
- `rtl/soc_memory_subsystem.v` owns the SRAM model and flash/XIP slave-window
  selection boundary.
- `rtl/soc_debug_subsystem.v` owns the JTAG/debug master boundary.
- `rtl/soc_core_subsystem.v` owns the CPU/cache and CP0 interrupt-input boundary.
- Any new verification observation points are stable interfaces or binds, not new
  scattered hierarchy paths.
- Existing Phase 2/3A/3B/3C regression entry points remain valid after the
  hardening changes.

Phase 3D status:
- Structural subsystem extraction is complete for product wrapper hardening,
  peripheral, memory, debug, and core boundaries.
- The core wrapper has passed CPU/CP0 exception smoke, fabric-contract smoke,
  UVM coverage hierarchy smoke, legacy `soc-smoke`, and post-run error scanning.
- The default Phase 3 directed integration regression passed with coverage after
  extraction, including UART IRQ, APB wait/PSLVERR stress, and AXI
  flash-image/XIP window coverage.
- UVM CPU/CP0/JTAG observation now crosses a named `soc_observation_if`. A
  verification-only `soc_observation_bind` drives the interface from the
  centralized `soc_verif_top` scope, so the verification wrapper no longer owns
  direct observation assignments.
- Legacy `tb/soc_test` hierarchy probes now cross
  `soc_legacy_observation_if` and are driven by `soc_legacy_observation_bind`;
  the legacy smoke wrapper also connects product SPI outputs explicitly. The
  old direct SRAM array preload has been replaced by a simulation-only
  `preload_sram_hex()` task chain from `mips_soc` down to the memory model.
  The cleanup passed legacy smoke, the CPU/CP0 firmware gate, and the
  coverage-enabled Phase 3 directed gate. Reducing or retiring the legacy bind
  signal set remains follow-on architecture debt, not a blocker for Phase 3D
  structural closure.
- Legacy `exclude5.el` is now a comment-only placeholder. The previous active
  reset-path FSM transition exclusions did not match the current coverage
  database and caused URG `Warning-[UCAPI-EL-INVFSM]`; keeping them was
  misleading because they were not applied. New FSM exclusions must be derived
  from a current full-exclusion dump and reviewed against current RTL hierarchy
  names.

Post-rename DUT integration completeness audit:
- Purpose: the following modules have recently been integrated or structurally
  inserted into the DUT and must not be treated as product-complete solely
  because smoke/regression tests pass. Each item needs a dedicated feature
  completeness review against its block spec, directed tests, UVM coverage,
  firmware scenarios, and negative/error-path behavior.
- `mips_mdu`: integrated in `mips_ex_stage`; `_v2` transitional module/signal
  naming is being removed. Audit remaining MDU ISA completeness, HI/LO hazard
  behavior, stall/flush semantics, divide corner cases, and performance impact.
- `apb_axi_dma`: integrated in `soc_peripheral_subsystem`; `_v2` transitional
  naming is being removed. Audit channel model, descriptor/scatter-gather
  behavior, AXI burst legality, APB programming model, interrupt/error handling,
  alignment/length corner cases, and scoreboard coverage.
- `apb_vic`: integrated as the interrupt controller baseline. Audit source
  mapping, mask/active behavior, priority/vector semantics, edge-vs-level
  handling, software-trigger behavior, nesting expectations, and formal
  priority proofs before claiming product-level VIC closure.
- `apb_uart_16550`: integrated as the UART baseline. Hardened in Phase 4E under
  PC16550D-compatible contract with RX timeout, FCR reset, IIR priority, and
  modem loopback.
- `l2_cache`: real caching is enabled in the DUT through `SOC_L2_CACHING`. The
  default impl is reset-safe **write-through / no-write-allocate**
  (`l2_cache_wt`, 128 KB 8-way, caches reads, forwards writes to SRAM, no dirty
  state). The **write-back / write-allocate** impl (`l2_cache_caching`, NINE,
  single-outstanding, dirty eviction, refill/write error propagation, snoop
  tie-off) is available behind `SOC_L2_WRITEBACK` and is now also reset-safe: its
  tag/data/valid/dirty/PLRU arrays are retention memory (cold-boot `initial` only,
  not wiped by warm `rst_n`), mirroring `axi_sram.v`, so dirty lines survive the
  TB's async reset pulses. Both are closed under Phase 4F (see above), service
  aligned word-INCR bursts including line-crossing bursts, and return `SLVERR`
  only for genuinely-illegal requests. Follow-up audit must not over-claim MSHR,
  multi-outstanding, coherent snoop, ECC, or performance closure until those
  features are implemented and verified.

Exit criteria:
- architecture is signoff-ready
- debug and test hooks are gated
- source tree is free of generated artifacts

## Phase 4A: Commercial DUT Block Readiness Baseline

Deliverables:
- Block specs and RTL headers updated to reflect actual integration state and boundaries.
- Hardened DMA AXI error response handling and MDU signed accumulation logic.
- `make dut-block-unit-gate` entry point implemented for focused block unit tests (`mips_mdu`, `apb_axi_dma`, `apb_vic`, `apb_uart_16550`, `l2_cache`).
- Extended focused unit test coverage for MDU signed/accumulate/div-zero, DMA scatter-gather and AXI error, VIC map & tie-break, UART DLAB/SCR & FIFO/IRQ, and L2 dirty/error.
- Verified unit gate, firmware smoke, and UVM smoke gates pass cleanly.

## Phase 4B: MDU CPU ISA Closure

Deliverables:
- Upgrade CPU MDU control plumbing from 3-bit legacy encoding to 4-bit `mips_mdu` operation encoding in `rtl/cpu/mips_control.v`, `rtl/cpu/mips_id_stage.v`, `rtl/cpu/mips_id_ex_reg.v`, `rtl/cpu/mips_ex_stage.v`, and `rtl/cpu/mips_cpu.v`.
- Decode `MADD`, `MADDU`, `MUL`, `MSUB`, and `MSUBU` using the standard MIPS32 R2 SPECIAL2 opcode.
- Route `MUL` low-word result to GPR writeback (`rd`) through `ex_out`.
- Add dedicated `mdu_cpu` firmware test exercising signed/unsigned accumulate, subtract accumulate, negative `MUL`, `MUL` destination writeback, and `MFHI/MFLO` checks.
- Add `make mdu-cpu-gate` entry point.

## Phase 4C: DMA Commercial Closure

Deliverables:
- Hardened `apb_axi_dma` for direct copy, scatter-gather, error handling (`ERR_ALIGN`, `ERR_AXI_READ`, `ERR_AXI_WRITE`, `ERR_DESC`, `ERR_DESC_LIMIT`), busy reprogramming protection, bounded descriptor chains (`MAX_DESCRIPTORS=16`), and status W1C/re-arm semantics under the single-outstanding AXI fabric contract.
- Updated `docs/block_specs/dma_spec.md` with full commercial DUT specification.
- Extended `tb/unit/dma/tb_dma.v` unit test suite covering direct, SG, AXI error, alignment rejection, malformed descriptor, descriptor limit, busy protection, and W1C/IRQ test cases.
- Added product firmware test `tb/soc_test/fw/tests/dma_cpu/` and `make dma-cpu-gate` top-level entry point.
- Clarified non-claims: single-beat single-outstanding contract (no burst/multi-outstanding claim), no IOMMU/coherency claim, no formal/lint/synthesis/timing closure claim; coverage exclusion maintenance remains separate.

## Phase 4D: VIC Commercial Closure

Deliverables:
- Hardened `apb_vic` to ensure single sequential state writers for all state registers (`active_r`, `edge_pending_r`, `soft_r`, `enable_r`, `type_r`, `polarity_r`, `prio_r`).
- Reconciled interrupt source map with actual SoC integration (`rtl/soc_peripheral_subsystem.v`):
  - Source 0: `uart_rx_int`
  - Source 1: `uart_tx_int`
  - Source 2: `timer_int`
  - Source 3: `dma_int`
  - Sources 4..31: tied low/reserved
- Extended `tb/unit/vic/tb_vic.v` to cover reset defaults, enable set/clr, priority arbitration & tie-break, `VEC_ID` read accept event, repeated read protection, nested interrupt suppression, higher-priority preemption, ACK rollback, level high/low & rising/falling edge modes, software triggers, mask while active, 32-source consistency, legacy low offsets, and unsupported address handling.
- Added product firmware gate `tb/soc_test/fw/tests/vic_cpu/` and `make vic-cpu-gate` top-level entry point.
- Updated `docs/block_specs/vic_spec.md` and `docs/commercial_dut_block_readiness_plan.md`.
- Explicit non-claims: single-line IRQ + APB dispatch contract (no CPU EIC/VEIC claim), no MSI claim, no multicore routing claim, no formal proof claim, no synthesis/timing closure claim; coverage exclusion maintenance remains separate.

## Phase 4E: UART Commercial Closure

Deliverables:
- Hardened `apb_uart_16550` under PC16550D-compatible contract:
  - DLAB DLL/DLM vs RBR/THR/IER access separation and SCR 8-bit read/write.
  - FCR FIFO mode (1/4/8/14 trigger levels) vs FIFO disabled (1-byte compatibility mode with OE overrun on unread data).
  - Self-clearing FCR reset bits (`RCVR_RESET`, `XFR_RESET`).
  - RX character timeout interrupt after 4 character times when data is below threshold.
  - IIR priority order (LSI > RDA/CTI > THRE > MSR) with accurate FCR FIFO enable prefix.
  - Modem loopback mapping and MSR 4-bit delta flags cleared on MSR read.
  - APB `pstrb[3:0]` byte-lane selection contract.
  - APB `pready=1`, `pslverr=0`, and unsupported address read zero behavior.
- Extended `tb/unit/uart/tb_uart_16550.v` covering 15 unit verification test cases.
- Added product firmware gate under `tb/soc_test/fw/tests/uart_cpu/` and `make uart-cpu-gate` top-level entry point.
- Updated `docs/block_specs/uart_16550_spec.md`, `docs/commercial_dut_block_readiness_plan.md`, and `docs/refactor_roadmap.md`.
- Documented explicit non-claims: Linux 8250 system-level driver compatibility, real-board baud tolerance/CDC/RDC, complete CTS/RTS flow-control closure, DMA mode, formal proof, synthesis/timing, and coverage exclusion maintenance.

## Phase 4F: L2 Cache Commercial Closure

Status: CLOSED. Full acceptance sequence passed with `SOC_L2_CACHING=1`:
`make dut-block-unit-gate` (5/5), `make l2-cpu-gate`, `make firmware`, `make uvm`
(default `soc_bus_stress_test`, 0 UVM_ERROR / 0 SB_RESP), `soc_test run.sh`
(clean `$finish`), and `git diff --check`.

Follow-on fix (2026-07-29): the DUT default caching impl is now **write-through /
no-write-allocate** (`rtl/cache/l2_cache_wt.v`), not write-back. The TB pulses
async global `rst_n` mid-run (JTAG reset-recovery coverage); a write-back L2 holds
written data as dirty until eviction, so a reset wipes it before writeback and
silently drops SRAM-alias writes (`soc_axi_attribute_cross_sweep_test` read back
0). Write-through forwards every write to SRAM immediately, so committed writes
survive reset. The write-back/write-allocate impl (`l2_cache_caching`) stays
available behind `SOC_L2_WRITEBACK`. Three latent write-through defects were fixed
(multi-beat write re-forwarding AW → downstream deadlock; read-miss partial-line
refill → stale 0; line-crossing read burst not re-looking-up per beat), covered by
`tb/unit/l2/tb_l2_wt.v`. The DUT block unit gate compiles the WB impl explicitly
via `+define+SOC_L2_WRITEBACK` (its 16 contracts are write-back-specific); the
write-through path is validated at SoC level. Re-verified: phase3 completion gate,
DUT block unit gate, 0 UVM errors/fatals.

Follow-on fix (2026-07-29, reset-safety): the write-back impl `l2_cache_caching`
is now itself reset-safe. Its `valid_ram`/`dirty_ram`/`plru_ram` (with the already-
retention `tag_ram`/`data_ram`) are now retention memory — cold-boot `initial`
init, not wiped by warm `rst_n`; only FSM control state resets. This is symmetric
with the retention SoC SRAM model (`axi_sram.v`) and removes the silent dropped-
write liability that motivated the write-through default. `tb/unit/l2/tb_l2.v`
Test 19 covers write-dirty → warm-reset → L2-hit readback (no downstream refill).
Verified: `make dut-block-unit-gate` 5/5 (L2 19/19); `tb_l2_wt.v` still passes.

Follow-on (2026-07-29, write-back SoC signoff): write-back is now signed off at SoC
level via an opt-in `L2_WRITEBACK=1` build switch (UVM/soc_test compile scripts +
Makefile `uvm`/`phase3-complete`/`soc-smoke`; appends `+define+SOC_L2_WRITEBACK`,
default unchanged = write-through). The deferred "scoreboard SRAM-truth model" concern
proved a non-issue: the scoreboard builds its SRAM model from AXI taps upstream of L2
and never reads physical SRAM, so write-back's deferred downstream writes are invisible
to it (L2 is the single coherence point and returns dirty on hit). Verified with
`L2_WRITEBACK=1`: phase3-complete PASS, `soc_bus_stress_test` 0 UVM_ERROR/0 UVM_FATAL,
soc-smoke PASS, phase2 directed 16/16 incl. `soc_jtag_reset_recovery_test` (async
`rst_n` pulses — the direct reset-safety validation). Write-through stays the default.

Two defects were fixed to reach
closure: an ungated per-cycle `$display` in the `l2_cache_caching` FSM was
removed, and a sample/drive `WLAST` race in the `tb_l2.v` `cache_write_raw`
helper (which stalled the line-crossing write test) was corrected. The caching
FSM itself already services aligned word-INCR line-crossing bursts by
re-looking-up per beat; the previously reported `SB_RESP` UVM regression did not
reproduce on the current tree.

Deliverables:
- Hardened `l2_cache` / `l2_cache_caching` under current single-outstanding blocking contract:
  - Upstream request validation returning deterministic `SLVERR` (`2'b10`) for unaligned addresses, unsupported size (!=3'b010), non-INCR bursts, line-crossing bursts, or len>7.
  - Downstream `RRESP`/`BRESP` error propagation with no invalid line installation on refill error and dirty victim preservation on eviction error.
  - Single-outstanding rejection and backpressure (`s_arready=0`, `s_awready=0` while a request is active).
  - Optimized multi-beat read hit bursts holding `s_rvalid` continuously without bubble cycles.
  - Reserved snoop tie-off without side effects.
- Extended `tb/unit/l2/tb_l2.v` to cover all 16 required commercial unit test cases.
- Added product firmware test under `tb/soc_test/fw/tests/l2_cpu/` and `make l2-cpu-gate` top-level entry point.
- Updated `docs/block_specs/l2_spec.md`, `docs/commercial_dut_block_readiness_plan.md`, and `docs/refactor_roadmap.md`.
- Documented explicit non-claims: non-blocking L2, MSHR, writeback buffer, multi-outstanding AXI, coherent snoop/directory, ECC/SECDED, formal proof, synthesis/timing, and coverage exclusion maintenance.

## Phase C.3: Multi-Outstanding AXI Crossbar

Status: DELIVERED (functional signoff under the current contract). The legacy
single-outstanding arbiter cascade (`axi_arbiter_2x1`, `axi_arbiter_2x1_full`,
`axi_decoder_1x3` — now deleted) is replaced by a true M×N crossbar
`rtl/axi/axi_crossbar.v`, instantiated inside the `soc_fabric.v` wrapper (flat
port list and `ENABLE_EXT_AXI_MASTER` param unchanged, so zero blast radius at
`mips_soc_impl.v`).

Delivered:
- Concurrent cross-slave transactions: masters hitting different slaves proceed
  in parallel (the key win over the old shared trunk).
- Per-master address decode -> target slave (mirrors the old decoder map exactly:
  SRAM 0x0/0xA0000000, APB 0x40000000, FLASH 0x10000000, else DECERR).
- Per-slave QoS-priority arbiter (max AxQOS wins) with round-robin tie-break.
  Static per-master QoS classes in `soc_config.vh` (D$>I$>DMA>jtag>ext).
- Per-slave outstanding FIFO {master_idx,id,len} routes in-order responses to the
  origin master; original id passes through (slaves are in-order, so no ID
  widening needed). AR/AW grant lock holds address-channel payload stable while
  xVALID && !xREADY.
- Synthesized DECERR slave (per-master multi-beat DECERR reads + single-beat
  DECERR write) — preserves legacy semantics without cross-master blocking.

Verification:
- `make fabric-unit-gate` (3/3): tb_xbar_core (R/W, DECERR, bursts),
  tb_xbar_qos (QoS priority + RR), tb_xbar_multi_ot (N_OT=4 boundary depth +
  cross-slave concurrency).
- SoC regression green with the crossbar: phase2 directed 16/16 (incl.
  soc_fabric_contract_test, soc_axi_id_sweep_test, soc_axi_overlap_probe_test,
  soc_jtag_reset_recovery_test, soc_bus_stress_test), phase3-complete, make uvm,
  make soc-smoke. The overlap-probe checker caught a real AR-payload-stability
  bug during bring-up, fixed by the grant lock.

Honest scope / non-claims:
- Per-slave outstanding depth `SOC_XBAR_N_OT=4` is realized at the crossbar
  BOUNDARY. End-to-end same-slave depth stays capped at 1 by today's single-
  outstanding L2/APB/flash slaves; same-slave throughput gain awaits a non-
  blocking slave AND a multi-outstanding master. A non-blocking full-MSHR L2
  (`rtl/cache/l2_cache_nb.v`, `+define+SOC_L2_NONBLOCKING`) now exists and is
  proven in `tb/unit/l2nb`, but the SoC's L1s are still blocking single-
  outstanding, so end-to-end same-slave depth remains 1 until CPU/L1 hit-under-
  miss lands. Cross-slave concurrency is realized now.
- QoS is a static per-master class today (masters drive constant AxQOS); dynamic
  per-transaction QoS is deferred until masters emit AxQOS.
- No formal proofs (no formal tool in-environment) and no commercial AXI VIP
  compliance; covered by directed unit tests + self-built protocol checkers +
  bus stress. No synthesis/timing/lint/CDC closure claim.
- The verification protocol checkers were re-homed from the old shared-trunk nets
  onto the three crossbar slave ports (still single-outstanding, matching the
  slaves); the ext-master checker was relaxed to allow multiple outstanding.
- Coverage exclusion entries for the three deleted modules were removed from
  `tb/coverage/manifest.json`, `exclusion_manifest.json`, and the `.el` files. A
  full coverage regeneration is separate (belongs to the parked coverage-closure
  effort); the pre-existing manifest/.el audit desync is unchanged by this work.

## Phase C.4: CPU/L1 Hit-Under-Miss (in progress)

Goal: let the CPU accept new memory ops while an L1 D-cache miss is still
outstanding, so the multi-outstanding fabric/non-blocking L2 delivered in
Phase C.2/C.3 finally has a source of concurrent same-slave traffic (see the
Phase C.3 non-claims above — same-slave depth is capped at 1 until this
lands). Landing in stages so each one is independently provable against the
previous baseline before growing scope, mirroring how Phase C.2/C.3 staged
their own hardening:

- **Stage 1 (delivered, `46fda4c`)**: `rtl/cpu/mips_rob.v`, a parameterized
  in-order-retirement completion buffer (mini-ROB) replaces the plain
  MEM/WB pipeline register (`mips_mem_wb_reg`). At `DEPTH=1` it is a
  bit-exact drop-in — same three-way reset/flush/stall commit register
  driving the same `wb_*` bundle. Purpose: rewire retirement/exceptions
  through the new module boundary with zero functional change before any
  stage grows depth or run-ahead.
- **Stage 2 (delivered, this commit)**: `mips_rob` grows a real
  `DEPTH>=2` circular-buffer skeleton (slot array, per-slot valid/ready
  bits, head/tail pointers) instantiated at `DEPTH=2` in `mips_cpu.v`. The
  D-cache is still blocking, so every allocated entry is ready in the same
  cycle it's produced — occupancy is a structural invariant of 0 across
  every clock edge, so the buffered path is bookkept every cycle but stays
  dead code, and commit remains bit-identical to Stage 1. Proven with
  `tb/unit/rob/tb_mips_rob.v`, which runs a `DEPTH=1` (golden) and
  `DEPTH=2` (skeleton) instance side by side against identical stimulus
  (back-to-back allocate, stall-hold, flush, exception propagation) and
  diffs every `wb_*` output every cycle — now the 8th block in
  `make dut-block-unit-gate` (8/8). `make soc-smoke` confirmed unaffected
  (`REGRESSION_TEST_SUCCESS`, same as pre-change baseline).
- **Stage 3 (not started)**: make `dcache.v`'s FSM non-blocking — add an
  MSHR to track one outstanding miss while still accepting new hits (and,
  later, additional misses), so an entry can genuinely go un-ready for
  more than zero cycles for the first time. This is the point where
  `rob_valid`/`rob_ready` in the Stage 2 skeleton start mattering and out-
  of-order slot writeback + in-order head commit become live code paths
  instead of dead bookkeeping.
- **Stage 4 (not started)**: rework ID-stage hazard/forwarding
  (`mips_id_stage.v`'s `fw_mem_we`/`fw_wb_we` forwarding and load-use
  stall) to consult in-flight ROB entries rather than only EX/MEM, since a
  source register can now be produced by a still-outstanding (not-yet-
  ready) ROB slot.
- **Stage 5 (not started)**: grow `DEPTH` beyond 2 and add run-ahead
  profiling to characterize real throughput gain once Stage 3/4 land.

Non-claims: no out-of-order issue/execute (this is strictly an in-order-
issue, in-order-commit design — only the memory-completion stage tolerates
a miss in flight), no register renaming, no speculative memory
disambiguation. This is a narrowly-scoped MEM-stage hit-under-miss buffer,
not a general out-of-order core.
