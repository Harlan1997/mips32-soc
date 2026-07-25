# Coverage Plan

## Scope

This plan tracks functional coverage for the SoC fabric and its verification
boundary. The goal is to prove the documented bus contract, not only firmware
completion.

Protocol correctness is checked in normal UVM runs by
`tb/uvm_tb/checkers/axi_protocol_checker.sv`. Instances are connected at the
external UVM master port, the SRAM observation port, and are bound into
`soc_fabric` for the internal `axim`, `axim2`, `axim3`, and `axim4` links. All
current instances enforce the single-outstanding RTL contract while retaining an
ID-aware queue model for a future multi-outstanding fabric.

## Implemented Coverage

`tb/uvm_tb/env/soc_bus_coverage.sv` samples reconstructed AXI transactions from:
- external UVM AXI master monitor
- SRAM AXI observation monitor

Current coverpoints:
- transaction source: external master, SRAM observation
- direction: read, write
- address window: boot SRAM, SRAM alias, APB, flash, unmapped
- AXI response: OKAY, SLVERR, DECERR; EXOKAY is ignored until the RTL contract
  expands to exclusive-access support
- burst length: single, 2-4 beats, 5-8 beats, long burst
- transfer size: word; byte, half-word, and larger sizes are ignored until the
  slave/fabric contract expands beyond word-sized accesses
- burst type: INCR; FIXED, WRAP, and reserved burst encodings are ignored until
  the RTL contract supports them
- transaction ID: ID0, ID1-3, ID4-7, ID8-15

Current crosses:
- source x direction x address window
- address window x response
- direction x burst length
- source x direction x transaction ID

The cross model excludes architecturally unreachable combinations: the SRAM
observation monitor can only see boot/SRAM-alias traffic, unmapped accesses are
expected to return DECERR, normal APB/SRAM/boot accesses are expected to return
OKAY, and the current flash model returns OKAY for reads plus SLVERR for writes.

## Directed Coverage Tests

`soc_fabric_contract_test` drives a compact contract suite:
- boot SRAM read returns OKAY
- SRAM alias read returns OKAY
- APB GPIO read/write returns OKAY
- flash read burst returns OKAY
- flash write returns SLVERR
- unmapped read/write returns DECERR

Additional directed tests:
- `soc_unmapped_error_test`
- `soc_flash_write_error_test`
- `soc_gpio_reg_model_test`
- `soc_apb_reg_model_test`
- `soc_sram_data_integrity_test`
- `soc_axi_id_sweep_test`
- `soc_axi_overlap_probe_test`
- `soc_dma_copy_test`
- `soc_dma_irq_test`
- `soc_timer_irq_test`
- `soc_jtag_reset_recovery_test`
- `soc_bus_stress_test`
- `soc_uart_irq_test`
- `soc_apb_fault_stress_test`
- `soc_flash_image_test`
- `soc_cpu_cp0_exception_test`
- `soc_pic_mask_arbitration_test`

`soc_apb_reg_model_test` also includes a 4-beat INCR read burst across the
timer `CTRL`, `LOAD`, `VAL`, and `INT` registers. This directed check locks the
APB bridge read-burst fix into the normal Phase 2 gate instead of relying only
on firmware instruction traffic to hit APB-window bursts.

`soc_timer_irq_test` covers the timer interrupt path into PIC bit 2:
- programs timer `LOAD`, `VAL`, and `CTRL` with interrupt enable
- enables PIC mask bit 2
- polls PIC `STATUS` and `ACTIVE` until the timer interrupt is visible
- disables the timer, clears timer `INT`, verifies PIC deassertion, and
  restores the PIC mask to zero
- contributes `timer_irq_event_cg` and `timer_irq_latency_cg`

`soc_axi_overlap_probe_test` enables the active master's overlap mode and submits
back-to-back requests across multiple AXI IDs:
- SRAM write/read returning OKAY
- flash read returning OKAY
- flash write returning SLVERR
- unmapped read/write returning DECERR

This is a verification-infrastructure probe. It proves the BFM, monitors,
scoreboard, and coverage path can tolerate overlapping request issue and
ID-based response matching. It does not close RTL multi-outstanding coverage
while the fabric is still specified and checked as single-outstanding.

`soc_uart_irq_test` covers the UART TX interrupt path into PIC bit 1:
- clears UART IRQ state, enables PIC mask bit 1, writes UART TX data, checks
  UART `IRQ_STATUS` and `STATUS`, checks PIC `STATUS`/`ACTIVE`, clears the UART
  IRQ, and verifies PIC deassertion.
- contributes `uart_irq_event_cg`.

