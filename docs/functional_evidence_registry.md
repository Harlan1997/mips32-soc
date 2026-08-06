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
| QSPI APB/shared-pin SoC path | `SOC_INTEGRATED` | `make qspi-status-integration-gate qspi-soc-quad-gate` | `build/unit_tb/qspi_status_integration/sim.log`, `build/unit_tb/qspi_soc_quad/sim.log` | Device-specific command modes and production software policy are outside this RTL contract |
| QSPI x1/quad AXI XIP | `BLOCK_VERIFIED` | `make qspi-axi-xip-gate qspi-axi-xip-quad-gate` | `build/unit_tb/qspi_axi_xip/sim.log`, `build/unit_tb/qspi_axi_xip_quad/sim.log` | Device-specific command modes and erase/program policy are outside this RTL contract |
| QSPI development boot handoff | `SOC_INTEGRATED` | `make product-manifest-handoff-gate product-manifest-handoff-quad-gate` | `build/unit_tb/product_manifest_handoff*/sim_valid.log`, `sim_bad_crc.log`, `sim_xip_timeout.log` | Quad behavioral endpoint no longer overwrites a testbench-loaded image during time-0 initialization; this is still a development manifest/CRC flow, not a signed production boot chain |
| DDR4 protocol controller | `CONTRACT_CLOSED` | `make ddr4-complete-gate ddr4-status-soc-gate` | `build/unit_tb/axi_ddr4_controller*/sim.log`, `build/soc_test/ddr4_status_gate/*/sim.log` | ECC policy and multi-rank behavior are outside this RTL contract |
| CPU/MMU current contract | `CONTRACT_CLOSED` | `make cpu-mmu-complete` | `build/cpu_mmu_complete/cpu_mmu_completion_report.md` | Full Linux/OS boot, uncached DDR backend stress, and production policy are out of scope |
| UART/WDT/APB baseline | `SOC_INTEGRATED` | `make phase3-complete` and focused UART/WDT gates | `build/uvm/phase3_complete/`, focused `build/unit_tb/` and `build/soc_test/` logs | Production software policy is outside this RTL contract |
| D-cache baseline | `BLOCK_VERIFIED` | Existing D-cache unit/CPU/SoC gates | Focused `build/unit_tb/` and `build/soc_test/` logs | Nonblocking D-cache WIP is retired; ECC/coherence are not claimed |
| Dual-core cache notification path | `SOC_INTEGRATED` | `make dcache-coherency-gate dual-core-soc-gate llsc-coherency-gate` | `build/unit_tb/dcache_coherency/`, `build/soc_test/dual_core/`, `build/soc_test/llsc_coherency_gate/` | The frozen opt-in IPI/TLB notification, timeout, stale-ack, busy-reentry, reset-isolation, exception-isolation and CPU LL/SC reservation peer-invalidation slices pass; shared-memory firmware stress, snoop/refill collision and full memory-ordering proof remain outside this gate |
| QSPI XIP retry integration | `SOC_INTEGRATED` | `make qspi-error-taxonomy-gate qspi-retry-policy-gate qspi-axi-xip-gate` | `build/unit_tb/qspi_*` | Bounded one-retry policy; timeout fault-injection at the external flash endpoint remains a separate stress case |
| DDR4 ECC SECDED path | `BLOCK_VERIFIED` | `make ecc-secded-gate ddr4-controller-gate ddr4-controller-stress-gate ddr4-status-gate` | `build/unit_tb/ecc_secded_32/`, `build/unit_tb/axi_ddr4_controller*/`, `build/unit_tb/apb_ddr4_status/` | SECDED correction/detection, controller storage/injection, and APB status classification are verified; SoC IRQ escalation and multi-rank policy are outside this RTL contract |
| EIC/VEIC vector path | `SOC_INTEGRATED` | `make product-vectored-interrupt-gate` | `build/unit_tb/product_vectored_interrupt/` | VEIC is opt-in and uses the VIC source ID contract; nested interrupt policy and full MIPS compliance remain separate |
| ISA R2 implemented subset | `SOC_INTEGRATED` | `make isa-r2-gate` | `build/soc_test/isa_r2_sweep/` | Directed firmware covers implemented R2 ALU/control/CP0 operations; full compliance suite, FPU and reference-model lockstep remain open |
| P1 current RTL/simulation extension bundle | `CONTRACT_CLOSED` | `make p1-current-complete` | `build/p1_complete/p1_completion_report.md` and dependent `build/unit_tb/`, `build/soc_test/`, `build/cpu_mmu_complete/` reports | Aggregate covers the current RTL/simulation slice only; full MESI/directory coherency, full ISA/FPU, Linux/OS boot and production software policy remain open |

## Evidence Rules

1. Every new gate must have a reproducible Make target and write `compile.log`
   and `sim.log` below `build/`.
2. The command, expected success marker, scope, and residual risk must be
   recorded in `docs/functional_completeness_plan.md` or this registry.
3. Coverage exclusion warnings are tracked separately and are not functional
   closure evidence.
4. Current conclusions are limited to RTL frontend, unit, firmware, and SoC
   simulation. They do not imply complete OS/Linux boot, full ISA compliance,
   or production software policy.
