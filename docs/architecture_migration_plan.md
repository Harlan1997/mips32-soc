# Architecture Migration Plan

## Goal

Turn the current teaching-style SoC integration into a production-grade chip
architecture with a clear product boundary, a separate verification boundary,
and a single system contract.

## Step 1: Freeze the System Contract

Freeze these items before any deep RTL refactor:
- top-level ports
- memory map
- AXI/APB widths
- interrupt map
- reset behavior
- debug/test feature switches

## Step 2: Split Top-Level Responsibilities

Create two explicit integration views:
- product top: chip-facing RTL only
- verification top: UVM, monitors, force hooks, coverage, stress masters

Initial implementation:
- `rtl/soc_top.v` is the product-facing wrapper.
- `rtl/mips_soc.v` is the product-facing SoC wrapper.
- `rtl/mips_soc_impl.v` contains the transitional integrated implementation.
- `tb/uvm_tb/tb_top/soc_verif_top.sv` is the verification wrapper.
- UVM now instantiates `soc_verif_top`, which contains `mips_soc_impl u_dut`.

Status:
- Initial product/verification top split is complete.
- Product-facing `mips_soc` no longer exposes the verification-only external
  AXI master.
- UVM path enables the same path only through `soc_verif_top`.
- Remaining debt: `mips_soc_impl` remains a transitional subsystem wiring owner.
  Fabric, core, memory, peripheral, and debug integration have been split into
  named product-owned blocks.

## Step 2A: Split Verification Bus Roles

The first UVM cleanup is to remove mixed-role AXI interfaces. The previous
testbench used one `axi_if` type for active slave driving, active master
driving, and passive monitoring. That made the clocking-block outputs structural
drivers even when the interface instance was only being observed, causing VCS
multi-driver warnings.

Implementation:
- `tb/uvm_tb/agents/axi_if.sv` is now passive monitor-only.
- `tb/uvm_tb/agents/axi_master_if.sv` owns the active external AXI master BFM
  request-side drives.
- `tb/uvm_tb/agents/axi_slave_if.sv` preserves an active slave-memory BFM role
  for future external-memory verification.
- `tb/uvm_tb/agents/axi_master_driver.sv` now uses `virtual axi_master_if`.
- `tb/uvm_tb/agents/axi_driver.sv` now uses `virtual axi_slave_if`.
- `tb/uvm_tb/tests/soc_base_test.sv` marks the internal SRAM observation agent
  as `UVM_PASSIVE` and the external verification master as `UVM_ACTIVE`.

Status:
- Complete for compile/elaboration and first transaction-level checking.
- VCS compile passes without the previous `ICPSD_W` illegal driver-combination
  warnings.
- The AXI monitors reconstruct ID-aware read/write transactions and feed both
  the fabric scoreboard and transaction-level coverage model.
- Remaining debt: the active master and RTL fabric still enforce the current
  single-outstanding contract before the fabric is upgraded to support multiple
  outstanding requests.

## Step 3: Centralize Shared Definitions

Move all shared constants into one package or equivalent source of truth:
- address decode constants
- bus widths
- register offsets
- boot address
- feature enable macros

Initial implementation:
- `rtl/include/soc_config.vh` defines the first shared contract.
- `rtl/axi/axi_decoder_1x3.v` now consumes the shared address decode nibbles.
- AXI response encodings are defined in `soc_config.vh` and used by directed
  verification for unmapped-access checks.

## Step 4: Rebuild the SoC Fabric

Replace ad hoc interconnect layering with a documented fabric:
- explicit master/slave routing
- one decode authority
- deterministic arbitration policy
- defined error response for unmapped access

Initial implementation:
- `rtl/soc_fabric.v` now owns the SoC AXI fabric boundary.
- `mips_soc_impl` no longer instantiates the cascaded arbiter chain or the AXI
  1x3 decoder directly.
- Private `axim*` intermediate links are contained inside `soc_fabric`.
- Fabric ports expose named masters: I-cache, D-cache, DMA, JTAG, and optional
  external verification master.
- Fabric ports expose named slaves: SRAM/DDR model, APB bridge, and SPI flash.

