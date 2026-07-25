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
- Next work item is hardening the remaining fabric behavior with an RTL-level
  multi-outstanding response model, broader interrupt/exception coverage,
  richer flash-image traffic, and the remaining peripheral data scoreboards.

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

Exit criteria:
- architecture is signoff-ready
- debug and test hooks are gated
- source tree is free of generated artifacts