`soc_apb_fault_stress_test` covers APB wait-state and `PSLVERR` propagation:
- reads a normal timer register through the APB bridge wait-state path.
- reads and writes a verification-only APB fault slot that returns `PSLVERR`.
- issues a multi-beat read burst to the fault slot and checks every AXI beat
  returns `SLVERR`.
- contributes `apb_fault_stress_cg`.

`soc_flash_image_test` covers the loadable flash-image/XIP verification window:
- passes `+FLASH_IMAGE=<hex>` into the verification flash model.
- checks a single flash word and a three-word INCR burst against the loaded
  image contents.
- contributes `flash_image_cg`.

## Implemented Data Scoreboards

`soc_scoreboard` now includes a GPIO APB register model:
- writes to GPIO `DIR` update the expected direction register
- writes to GPIO `DATA` update the expected output data register
- reads from GPIO `DIR` must match the predicted direction register
- reads from GPIO `DATA` must match the predicted output bits for pins whose
  direction bit is set to output

`soc_scoreboard` also includes UART, timer, and PIC APB register checks:
- UART `STATUS` reads must report TX-ready and `TX` reads must return zero.
- Timer checks cover disabled-mode `CTRL`, `LOAD`, `VAL`, and interrupt clear
  behavior, avoiding dynamic counter comparisons while the timer is enabled.
- PIC checks cover `MASK` write-read consistency and `ACTIVE == 0` when the
  interrupt mask is zero.
- `soc_apb_reg_model_test` directly drives these register paths through the
  external UVM AXI master.

`soc_scoreboard` also includes a byte-lane SRAM data model for external master
traffic:
- OKAY writes into SRAM windows update only the byte lanes selected by `WSTRB`
- OKAY reads from SRAM windows check only bytes previously written by the
  external master
- firmware-owned SRAM contents remain unmodeled, preventing false failures from
  CPU boot traffic
- `soc_sram_data_integrity_test` covers a 4-beat SRAM alias burst, a masked
  byte-strobe update/readback sequence, a 9-beat long INCR burst, and a boot
  SRAM window write/readback sequence

Flash read data checking supports both verification flash modes:
- with no `+FLASH_IMAGE`, OKAY flash reads are expected to return zero-filled
  data beats.
- with `+FLASH_IMAGE`, `axi_flash_image_model` loads bytes through `$readmemh`
  and `soc_flash_image_test` checks expected XIP-window data words.
- Flash writes remain read-only and must return `SLVERR`.

Basic DMA copy checking is implemented as a directed sequence and scoreboard
test:
- `soc_dma_copy_test` seeds a 4-word source buffer in the SRAM alias window
- it programs DMA SRC/DST/LENGTH/CTRL over APB and polls CTRL.DONE
- it reads the destination burst and compares copied data in the sequence
- `soc_scoreboard` models DMA APB register reads/writes
- on DMA START, the scoreboard predicts destination words when all source byte
  lanes are known
- ID=2 DMA writes at the SRAM observation port are checked against that
  prediction and then folded into the SRAM byte-lane model
- `soc_dma_irq_test` enables DMA INT_EN and PIC mask bit 3, checks PIC
  STATUS/ACTIVE assertion after DMA DONE, clears DONE, and checks PIC
  STATUS/ACTIVE deassertion

`soc_jtag_reset_recovery_test` now includes dedicated functional coverage:
- `jtag_reset_event_cg` covers initial reset release, JTAG AXI command sequence
  completion, reset injection while the JTAG AXI state machine is in AW/W/AR,
  TAP reset sequence completion, and final JTAG stimulus completion.
- `jtag_recovery_pulse_cg` covers the required recovery pulse count of at least
  nine resets and treats fewer than nine as an illegal bin.

`soc_timer_irq_test` now includes dedicated functional coverage:
- `timer_irq_event_cg` covers PIC mask enable, timer enable, PIC assertion,
  timer interrupt clear, PIC clear, and PIC mask restore.
- `timer_irq_latency_cg` covers that PIC assertion is observed within the
  directed polling budget and treats zero observations as illegal.

`soc_pic_combined_irq_test` covers the currently signoffable combined PIC
source case:
- timer bit 2 is asserted first and sampled as a timer-only active state.
- DMA bit 3 is then asserted while timer remains pending, giving both-active
  PIC STATUS/ACTIVE coverage.
- timer clear is checked while DMA remains active, then DMA DONE clear is
  checked until all bits deassert.
- `pic_combined_irq_event_cg` and `pic_combined_irq_state_cg` cover the event
  sequence and none/timer-only/DMA-only/both active-state bins.