Status:
- Complete for structural extraction and first-pass fabric hardening.
- VCS compile passes after the extraction and hardening.
- Firmware smoke test reaches `REGRESSION_TEST_SUCCESS`.
- `axi_decoder_1x3` no longer defaults all unknown regions to SRAM. SRAM is
  now explicitly selected only through the boot window and the documented
  uncached alias window.
- Unmapped reads and writes now complete internally with AXI `DECERR`.
- `soc_unmapped_error_test` checks the write response and a multi-beat read
  response path.
- The 2x1 arbiters now use single-outstanding round-robin arbitration instead
  of fixed priority. Address channel payloads are latched while waiting for the
  downstream slave, so an upstream master cannot change the routed request while
  ready is low.
- `axi_stress_seq` is now non-destructive while firmware is running: it stresses
  read paths through mapped windows and write response paths through unmapped
  DECERR traffic instead of writing over firmware SRAM.
- `tb/uvm_tb/checkers/axi_protocol_checker.sv` now checks the verification
  master and the observed SRAM AXI port for VALID/READY payload stability,
  single-outstanding compliance, write/read burst beat counts, WLAST/RLAST
  placement, and responses without an outstanding transaction. The checker
  implementation now has an ID-aware queue mode for future multi-outstanding
  use: write data is matched to AW order, B responses are matched by `BID`,
  read data is matched by `RID`, and legal response reordering across IDs can
  be checked when `REQUIRE_SINGLE_OUTSTANDING` is disabled.
- The same AXI protocol checker is now bound into `soc_fabric` on the internal
  `axim`, `axim2`, `axim3`, and `axim4` links. These binds are verification
  only and do not add monitor ports to the product RTL wrappers.
- The SRAM observation port in `soc_verif_top` now exposes the full AXI
  handshake and response set instead of only request-side signals.
- `axi_monitor` and `axi_master_monitor` now reconstruct complete AXI read and
  write transactions from handshake events and publish them through analysis
  ports. Their reconstruction is ID-aware: AW/AR requests are queued, write
  responses are matched by `BID`, read data is matched by `RID`, and same-cycle
  address/data handshakes are handled in deterministic channel order.
- `soc_scoreboard` is connected to both monitor streams. It checks mapped versus
  unmapped response contracts, read-only flash write behavior, and that traffic
  observed at the SRAM port belongs to the documented SRAM windows.
- `soc_flash_write_error_test` directly covers the read-only flash `SLVERR`
  contract.
- `soc_bus_coverage` samples transaction source, read/write direction, address
  window, response type, burst length, transfer size, burst type, and key
  crosses. `soc_fabric_contract_test` drives a compact directed set across
  boot SRAM, SRAM alias, APB, flash, and unmapped regions.
- The scoreboard now includes a GPIO APB register model. `soc_gpio_reg_model_test`
  writes and reads GPIO `DATA`/`DIR` registers and checks data consistency in
  both the sequence and the scoreboard.
- The scoreboard now includes UART, timer, and PIC APB register checks.
  `soc_apb_reg_model_test` verifies UART TX/status behavior, timer
  disabled-mode control/load/value/interrupt-clear behavior, and PIC mask plus
  zero-mask active behavior.
- The scoreboard now includes a byte-lane SRAM data model for external
  master-owned bytes. `soc_sram_data_integrity_test` writes and reads a 4-beat
  SRAM alias burst, verifies a masked byte-strobe update, covers a 9-beat long
  INCR burst, and writes/reads the boot SRAM window without assuming ownership of
  firmware memory contents.
- `soc_dma_copy_test` covers the first DMA end-to-end data path. It writes a
  known source burst through the external UVM master, programs DMA SRC/DST/LENGTH
  and CTRL over APB, polls DONE, reads the destination burst, and compares the
  copied words in the sequence. The scoreboard now models DMA APB register
  reads/writes, predicts copied destination words from known SRAM source data,
  checks ID=2 DMA writes at the SRAM observation port, and records DMA-written
  bytes for later SRAM read checks.
- `soc_dma_irq_test` reuses the DMA copy path with INT_EN set, enables PIC mask
  bit 3, verifies DMA interrupt visibility through PIC STATUS/ACTIVE, clears
  DMA DONE, and verifies PIC deassertion.
