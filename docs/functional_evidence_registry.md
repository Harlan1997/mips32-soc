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
| CPU/MMU SoC PageMask extension | `SOC_INTEGRATED` | `make product-mmu-pagemask-gate` | `build/soc_test/product_mmu_pagemask_pass/sim.log` | Real CPU/DDR behavioral firmware covers ASID 7, 16KB even/odd halves, PFN folding and one refill; larger OS/page-table pressure and the hardware walker's 4KB-only contract remain outside this slice |
| CPU/MMU multi-segment runtime | `SOC_INTEGRATED` | `make product-kseg0-runtime-multi-gate` | `build/unit_tb/product_kseg0_runtime_multi/sim.log`, `sim_multi_wx.log` | No-preload MMU-enabled Boot ROM flow validates three RX/R/RW descriptors, rejects a valid-CRC W+X image before handoff, copies through uncached aliases, and executes copied text; hardware permission enforcement, PIC/GOT/TLS and production ELF loading remain outside this slice |
| CPU/MMU PIC/GOT-style runtime relocation | `SOC_INTEGRATED` | `make product-kseg0-runtime-multi-gate` | `build/unit_tb/product_kseg0_runtime_multi_picgot_two/sim.log`, `sim_multi_wx.log` | RW runtime data carries link-time pointers to both the R-only segment and RX function; stage-1 applies independent source/runtime deltas and invokes copied text through the relocated function pointer. This is a bounded relocation slice, not a complete ELF GOT/PLT or dynamic linker |
| CPU/MMU hardware walker permission integration | `SOC_INTEGRATED` | `make cpu-hardware-walker-gate` plus `make cpu-dside-hardware-walker-gate` plus `make page-table-walker-gate` plus `make page-table-tlb-refill-gate` plus `make mmu-refill-gate` | `build/unit_tb/cpu_dside_hardware_walker/sim.log`, `build/unit_tb/cpu_hardware_walker/sim.log`, `build/unit_tb/page_table_walker/sim.log`, `build/unit_tb/page_table_tlb_refill/sim.log`, `build/soc_test/mmu_refill_bootstrap/sim.log` | CPU opt-in walker covers I/D two-level refill, load/store retry, PA completion, leaf permission latch, TLBL/TLBS classification and request suppression; the bootstrap firmware adds bounded kseg0 software-page-table non-identity fault/refill/ERET evidence; full demand paging and OS page-table ownership remain outside this slice |
| Coverage metadata hygiene | `CONTRACT_CLOSED` | `make coverage-strict-clean-gate` | `build/coverage/strict_clean/exclusion_audit.log`, `uvm_urgReport/`, `product_urgReport/` | Uses empty, audited exclusion files; code coverage percentage is reported separately and is not a 99% signoff claim |
| CPU/CP0 TLS linker/runtime pointer | `SOC_INTEGRATED` | `make cp0-rdhwr-gate` | `build/soc_test/cp0_rdhwr/sim.log`, `tb/soc_test/fw/tests/cp0_sweep/link_tls.ld` | Dedicated linker layout exports `.tdata/.tbss` symbols; UserLocal/RDHWR $29 is used as a real user-mode TLS base for initialized/zeroed slot read/write; TLS relocation model and multi-thread scheduler ABI remain outside this slice |
| CPU/CP0 MTC0 source forwarding and UserLocal context switching | `CONTRACT_CLOSED` | `make rtl-frontend-compile` plus `make cp0-rdhwr-gate` | `build/unit_tb/rtl_frontend_cp0_mtc0_forward`, `build/soc_test/cp0_rdhwr/sim.log` | COP0/MTC0 `rt` is treated as a GPR source and uses existing EX/MEM/WB forwarding; firmware verifies consecutive UserLocal A->B->A writes and RDHWR readback, while CP0/TLB context regression remains passing. Full scheduler ABI remains outside this entry |
| CPU/MMU bounded page-table root allocator | `BLOCK_VERIFIED` | `make mmu-page-table-allocator-gate` | `build/unit_tb/mmu_page_table_allocator/compile.log`, `sim.log` | Four fixed 4KB-aligned root leases, exhaustion, stale-generation rejection and reuse are verified; root memory ownership, PTE population, demand paging and a production OS allocator remain outside this slice |
| UART/WDT/APB baseline | `SOC_INTEGRATED` | `make phase3-complete` and focused UART/WDT gates | `build/uvm/phase3_complete/`, focused `build/unit_tb/` and `build/soc_test/` logs | Production software policy is outside this RTL contract |
| D-cache baseline | `BLOCK_VERIFIED` | Existing D-cache unit/CPU/SoC gates | Focused `build/unit_tb/` and `build/soc_test/` logs | Nonblocking D-cache WIP is retired; ECC/coherence are not claimed |
| Dual-core shared-memory coherency | `SOC_INTEGRATED` | `make dcache-coherency-gate dual-core-soc-gate llsc-coherency-gate coherency-stress-gate` | `build/unit_tb/dcache_coherency/`, `build/soc_test/dual_core/`, `build/soc_test/llsc_coherency_gate/`, `build/soc_test/coherency_stress/` | v0.4 evidence covers bidirectional same-line store visibility, accepted notification order, reset/refill recovery, L1/L2 stale-line invalidation, refill-collision suppression, partial-byte/error behavior, CPU LL/SC peer invalidation and 8-round dual-core firmware stress; full MESI/directory ordering remains outside this contract |
| QSPI XIP retry integration | `SOC_INTEGRATED` | `make qspi-error-taxonomy-gate qspi-retry-policy-gate qspi-axi-xip-gate` | `build/unit_tb/qspi_*` | Bounded one-retry policy; timeout fault-injection at the external flash endpoint remains a separate stress case |
| DDR4 ECC SECDED path | `BLOCK_VERIFIED` | `make ecc-secded-gate ddr4-controller-gate ddr4-controller-stress-gate ddr4-status-gate ddr4-pic-integration-gate` | `build/unit_tb/ecc_secded_32/`, `build/unit_tb/axi_ddr4_controller*/`, `build/unit_tb/apb_ddr4_status/`, `build/unit_tb/ddr4_pic_integration/` | SECDED correction/detection, controller storage/injection, APB status classification, and PIC source 5 fatal/uncorrectable IRQ escalation are verified; multi-rank policy and silicon escalation are outside this RTL contract |
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
