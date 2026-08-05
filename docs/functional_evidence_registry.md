# RTL Functional Evidence Registry

Status levels used by this registry:

- `IMPLEMENTED`: RTL and interface contract are present.
- `BLOCK_VERIFIED`: block directed, negative, reset, and error tests pass.
- `SOC_INTEGRATED`: SoC wiring and firmware/SoC simulation pass.
- `CONTRACT_CLOSED`: the current RTL/simulation contract, including required
  backpressure and error evidence, is closed. This is not a product or silicon
  signoff.

## Current Registry

| Block | Status | Primary evidence | Log location | Residual risk / boundary |
|---|---|---|---|---|
| QSPI command/FIFO | `BLOCK_VERIFIED` | `make qspi-cmd-behavioral-gate` | `build/unit_tb/qspi_cmd_behavioral/sim.log` | Vendor-specific command timing and device modes are out of scope |
| QSPI canonical error taxonomy | `CONTRACT_CLOSED` | `make qspi-error-taxonomy-gate qspi-retry-policy-gate` | `build/unit_tb/qspi_error_taxonomy/sim.log`, `build/unit_tb/qspi_retry_policy/sim.log` | Secure-boot authentication and production policy are out of scope |
| QSPI APB/shared-pin SoC path | `SOC_INTEGRATED` | `make qspi-status-integration-gate qspi-soc-quad-gate` | `build/unit_tb/qspi_status_integration/sim.log`, `build/unit_tb/qspi_soc_quad/sim.log` | External pins, PHY timing, and board endpoint are out of scope |
| QSPI x1/quad AXI XIP | `BLOCK_VERIFIED` | `make qspi-axi-xip-gate qspi-axi-xip-quad-gate` | `build/unit_tb/qspi_axi_xip/sim.log`, `build/unit_tb/qspi_axi_xip_quad/sim.log` | Real flash electrical behavior and erase/program production flow are out of scope |
| QSPI development boot handoff | `SOC_INTEGRATED` | `make product-manifest-handoff-gate product-manifest-handoff-quad-gate` | `build/unit_tb/product_manifest_handoff*/sim_valid.log`, `sim_bad_crc.log`, `sim_xip_timeout.log` | Quad behavioral endpoint no longer overwrites a testbench-loaded image during time-0 initialization; this is still a development manifest/CRC flow, not a signed production boot chain |
| DDR4 protocol controller | `CONTRACT_CLOSED` | `make ddr4-complete-gate ddr4-status-soc-gate` | `build/unit_tb/axi_ddr4_controller*/sim.log`, `build/soc_test/ddr4_status_gate/*/sim.log` | No PHY, synthesis, backend, board, ECC, or multi-rank claim |
| CPU/MMU current contract | `CONTRACT_CLOSED` | `make cpu-mmu-complete` | `build/cpu_mmu_complete/cpu_mmu_completion_report.md` | Full Linux/OS boot and production policy are out of scope |
| UART/WDT/APB baseline | `SOC_INTEGRATED` | `make phase3-complete` and focused UART/WDT gates | `build/uvm/phase3_complete/`, focused `build/unit_tb/` and `build/soc_test/` logs | External electrical timing and production software policy are out of scope |
| D-cache baseline | `BLOCK_VERIFIED` | Existing D-cache unit/CPU/SoC gates | Focused `build/unit_tb/` and `build/soc_test/` logs | Nonblocking D-cache WIP is retired; ECC/coherence are not claimed |

## Evidence Rules

1. Every new gate must have a reproducible Make target and write `compile.log`
   and `sim.log` below `build/`.
2. The command, expected success marker, scope, and residual risk must be
   recorded in `docs/functional_completeness_plan.md` or this registry.
3. Coverage exclusion warnings are tracked separately and are not functional
   closure evidence.
4. Current conclusions are limited to RTL frontend, unit, firmware, and SoC
   simulation. They do not imply synthesis, backend, PHY, board, or product
   readiness.