- `soc_timer_irq_test` covers a second interrupt source by enabling PIC mask
  bit 2, programming the APB timer with interrupt enable, checking PIC
  STATUS/ACTIVE assertion, disabling and clearing the timer interrupt, checking
  PIC deassertion, and restoring the PIC mask.
- `soc_bus_coverage` now includes transaction ID bins and `source x direction x
  ID` coverage. `soc_axi_id_sweep_test` deterministically covers representative
  IDs across SRAM, APB, flash, and unmapped windows.
- The checker exposed a real SPI flash slave bug: flash reads returned `RLAST`
  on the first beat even when `ARLEN` requested a burst. `axi_spi_flash` now
  completes INCR read bursts and returns `SLVERR` for completed write attempts
  instead of silently hanging the write response channel.
- Internal fabric checker binding exposed a real APB bridge bug under
  firmware-driven instruction traffic: an APB-window AXI read with `ARLEN>0`
  was accepted but the bridge returned only one read beat with `RLAST`.
  `axi2apb_bridge` now latches `ARLEN`, `ARSIZE`, and `ARBURST`, issues one APB
  read per AXI read beat, advances INCR addresses by `1 << ARSIZE`, and holds
  `RVALID/RDATA/RRESP/RLAST` until `RREADY`.
- `soc_apb_reg_model_test` now locks this behavior into the directed regression
  with a 4-beat INCR burst across the timer `CTRL`, `LOAD`, `VAL`, and `INT`
  registers, checking every returned data beat and response.
- The external UVM AXI master now has a default-off overlap mode. In overlap
  mode the driver accepts sequence items independently from AW/W/B and AR/R
  channel progress, keeps response queues by AXI ID, and updates the original
  sequence item handles when B/R responses return.
- `soc_axi_overlap_probe_test` enables that overlap mode and issues back-to-back
  SRAM, flash, and unmapped read/write requests across multiple IDs. This
  validates the verification BFM and monitor/scoreboard path without changing
  the product fabric contract.
- The scoreboard now checks flash read data for the current SPI flash model.
  Because `soc_verif_top` ties `spi_miso` low, legal flash reads are expected to
  return zero-filled data beats; directed fabric, ID sweep, and overlap tests
  now exercise this data check.
- `soc_jtag_reset_recovery_test` adds a deterministic JTAG/reset recovery gate:
  it observes the fixed JTAG AXI command sequence, confirms reset injection at
  AW/W/AR states, checks TAP reset recovery completion, and requires at least
  nine recovery reset pulses. The passive AXI monitor now flushes in-flight
  tracking on asynchronous reset so reset recovery tests do not create false
  burst boundary errors. Dedicated JTAG/reset functional coverage is now
  collected by `jtag_reset_event_cg` and `jtag_recovery_pulse_cg`; both are
  100.00% in the latest coverage regression.
- Timer interrupt functional coverage is collected by `timer_irq_event_cg` and
  `timer_irq_latency_cg`; both are 100.00% in the latest coverage regression.
- Combined PIC interrupt functional coverage is collected by
  `pic_combined_irq_event_cg` and `pic_combined_irq_state_cg`. The directed
  scenario asserts timer bit 2 first, then DMA bit 3, checks both-active
  STATUS/ACTIVE, clears timer while DMA remains active, and finally clears DMA;
  both groups are 100.00% in the latest coverage regression.
- APB read-burst stress is covered by `soc_apb_burst_stress_test`, which reads
  UART, timer, GPIO, DMA, PIC, and an unused APB slot with multi-beat bursts.
  The APB register scoreboard now checks every read beat in a burst.
  `apb_burst_stress_cg` is 100.00% in the latest coverage regression.
- Phase 3A adds UART TX interrupt, APB wait/PSLVERR, and loadable flash-image
  verification:
  `soc_uart_irq_test` checks UART TX IRQ state through PIC bit 1 and IRQ clear;
  `soc_apb_fault_stress_test` checks normal APB wait-state completion and a
  gated APB fault slot returning `PSLVERR` on reads, writes, and bursts;
  `soc_flash_image_test` loads `tb/uvm_tb/data/flash_xip_image.hex` through
  `+FLASH_IMAGE` and checks single and burst XIP-window reads.
