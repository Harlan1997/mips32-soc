# Signoff Criteria

## Architecture

- one authoritative address map
- one authoritative interface definition
- product top separated from verification top
- debug/test features are gated
- unmapped fabric accesses complete with a documented AXI error response
- arbitration policy is deterministic, documented, and starvation-resistant

## RTL Quality

- no unresolved script-to-RTL mismatches
- no hardcoded user-specific paths
- no unbounded combinational loops in control paths
- no undocumented protocol assumptions

## Verification Quality

- smoke regressions pass
- stress regressions pass
- directed unmapped-access response tests pass
- background stress traffic is non-destructive to firmware state unless a test
  explicitly owns the memory region
- protocol checkers enabled on normal UVM runs
- protocol checkers cover external verification ingress, SRAM observation, and
  every current internal `soc_fabric` segment
- bus monitors reconstruct transactions and feed scoreboards during normal UVM
  runs
- all AXI slave windows complete legal bursts or return a documented error
- APB read-burst tests cover multiple peripheral windows and scoreboard every
  returned APB register beat
- Phase 2 closure is claimed only after `make phase2-complete` passes and
  writes a clean completion report
- Phase 3A closure is claimed only after `make phase3-complete` passes and
  writes a clean completion report
- Phase 3B CPU/CP0 UVM-visible closure is claimed only after
  `make phase3b-complete` passes and writes a clean completion report
- Phase 3C PIC mask arbitration closure is claimed only after
  `make phase3c-complete` passes and writes a clean completion report
- Current RTL contract full-chip sign-off is claimed only after
  `make current-contract-signoff` passes, merges all compatible UVM VDBs into
  `build/signoff/current_contract/coverage/merged.vdb`, meets all 15 required
  functional coverage groups (100.00%) and UVM/product module-definition code
  coverage thresholds, and writes a clean `current_contract_signoff_report.md`.
  Approved merged UVM code coverage defaults: Score >= 75.00%, Line >= 70.00%,
  Condition >= 80.00%, Toggle >= 60.00%, FSM >= 85.00%, Branch >= 70.00%.
  Approved product-top CPU/CP0 code coverage defaults: Score >= 80.00%, Line >= 70.00%,
  Condition >= 85.00%, Toggle >= 55.00%, FSM >= 90.00%, Branch >= 90.00%. All 15 required
  functional groups must hit 100.00%.
- directed interrupt tests cover at least DMA/PIC, timer/PIC, and timer+DMA
  combined PIC assertion/deassertion before CPU-level interrupt signoff is
  claimed
- UART TX interrupt signoff requires `soc_uart_irq_test` and
  `uart_irq_event_cg` at 100%; the behavioral external RX/PIC/RBR path is
  covered by the dedicated UART RX SoC gates, while board electrical timing
  and Linux 8250 compatibility remain outside this contract
- CPU/CP0 firmware smoke signoff requires `make cpu-cp0-gate` to observe
  interrupt, syscall, reserved-instruction, AdEL, and ERET events
- UVM-visible CPU exception-entry/return signoff requires
  `soc_cpu_cp0_exception_test` to observe interrupt, syscall, RI, AdEL, ERET,
  EXL set/clear, and EPC update events with required CPU/CP0 groups at 100%
- PIC multi-source mask arbitration signoff requires
  `soc_pic_mask_arbitration_test` to observe UART, timer, and DMA pending
  sources under none, single-source, dual-source, and all-source masks with
  required PIC groups at 100%; bounded priority-order signoff additionally
  requires `make interrupt-priority-gate` and the 32-source priority/ACK
  differential gate. The current RTL exposes `vec_id`/`vec_prio` from a
  deterministic maximum-priority, lower-ID tie-break encoder; arbitrary-depth
  OS nesting, multicore IRQ ownership and Linux IRQ ABI remain outside this
  criterion.
- loadable flash/XIP verification signoff requires `soc_flash_image_test` with
  an explicit `FLASH_IMAGE` artifact
- APB wait/PSLVERR stress signoff requires `soc_apb_fault_stress_test`; product
  RTL must keep the APB fault injector disabled outside verification
- checker, scoreboard, and coverage failures are treated as regression failures
- run scripts fail on simulator exit errors, SystemVerilog/VCS `Error`/`Fatal`
  messages, direct UVM error/fatal reports, nonzero UVM summary counts, and
  missing firmware artifacts
- coverage targets defined

## Release Quality

- generated files excluded from source control
- simulator, firmware, coverage, and waveform artifacts are isolated under
  `build/` or another explicit run directory
- build and run instructions documented
- interface and memory map versioned
- change log maintained