`soc_apb_burst_stress_test` extends APB-window burst coverage:
- it configures stable UART, timer, GPIO, DMA, and PIC register state with
  single-beat writes.
- it issues read bursts through UART, timer, GPIO, DMA, PIC, and an unused APB
  slot to exercise legal APB bridge read-burst sequencing and decode behavior.
- `soc_scoreboard` now checks APB register reads on every AXI read beat, not
  only the first beat of a burst.
- `apb_burst_stress_cg` covers all sampled APB windows and 2/3/4/5-beat burst
  lengths.

## Regression Coverage Flow

The deterministic Phase 2 gate is `make phase2-regression`. It runs
`tb/uvm_tb/phase2_directed_tests.txt` and records the pass/fail table in
`build/uvm/directed/directed_summary.txt`. The latest deterministic run used
`UVM_DIRECTED_DIR=build/uvm/directed_apb_burst_stress_closed` and passed 16/16
tests.

Coverage is enabled with `make phase2-regression UVM_ENABLE_COV=1`. The testlist
runner removes stale `directed.vdb`, `urgReport`, and `urg.log`, compiles with
`tb/uvm_tb/cov.cfg`, runs the same 16 directed tests, generates an URG report,
and appends the dashboard to `directed_summary.txt`. The latest coverage run
used `UVM_DIRECTED_DIR=build/uvm/directed_cov_apb_burst_stress_closed`, passed
16/16 tests, and produced this baseline:
- Total coverage: score 55.46%, line 45.19%, condition 52.60%, toggle 40.58%,
  FSM 49.38%, branch 45.04%, group 100.00%.
- Module definition coverage: score 82.68%, line 75.52%, condition 89.24%,
  toggle 74.60%, FSM 94.44%, branch 79.59%.
- Functional group coverage:
  `soc_bus_coverage::bus_contract_cg` is 100.00%.
  `soc_jtag_reset_recovery_test::jtag_reset_event_cg` is 100.00%.
  `soc_jtag_reset_recovery_test::jtag_recovery_pulse_cg` is 100.00%.
  `axi_timer_irq_seq::timer_irq_event_cg` is 100.00%.
  `axi_timer_irq_seq::timer_irq_latency_cg` is 100.00%.
  `axi_pic_combined_irq_seq::pic_combined_irq_event_cg` is 100.00%.
  `axi_pic_combined_irq_seq::pic_combined_irq_state_cg` is 100.00%.
  `axi_apb_burst_stress_seq::apb_burst_stress_cg` is 100.00%.

The `cov.cfg` hierarchy paths now match the refactored SoC fabric, JTAG debug,
and arbiter instance names; the latest coverage compile/report logs have no
unmatched-region warnings. The lower total score versus the previous coverage
baseline is expected after the APB bridge read path was expanded from a
single-beat assumption to full `ARLEN+1` burst completion, which added RTL
coverage targets without reducing functional group coverage. Low top-level
instance coverage is still expected because CPU/full-SoC execution paths, real
flash/XIP or boot-from-flash traffic, broader SRAM stress, and
interrupt/exception scenarios remain open.

The legacy SoC smoke `exclude5.el` file intentionally contains no active
exclusions. Previous reset-path FSM transition exclusions no longer matched
VCS X-2025.06 FSM extraction and produced URG
`Warning-[UCAPI-EL-INVFSM]` without excluding any coverage. Future legacy FSM
exclusions must be regenerated from a current full-exclusion dump instead of
carrying forward stale transition names.

The UVM run scripts treat simulator exit failures, SystemVerilog/VCS
`Error`/`Fatal` messages, direct `UVM_ERROR`/`UVM_FATAL` reports, nonzero UVM
summary counts, checker errors, scoreboard errors, and missing firmware
artifacts as regression failures. Firmware-driven mailbox success is still
accepted for tests that finish through the legacy `$finish` path.

`make phase2-complete` is the final Phase 2 closure gate. It runs both the
non-coverage and coverage Phase 2 directed gates, scans logs for project failure
patterns, checks required functional groups, and writes
`build/uvm/phase2_complete/phase2_completion_report.md`.

`make phase3-regression` runs the deterministic Phase 3A directed list in
`tb/uvm_tb/phase3_directed_tests.txt`: UART TX IRQ, APB wait/PSLVERR fault
stress, and loadable flash-image reads. The default flash image is
`tb/uvm_tb/data/flash_xip_image.hex`.

`make cpu-cp0-gate` runs the firmware-driven CPU/CP0 smoke gate and scans for a
machine-readable `CPU_CP0_SUMMARY`. The latest passing gate observed dynamic
interrupt, syscall, reserved-instruction, AdEL, and ERET events.