- CPU/CP0 firmware smoke is now a machine-checked gate through
  `make cpu-cp0-gate`. The current passing summary is
  `CPU_CP0_SUMMARY intr=8 syscall=1 ri=7 adel=1 eret=16`.
- `soc_bus_coverage` now matches the current supported SoC bus contract. The
  model targets OKAY/SLVERR/DECERR responses, word-sized INCR bursts, legal
  address-window behavior, and representative IDs. EXOKAY, non-word sizes,
  FIXED/WRAP/reserved bursts, SRAM-monitor external windows, and unreachable
  window/response combinations are excluded from the Phase 2 signoff model until
  RTL support is intentionally added.
- Current regression status: VCS compile passes. `make phase2-regression` now
  builds the firmware, compiles the UVM testbench once, and runs the directed
  Phase 2 testlist in `tb/uvm_tb/phase2_directed_tests.txt`. The latest run
  used `UVM_DIRECTED_DIR=build/uvm/directed_apb_burst_stress_closed`, passed
  16/16 tests, and wrote `directed_summary.txt` under that run directory.
  `soc_dma_copy_test` reports `dma reg updates=5 checks=14 copy predictions=4
  checks=4 skips=0`; `soc_dma_irq_test` reports `pic updates=2 checks=6; dma
  reg updates=5 checks=14 copy predictions=4 checks=4 skips=0`.
- UVM pass/fail gates now fail on simulator exit errors, SystemVerilog/VCS
  `Error`/`Fatal` messages, direct UVM error/fatal reports, nonzero UVM summary
  counts, checker/scoreboard errors, and missing firmware artifacts. Firmware
  mailbox success remains supported for legacy `$finish` tests.
- Coverage regression status: `make phase2-regression UVM_ENABLE_COV=1`
  compiles with `tb/uvm_tb/cov.cfg`, runs the same 16 directed tests, invokes
  `urg -dir directed.vdb -format both -report urgReport -log urg.log`, and
  appends the URG dashboard to `directed_summary.txt`. Stale coverage databases
  and reports are removed before each coverage run. The latest
  `directed_cov_apb_burst_stress_closed` coverage baseline passed 16/16 with
  total score 55.46%, line 45.19%, condition 52.60%, toggle 40.58%, FSM 49.38%,
  branch 45.04%, and group 100.00%. Module definition coverage is 82.68% score,
  75.52% line, 89.24% condition, 74.60% toggle, 94.44% FSM, and 79.59% branch.
  `soc_bus_coverage::bus_contract_cg`, `jtag_reset_event_cg`,
  `jtag_recovery_pulse_cg`, `timer_irq_event_cg`, `timer_irq_latency_cg`,
  `pic_combined_irq_event_cg`, `pic_combined_irq_state_cg`, and
  `apb_burst_stress_cg` are all 100.00%.
  The `cov.cfg` hierarchy paths now match the refactored SoC fabric/JTAG
  instance names without unmatched-region warnings.
- `make phase2-complete` is the Phase 2 closure gate. It runs non-coverage and
  coverage directed gates, scans for project failure patterns, checks required
  URG functional groups, and writes
  `build/uvm/phase2_complete/phase2_completion_report.md`.
- Phase 3B closes UVM-visible CPU interrupt/exception entry/return functional
  coverage through `soc_cpu_cp0_exception_test` and `make phase3b-complete`.
  The gate observes interrupt, syscall, reserved-instruction, AdEL, ERET, EXL
  set/clear, EPC update, and nonzero dynamic counts in UVM covergroups.
- Phase 3C closes PIC multi-source mask arbitration for the current RTL
  contract through `soc_pic_mask_arbitration_test` and `make phase3c-complete`.
  The gate covers UART, timer, and DMA pending sources under zero, single,
  dual, and all-source masks. Priority-order signoff is not claimed because
  `apb_pic` has no priority encoder output.
- Deferred beyond Phase 3C: RTL-level multi-outstanding support, SPI-level flash
  protocol timing, boot-from-flash signoff, deeper debug command/reset timing
  scenarios, and broader stress remain open. The current checker instances
  intentionally still enforce the single-outstanding contract.

## Step 5: Gate Debug and Test Paths

Keep debug only where it is intended:
- production: minimal mandatory debug
- bring-up: JTAG and trace enabled
- verification: additional test masters and backdoors

Initial implementation:
- `mips_soc_impl.ENABLE_EXT_AXI_MASTER` gates the UVM-only external AXI master
  path.
- `mips_soc_impl.ENABLE_APB_FAULT_INJECTOR` gates the verification-only APB
  fault slot used for wait-state and `PSLVERR` stress.
- `mips_soc_impl.ENABLE_FLASH_IMAGE_MODEL` gates the verification-only
  loadable AXI flash-image model used for XIP-window data checking.
- Product `rtl/mips_soc.v` explicitly sets all verification-only parameters to
  `0` internally and exposes no external UVM AXI ports. Product builds do not
  rely on default parameter values to keep the external AXI master, APB fault
  injector, or flash image model disabled.
- `tb/uvm_tb/tb_top/soc_verif_top.sv` enables the verification-only external
  AXI master, APB fault injector, and flash image model.

## Step 6: Align Firmware and Verification

Update firmware and testbench models to match the same contract:
- no duplicate address maps
- no width mismatches
- no silent assumptions in sequences or mailboxes

Firmware and UVM regression policy:
- Firmware build is a first-class regression stage, separate from UVM
  simulation. It must produce traceable artifacts such as `firmware.elf`,
  `firmware.bin`, `firmware.hex`, a linker map, an objdump/disassembly, and a
  small manifest recording the source inputs and toolchain version.
- UVM test scripts must not silently rebuild firmware or copy an implicit stale
  image. They should consume an explicitly selected firmware artifact, for
  example through `FW_HEX=/path/to/firmware.hex` or a simulator plusarg such as
  `+FW_HEX=/path/to/firmware.hex`.
- The top-level regression orchestrator owns the sequence:
  1. build the selected firmware image with the MIPS32 cross toolchain;
  2. record the firmware artifact path and hash in the regression log;
  3. launch the selected RTL/UVM test with that artifact;
  4. archive firmware artifacts, simulator logs, and coverage outside source
     control.
- Random MIPS instruction firmware generation is a separate regression class
  from fabric-directed UVM tests. The random flow may generate assembly with
  `gen_rand_mips.py`, compile it with the MIPS32 cross toolchain, convert it to
  `firmware.hex`, and then run simulation. Normal fabric UVM tests should remain
  driven primarily by UVM sequences, scoreboards, and coverage, while using
  firmware only as an explicit smoke/background workload.

Required implementation work:
- Add a top-level firmware build target or regression driver that wraps the
  existing `tb/soc_test/fw` cross-compile flow.
- Update `tb/uvm_tb/run_uvm.sh` and `tb/uvm_tb/run_regression.sh` to accept an
  explicit `FW_HEX` path, fail fast when it is missing, and log the firmware
  hash before simulation starts.
- Move generated firmware and regression outputs into a build/output directory
  instead of relying on implicit copies in source directories.

Initial implementation:
- A repository-level `Makefile` now provides `firmware`, `uvm`,
  `uvm-regression`, and `regression` targets. The `regression` target builds
  firmware first, then launches UVM with the generated artifact.
- `tb/soc_test/fw/Makefile` supports `OUT_DIR` and emits `firmware.elf`,
  `firmware.bin`, `firmware.hex`, `firmware.map`, `firmware.objdump`, and
  `firmware.manifest` under `build/firmware/<name>/`.
- UVM run scripts now require `FW_HEX`, log the absolute firmware path and
  SHA-256 hash, run from `build/uvm/...`, and pass `+FW_HEX` into simulation
  instead of copying `../soc_test/fw/firmware.hex`.
- The SRAM/DDR verification memory path honors the `+FW_HEX` plusarg while
  retaining `firmware.hex` as a compatibility default for older direct runs.
- Repository layout is documented in `docs/repo_layout.md`. Legacy SoC and
  stage/block entry points now run from `build/soc_test/...` and
  `build/stage/<stage>/` instead of emitting VCS/URG output into source
  directories. Top-level cleanup targets distinguish disposable `build/` output
  from known legacy artifacts that may already exist under `sim/` or
  `tb/soc_test/`.