`make phase3-complete` is the Phase 3A closure gate. It runs Phase 3A directed
tests without coverage, reruns them with VCS/URG coverage, checks the required
Phase 3A functional groups, runs the CPU/CP0 firmware gate, scans logs, and
writes `build/uvm/phase3_complete/phase3_completion_report.md`. The latest run
passed 3/3 directed, 3/3 coverage, and CPU/CP0 firmware with
`CPU_CP0_SUMMARY intr=8 syscall=1 ri=7 adel=1 eret=16`.

`soc_cpu_cp0_exception_test` closes UVM-visible CPU/CP0 exception-entry/return
coverage using the same firmware exception path. The test disables the legacy
mailbox `$finish`, waits for firmware success, and samples UVM covergroups for
interrupt, syscall, reserved-instruction, AdEL, ERET, EXL set/clear, EPC update,
and nonzero event counts.

`make phase3b-complete` is the Phase 3B CPU/CP0 UVM closure gate. It runs the
Phase 3B directed test without coverage, reruns it with VCS/URG coverage, checks
`soc_cpu_cp0_exception_test::cpu_cp0_exception_event_cg` and
`soc_cpu_cp0_exception_test::cpu_cp0_exception_count_cg` at 100.00%, scans logs,
and writes `build/uvm/phase3b_complete/phase3b_completion_report.md`. The latest
run passed 1/1 directed and 1/1 coverage with observed counts
`intr=8 syscall=1 ri=7 adel=1 eret=16`.

`soc_pic_mask_arbitration_test` covers the actual PIC arbitration contract:
`ACTIVE = STATUS & MASK`, with `cpu_int` being the OR reduction of active bits.
The current RTL does not expose a priority-encoded interrupt output, so this
test intentionally does not claim priority ordering. It drives UART TX, timer,
and DMA pending sources and checks none, single-source, dual-source, and
all-source mask combinations.

`make phase3c-complete` is the Phase 3C PIC mask arbitration closure gate. It
runs the Phase 3C directed test without coverage, reruns it with VCS/URG
coverage, checks `axi_pic_mask_arbitration_seq::pic_mask_arbitration_event_cg`
and `axi_pic_mask_arbitration_seq::pic_mask_arbitration_active_cg` at 100.00%,
scans logs, and writes
`build/uvm/phase3c_complete/phase3c_completion_report.md`. The latest run passed
1/1 directed and 1/1 coverage.

## Deferred Beyond Phase 2

- AXI ID coverage is started with directed traffic and an overlap-generation
  probe. True RTL multi-outstanding request and response reordering coverage
  still needs fabric support and a widened top-level checker configuration.
- APB peripheral register coverage now covers GPIO, UART, timer, and PIC at a
  directed register-model level. DMA has basic APB programming and DONE polling
  coverage, scoreboard prediction for known-source copy data, directed DMA/PIC
  interrupt assertion/deassertion coverage, and directed timer/PIC interrupt
  assertion/deassertion coverage.
- SRAM data integrity scoring now covers external master-owned byte lanes across
  alias and boot SRAM windows, masked byte writes, and long INCR bursts.
- Loadable AXI flash-image reads are covered in Phase 3A. SPI-serial flash
  protocol timing and boot-from-flash remain future work.
- JTAG debug/reset recovery now has both a directed observability gate and
  dedicated functional coverage bins. Deeper debug scenarios, such as varied
  command mixes and reset timing beyond the fixed AW/W/AR injection points, are
  still future coverage expansion items.
- Remaining interrupt work no longer includes PIC mask arbitration for the
  current RTL contract; Phase 3C closes UART/timer/DMA multi-source mask
  combinations. Priority-order signoff remains unclaimed because the PIC has no
  priority encoder output. CPU/CP0 firmware smoke and UVM-visible
  exception-entry/return functional coverage are closed through Phase 3A/3B
  gates. UART TX IRQ is covered in Phase 3A; RX IRQ remains tied off until an
  RX datapath exists.
- Firmware-driven long-running tests currently terminate through the mailbox
  `$finish` path, so UVM report-phase coverage summaries are mainly visible in
  directed UVM tests.
- The APB bridge now has directed timer-register and multi-peripheral APB-window
  read-burst checks. Phase 3A adds a verification-only APB fault slot for
  wait-state and `PSLVERR` propagation stress.

## Exit Criteria

- All documented address windows hit read and write bins where legal.
- Illegal accesses hit the expected error response bins.
- Each AXI slave window has burst coverage for its supported legal lengths.
- Cross coverage is reviewed with ignores or waivers for architecturally illegal
  or unreachable bins.
- Coverage reports are generated in regression and stored outside source
  control.