## Step 7: Signoff the New Architecture

Exit only when:
- product top is stable
- verification top is isolated
- shared contract is versioned
- regressions no longer depend on hierarchy hacks
- protocol checkers are enabled in normal UVM runs
- scoreboards and coverage prove the fabric contract, not only firmware success

Current architecture review status:
- Phase 2 is complete for the current single-outstanding RTL fabric contract.
- Phase 3A is complete for UART TX IRQ, APB wait/PSLVERR stress, loadable
  AXI flash-image reads, and CPU/CP0 firmware smoke gating.
- Phase 3B is complete for UVM-visible CPU/CP0 exception-entry and return
  coverage.
- Phase 3C is complete for PIC multi-source mask arbitration coverage. Priority
  ordering is intentionally not claimed because the current PIC exposes raw
  status, mask, active bits, and an OR-reduced CPU interrupt.
- The architecture is hardened and bounded, but not production-final. Remaining
  production work is tracked below and must not be folded into the already
  closed Phase 2/3A/3B/3C claims.

## Step 8: Product Boundary Hardening

Purpose:
- remove dependency on verification defaults in product-facing RTL
- make test-only feature selection explicit at the top-level boundary
- keep the product build auditable without inspecting verification wrappers

Required implementation work:
- Explicitly tie off `mips_soc_impl.ENABLE_EXT_AXI_MASTER`,
  `mips_soc_impl.ENABLE_APB_FAULT_INJECTOR`, and
  `mips_soc_impl.ENABLE_FLASH_IMAGE_MODEL` to `0` in `rtl/mips_soc.v`.
- Keep `tb/uvm_tb/tb_top/soc_verif_top.sv` as the only wrapper that enables all
  three verification-only hooks.
- Add static review checks before future release branches to catch accidental
  verification hook exposure in product wrappers.

Current status:
- Product wrapper parameter hardening is implemented.
- `soc_verif_top` remains the verification integration view that enables the
  external AXI master, APB fault injector, and loadable flash-image model.

Exit criteria:
- Product wrapper exposes board/product pins only.
- Verification-only hooks are disabled explicitly, not by inherited defaults.
- UVM wrapper remains the only integration view with external AXI stress,
  APB fault injection, and loadable flash-image model enabled.

## Step 9: Split the Transitional SoC Implementation

Purpose:
- retire `mips_soc_impl` as a monolithic integration owner
- make subsystem ownership explicit before larger feature work

Target partition:
- `soc_core_subsystem`: CPU, CP0-visible interrupt input, instruction/data cache
  master interfaces, and stable verification trace/exception observation points
  under verification-only configuration.
- `soc_memory_subsystem`: SRAM/DDR model boundary, boot/SRAM alias ownership, and
  future boot ROM or flash boot selection.
- `soc_peripheral_subsystem`: APB bridge attachment, UART, timer, GPIO, DMA, PIC,
  APB fault slot gating, and interrupt-source wiring.
- `soc_debug_subsystem`: JTAG/debug master, reset recovery policy, and debug-mode
  configuration.
- `soc_fabric`: remains the named AXI master/slave routing boundary.

Current status:
- `rtl/soc_peripheral_subsystem.v` now owns the APB bridge, APB decode, UART,
  timer, GPIO, DMA, PIC, verification-only APB fault slot, interrupt-source
  packing, and the CPU interrupt output.
- `mips_soc_impl` now connects the fabric APB slave port, DMA AXI master port,
  GPIO pins, and CPU interrupt line through `u_peripheral_subsystem` instead of
  owning the peripheral integration directly.
- `rtl/soc_memory_subsystem.v` now owns the SRAM/DDR model instance, flash/XIP
  AXI slave window, SPI flash controller pins, and the verification-only
  flash-image model selection.
- `mips_soc_impl` now connects fabric slave ports S0 and S2 plus the SPI pins
  through `u_memory_subsystem` instead of owning SRAM and flash integration
  directly.
- `rtl/soc_debug_subsystem.v` now owns the JTAG debug master instance and its
  reset policy, while `mips_soc_impl` only carries the fabric-facing JTAG AXI
  master wires and package pins.
- `rtl/soc_core_subsystem.v` now owns the CPU/cache core instance, CP0-visible
  interrupt mapping, and instruction/data AXI master boundary.
- UVM and legacy SoC compile entry points include the new subsystem file.
- Coverage hierarchy exclusions, the legacy UART mailbox probe, direct firmware
  SRAM preload path, CPU/CP0 observation path, and JTAG reset-recovery
  observation path were updated to account for the new subsystem instance
  layers.
- Phase 3D subsystem extraction is structurally complete and smoke/coverage
  verified across the peripheral, memory, debug, and core subsystem wrappers.
- Core subsystem closure included CPU/CP0 exception smoke, fabric-contract smoke,
  UVM coverage hierarchy smoke, legacy `soc-smoke`, and a clean error scan under
  `build/uvm/core_subsystem*` and `build/soc_test/core_subsystem*`.
- Post-extraction Phase 3 directed integration closure passed with coverage in
  `build/uvm/phase3_directed_after_phase3d`, covering UART IRQ, APB
  wait/PSLVERR stress, and AXI flash-image/XIP window tests.
- `tb/uvm_tb/tb_top/soc_observation_if.sv` now provides a stable UVM observation
  interface for mailbox, CPU/CP0 exception, execution trace, and JTAG AXI-state
  signals. The UVM test top consumes this interface instead of a wide set of
  ad hoc wrapper scalar ports.
- `tb/uvm_tb/tb_top/soc_observation_bind.sv` now drives that interface through a
  verification-only bind on `soc_verif_top`. This removes the direct
  observation assignments from the verification wrapper while keeping the UVM
  test top stable.
- Legacy `tb/soc_test` monitors consume local `legacy_*` aliases, and the
  product wrapper SPI outputs are explicitly connected in the legacy smoke
  testbench to avoid the old missing-port warning.
- `tb/soc_test/soc_legacy_observation_if.sv` and
  `tb/soc_test/soc_legacy_observation_bind.sv` now provide the same
  interface/bind containment style for legacy smoke observation. `tb_mips_soc`
  consumes local interface aliases while the hierarchy expressions are isolated
  in one bind block.
- The legacy direct SRAM array preload has been removed from `tb_mips_soc`.
  Preload now uses the simulation-only `preload_sram_hex()` task exposed through
  the product wrapper and delegated to the memory subsystem/DDR model.
- Legacy bind/preload cleanup was verified with `make soc-smoke` under
  `build/soc_test/legacy_bind_preload_smoke`, `make cpu-cp0-gate` under
  `build/soc_test/legacy_bind_preload_cpu_cp0_gate`, and a coverage-enabled
  Phase 3 directed regression under
  `build/uvm/legacy_bind_preload_phase3_directed`.
- Legacy smoke `exclude5.el` no longer carries stale reset-path FSM transition
  exclusions. Those transition objects are not emitted by the current
  VCS X-2025.06 FSM extraction, so active rules produced
  `Warning-[UCAPI-EL-INVFSM]` while having no coverage effect. The file is now
  an explicit no-active-exclusion placeholder, and future FSM exclusions must
  be regenerated from a current full-exclusion dump.
- Remaining architecture debt is reducing the legacy bind signal set over time
  as the legacy smoke bench is retired or replaced by UVM-owned monitors. This
  is not blocking the Phase 3D structural extraction exit.

Exit criteria:
- Each subsystem has product-facing ports and no UVM-only stimulus ports.
- Verification observation is provided through stable interfaces or binds rather
  than ad hoc hierarchy paths.
- Address map, interrupt map, and reset/boot behavior are referenced from the
  shared contract instead of duplicated in subsystem-local comments.

## Step 10: Future Architecture Expansion

Open work that requires a new contract before RTL changes:
- RTL multi-outstanding fabric support. Define ordering, ID ownership, response
  reordering, arbitration, and checker mode before disabling the current
  single-outstanding requirement.
- SPI-level flash protocol timing and boot-from-flash signoff. Define reset
  vector source, flash map, XIP timing, flash image format, and firmware build
  artifact before claiming real flash boot.
- Debug command/reset timing stress beyond the current deterministic recovery
  gate.
- Broader long-duration/random stress after the subsystem boundaries are stable.
