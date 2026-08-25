ROOT_DIR := $(CURDIR)
BUILD_DIR ?= $(ROOT_DIR)/build
FW_NAME ?= soc_smoke
FW_BUILD_DIR ?= $(BUILD_DIR)/firmware/$(FW_NAME)
FW_HEX ?= $(FW_BUILD_DIR)/firmware.hex
PERF_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/perf_cpu
PERF_CPU_FW_HEX ?= $(PERF_CPU_FW_DIR)/firmware.hex
PERF_WORKLOADS_FW_DIR ?= $(BUILD_DIR)/firmware/perf_workloads
PERF_WORKLOADS_FW_HEX ?= $(PERF_WORKLOADS_FW_DIR)/firmware.hex
VIC_NESTED_FW_DIR ?= $(BUILD_DIR)/firmware/vic_nested
VIC_NESTED_FW_HEX ?= $(VIC_NESTED_FW_DIR)/firmware.hex
UVM_TEST ?= soc_bus_stress_test
UVM_SEED ?= 1
UVM_RUN_DIR ?= $(BUILD_DIR)/uvm/single
UVM_REG_DIR ?= $(BUILD_DIR)/uvm/regression
UVM_DIRECTED_DIR ?= $(BUILD_DIR)/uvm/directed
UVM_TESTLIST ?= tb/uvm_tb/phase2_directed_tests.txt
UVM_ENABLE_COV ?= 0
UVM_FLASH_IMAGE ?=
UVM_PHASE3_FLASH_IMAGE ?= tb/uvm_tb/data/flash_xip_image.hex
UVM_PHASE3_DIR ?= $(BUILD_DIR)/uvm/phase3_directed
UVM_PHASE3_TESTLIST ?= tb/uvm_tb/phase3_directed_tests.txt
UVM_PHASE3_COMPLETE_DIR ?= $(BUILD_DIR)/uvm/phase3_complete
UVM_PHASE3B_DIR ?= $(BUILD_DIR)/uvm/phase3b_directed
UVM_PHASE3B_TESTLIST ?= tb/uvm_tb/phase3b_directed_tests.txt
UVM_PHASE3B_COMPLETE_DIR ?= $(BUILD_DIR)/uvm/phase3b_complete
UVM_PHASE3C_DIR ?= $(BUILD_DIR)/uvm/phase3c_directed
UVM_PHASE3C_TESTLIST ?= tb/uvm_tb/phase3c_directed_tests.txt
UVM_PHASE3C_COMPLETE_DIR ?= $(BUILD_DIR)/uvm/phase3c_complete
SOC_TEST_RUN_DIR ?= $(BUILD_DIR)/soc_test/smoke
SOC_TEST_CPU_CP0_DIR ?= $(BUILD_DIR)/soc_test/cpu_cp0_gate
SOC_TEST_SRS_DIR ?= $(BUILD_DIR)/soc_test/srs
SRS_FW_DIR ?= $(BUILD_DIR)/firmware/srs
SRS_FW_HEX ?= $(SRS_FW_DIR)/firmware.hex
SOC_TEST_SRS_EXCEPTION_DIR ?= $(BUILD_DIR)/soc_test/srs_exception
SRS_EXCEPTION_FW_DIR ?= $(BUILD_DIR)/firmware/srs_exception
SRS_EXCEPTION_FW_HEX ?= $(SRS_EXCEPTION_FW_DIR)/firmware.hex
SOC_TEST_SRS_NESTED_DIR ?= $(BUILD_DIR)/soc_test/srs_nested
SRS_NESTED_FW_DIR ?= $(BUILD_DIR)/firmware/srs_nested
SRS_NESTED_FW_HEX ?= $(SRS_NESTED_FW_DIR)/firmware.hex
SOC_TEST_RANDOM_DIR ?= $(BUILD_DIR)/soc_test/random_regression
SIGNOFF_DIR ?= $(BUILD_DIR)/signoff/current_contract
STAGE ?= ex
NUM_TESTS ?= 10
SEED_BASE ?= 1
DUT_BLOCK_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/dut_block_readiness
FABRIC_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/fabric
PRODUCT_MMU_BOOT_DIR ?= $(BUILD_DIR)/unit_tb/product_mmu_boot
PRODUCT_MMU_EBASE_MODIFIED_DIR ?= $(BUILD_DIR)/unit_tb/product_mmu_ebase_modified
PRODUCT_VECTORED_INTERRUPT_DIR ?= $(BUILD_DIR)/unit_tb/product_vectored_interrupt
SPI_FLASH_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/axi_spi_flash
XIP_READ_TIMEOUT_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/axi_read_timeout_guard
QSPI_STATUS_INTEGRATION_DIR ?= $(BUILD_DIR)/unit_tb/qspi_status_integration
QSPI_CMD_BEHAVIORAL_DIR ?= $(BUILD_DIR)/unit_tb/qspi_cmd_behavioral
QSPI_FLASH_BEHAVIORAL_DIR ?= $(BUILD_DIR)/unit_tb/qspi_flash_behavioral
QSPI_PAD_WRAPPER_DIR ?= $(BUILD_DIR)/unit_tb/qspi_pad_wrapper
QSPI_AXI_XIP_DIR ?= $(BUILD_DIR)/unit_tb/qspi_axi_xip
QSPI_AXI_XIP_QUAD_DIR ?= $(BUILD_DIR)/unit_tb/qspi_axi_xip_quad
QSPI_SOC_MEMORY_QUAD_XIP_DIR ?= $(BUILD_DIR)/unit_tb/soc_memory_quad_xip
QSPI_SHARED_PIN_ARBITER_DIR ?= $(BUILD_DIR)/unit_tb/qspi_shared_pin_arbiter
QSPI_SOC_PAD_MUX_DIR ?= $(BUILD_DIR)/unit_tb/qspi_soc_pad_mux
QSPI_SOC_QUAD_DIR ?= $(BUILD_DIR)/unit_tb/qspi_soc_quad
PRODUCT_MANIFEST_HANDOFF_DIR ?= $(BUILD_DIR)/unit_tb/product_manifest_handoff
PRODUCT_MANIFEST_HANDOFF_QUAD_DIR ?= $(BUILD_DIR)/unit_tb/product_manifest_handoff_quad
TLB_ASID_POLICY_DIR ?= $(BUILD_DIR)/unit_tb/tlb_asid_policy
TLB_OS_CONTEXT_DIR ?= $(BUILD_DIR)/unit_tb/tlb_os_context
PRODUCT_KSEG0_RUNTIME_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime
PRODUCT_KSEG0_RUNTIME_DEPTH_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime_depth
PRODUCT_KSEG0_RUNTIME_LAYOUT_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime_layout
PRODUCT_KSEG0_RUNTIME_ABI_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime_abi
PRODUCT_KSEG0_RUNTIME_MULTI_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime_multi
PRODUCT_KERNEL_BOOT_DIR ?= $(BUILD_DIR)/unit_tb/product_kernel_boot
PRODUCT_MMU_ASID_CONTEXT_DIR ?= $(BUILD_DIR)/soc_test/product_mmu_asid_context
PRODUCT_MMU_PROCESS_PRESSURE_DIR ?= $(BUILD_DIR)/soc_test/product_mmu_process_pressure
PRODUCT_MMU_PAGEMASK_DIR ?= $(BUILD_DIR)/soc_test/product_mmu_pagemask
CPU_CACHE_ERROR_DIR ?= $(BUILD_DIR)/unit_tb/cpu_cache_error
CPU_CACHE_OP_DIR ?= $(BUILD_DIR)/unit_tb/cpu_cacheop
CPU_CACHE_TAG_DIR ?= $(BUILD_DIR)/unit_tb/cpu_cachetag
CPU_ICACHE_EXEC_DIR ?= $(BUILD_DIR)/unit_tb/mips_core_icache_exec
CPU_ICACHE_ERROR_DIR ?= $(BUILD_DIR)/unit_tb/mips_core_icache_error
CPU_ICACHE_PRODUCT_ERROR_DIR ?= $(BUILD_DIR)/unit_tb/mips_core_icache_product_error
CPU_ICACHE_STRESS_DIR ?= $(BUILD_DIR)/unit_tb/mips_core_icache_stress
CPU_ICACHE_TAG_DIR ?= $(BUILD_DIR)/unit_tb/mips_core_icache_tag
CPU_SCHEDULER_INTEGRATION_DIR ?= $(BUILD_DIR)/unit_tb/cpu_scheduler_integration
CPU_HARDWARE_WALKER_DIR ?= $(BUILD_DIR)/unit_tb/cpu_hardware_walker
CPU_DSIDE_HARDWARE_WALKER_DIR ?= $(BUILD_DIR)/unit_tb/cpu_dside_hardware_walker
MMU_PAGE_TABLE_ALLOCATOR_DIR ?= $(BUILD_DIR)/unit_tb/mmu_page_table_allocator
MMU_REFILL_DIR ?= $(BUILD_DIR)/soc_test/mmu_refill_bootstrap
MMU_OS_PRESSURE_DIR ?= $(BUILD_DIR)/soc_test/mmu_os_pressure
PRODUCT_CACHEERR_DIR ?= $(BUILD_DIR)/unit_tb/product_cacheerr
WDT_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/wdt
WDT_PERIPHERAL_DIR ?= $(BUILD_DIR)/unit_tb/wdt_peripheral
BOOT_STATUS_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/boot_status
WDT_BOOT_FAILURE_DIR ?= $(BUILD_DIR)/soc_test/wdt_boot_failure_gate
WDT_BOOT_FAILURE_FW_DIR ?= $(BUILD_DIR)/firmware/wdt_boot_failure
WDT_BOOT_FAILURE_FW_HEX ?= $(WDT_BOOT_FAILURE_FW_DIR)/firmware.hex
PRODUCT_WDT_BOOT_FAILURE_DIR ?= $(BUILD_DIR)/unit_tb/product_wdt_boot_failure
DDR_ENTRY_AUDIT_DIR ?= $(BUILD_DIR)/unit_tb/ddr_contract_entry
DDR4_PHY_BEHAVIORAL_DIR ?= $(BUILD_DIR)/unit_tb/ddr4_phy_behavioral
DDR4_CONTROLLER_DIR ?= $(BUILD_DIR)/unit_tb/axi_ddr4_controller

SOC_TEST_MDU_CPU_DIR ?= $(BUILD_DIR)/soc_test/mdu_cpu_gate
MDU_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/mdu_cpu
MDU_CPU_FW_HEX ?= $(MDU_CPU_FW_DIR)/firmware.hex
MDU_FLUSH_DIR ?= $(BUILD_DIR)/unit_tb/mdu_flush

SOC_TEST_DMA_CPU_DIR ?= $(BUILD_DIR)/soc_test/dma_cpu_gate
DMA_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/dma_cpu
DMA_CPU_FW_HEX ?= $(DMA_CPU_FW_DIR)/firmware.hex

SOC_TEST_VIC_CPU_DIR ?= $(BUILD_DIR)/soc_test/vic_cpu_gate
VIC_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/vic_cpu
VIC_CPU_FW_HEX ?= $(VIC_CPU_FW_DIR)/firmware.hex

SOC_TEST_UART_CPU_DIR ?= $(BUILD_DIR)/soc_test/uart_cpu_gate
UART_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/uart_cpu
UART_CPU_FW_HEX ?= $(UART_CPU_FW_DIR)/firmware.hex
UART_EXTERNAL_RX_DIR ?= $(BUILD_DIR)/unit_tb/uart_external_rx
SOC_TEST_UART_EXTERNAL_RX_DIR ?= $(BUILD_DIR)/soc_test/uart_external_rx_gate
UART_EXTERNAL_RX_FW_DIR ?= $(BUILD_DIR)/firmware/uart_external_rx
UART_EXTERNAL_RX_FW_HEX ?= $(UART_EXTERNAL_RX_FW_DIR)/firmware.hex
SOC_TEST_UART_CTS_DIR ?= $(BUILD_DIR)/soc_test/uart_cts_gate
UART_CTS_FW_DIR ?= $(BUILD_DIR)/firmware/uart_cts
UART_CTS_FW_HEX ?= $(UART_CTS_FW_DIR)/firmware.hex
DDR4_STATUS_SOC_DIR ?= $(BUILD_DIR)/soc_test/ddr4_status_gate
DDR4_STATUS_FW_DIR ?= $(BUILD_DIR)/firmware/ddr4_status

SOC_TEST_L2_CPU_DIR ?= $(BUILD_DIR)/soc_test/l2_cpu_gate
L2_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/l2_cpu
L2_CPU_FW_HEX ?= $(L2_CPU_FW_DIR)/firmware.hex
SOC_TEST_L2_E2E_DIR ?= $(BUILD_DIR)/soc_test/l2_end_to_end
L2_E2E_FW_DIR ?= $(BUILD_DIR)/firmware/l2_e2e
L2_E2E_FW_HEX ?= $(L2_E2E_FW_DIR)/firmware.hex

SOC_TEST_LLSC_DIR ?= $(BUILD_DIR)/soc_test/llsc_gate
SOC_TEST_LLSC_COHERENCY_DIR ?= $(BUILD_DIR)/soc_test/llsc_coherency_gate
LLSC_FW_DIR ?= $(BUILD_DIR)/firmware/llsc
LLSC_COHERENCY_FW_DIR ?= $(BUILD_DIR)/firmware/llsc_coherency
LLSC_FW_HEX ?= $(LLSC_FW_DIR)/firmware.hex
COHERENCY_STRESS_DIR ?= $(BUILD_DIR)/soc_test/coherency_stress
COHERENCY_STRESS_FW_DIR ?= $(BUILD_DIR)/firmware/coherency_stress
CP0_RDHWR_DIR ?= $(BUILD_DIR)/soc_test/cp0_rdhwr
CP0_RDHWR_FW_DIR ?= $(BUILD_DIR)/firmware/cp0_rdhwr
P1_COMPLETE_DIR ?= $(BUILD_DIR)/p1_complete
SVA_DIR ?= $(BUILD_DIR)/sva

bpu-redirect-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/bpu_redirect_unit tb/unit/bpu/run.sh
	SOC_BPU_ENABLE=1 RUN_ROOT=$(BUILD_DIR)/unit_tb/bpu_redirect_compile tb/unit/run_rtl_frontend_compile.sh

sva-gate: firmware
	RUN_ROOT=$(SVA_DIR) FW_HEX=$(FW_HEX) tb/sva/run_sva_gate.sh

verification-foundation-gate:
	RUN_ROOT=$(BUILD_DIR)/verification_foundation scripts/run_verification_foundation_gate.sh

mdu-flush-gate:
	RUN_DIR=$(MDU_FLUSH_DIR) tb/unit/mdu/run_flush_gate.sh

dcache-parity-gate:
	chmod +x tb/unit/dcache/run_parity.sh
	RUN_DIR=$(BUILD_DIR)/unit_tb/dcache_parity tb/unit/dcache/run_parity.sh

.PHONY: bpu-redirect-gate sva-gate verification-foundation-gate micro-tlb-gate interrupt-priority-gate mdu-flush-gate mips-control-fpu-cond-gate mips-fpu-compare-gate firmware firmwares uvm uvm-regression uvm-directed-regression regression phase2-regression phase2-complete phase3-regression phase3-complete phase3b-regression phase3b-complete phase3c-regression current-contract-signoff soc-smoke cpu-cp0-gate cpu-mmu-complete p1-current-complete dual-core-frontend-compile dual-core-soc-gate dcache-coherency-gate coherency-stress-gate mdu-cpu-gate dma-cpu-gate dma-axi-error-gate vic-cpu-gate vic-full-sources-gate uart-cpu-gate uart-external-rx-gate uart-external-rx-soc-gate uart-cts-soc-gate l2-cpu-gate l2-end-to-end-gate llsc-gate llsc-coherency-gate product-mmu-boot-gate product-mmu-micro-tlb-gate product-mmu-ebase-modified-gate product-mmu-asid-context-gate product-mmu-process-pressure-gate product-mmu-pagemask-gate product-vectored-interrupt-gate spi-flash-unit-gate xip-read-timeout-unit-gate qspi-status-integration-gate qspi-cmd-behavioral-gate qspi-flash-behavioral-gate qspi-pad-wrapper-gate qspi-axi-xip-gate qspi-axi-xip-quad-gate qspi-soc-memory-quad-xip-gate qspi-shared-pin-arbiter-gate qspi-soc-pad-mux-gate qspi-soc-quad-gate qspi-vendor-neutral-boot-gate product-manifest-handoff-gate product-manifest-handoff-quad-gate product-kseg0-runtime-gate product-kseg0-runtime-depth-gate product-kseg0-runtime-layout-gate product-kseg0-runtime-abi-gate product-kseg0-runtime-multi-gate product-kernel-boot-gate tlb-asid-policy-gate tlb-os-context-gate tlb-invalidate-gate mmu-active-gate mmu-hardware-walker-soc-gate wdt-unit-gate wdt-peripheral-gate boot-status-unit-gate wdt-boot-failure-gate product-wdt-boot-failure-gate cpu-cache-error-gate cpu-cache-op-gate cpu-cache-tag-gate cpu-icache-exec-gate cpu-icache-error-gate cpu-icache-product-error-gate cpu-icache-stress-gate cpu-icache-tag-gate product-cacheerr-gate ddr-contract-entry-audit ddr4-phy-behavioral-gate ddr4-status-gate ddr4-pic-integration-gate ddr4-controller-gate ddr4-controller-stress-gate ddr4-complete-gate ecc-secded-gate rtl-frontend-compile rob-fifo-gate soc-random-regression stage-sim dut-block-unit-gate cpu-dside-hardware-walker-gate page-table-walker-page-sizes-gate cpu-hardware-walker-page-size-gate cpu-hardware-walker-page-sizes-gate coverage-strict-clean-gate linux-boot-fetch-sources linux-boot-dependency-gate qemu-linux-user project-tree clean-firmware clean-build clean-legacy-artifacts clean

.PHONY: cache-concurrency-gate l1-nonblocking-gate l1-nonblocking-errors-gate l1-nonblocking-axi-bridge-gate l1-nonblocking-cpu-compat-gate l1-nonblocking-cpu-multi-gate l1-nonblocking-cpu-stress-gate l1-nonblocking-cpu-error-gate l1-nonblocking-cpu-two-error-gate l1-nonblocking-cpu-error-reset-gate mmu-ipi-shootdown-pressure-gate fpu-single-gate fpu-double-gate fpu-cu1-exception-gate fpu-fpe-exception-gate fpu-fpe-double-gate fpu-fpe-inexact-gate fpu-fpe-double-inexact-gate fpu-fpe-double-underflow-gate fpu-fpe-invalid-gate fpu-fpe-overflow-gate fpu-fpe-underflow-gate fpu-rounding-gate qemu-system-fpu-single-differential-gate qemu-system-fpu-double-differential-gate qemu-system-fpu-cu1-exception-differential-gate qemu-system-fpu-fpe-inexact-differential-gate qemu-system-fpu-fpe-double-inexact-differential-gate qemu-system-fpu-fpe-double-underflow-differential-gate qemu-system-branch-likely-differential-gate cpu-reference-gate cpu-lockstep-gate perf-counters-gate qemu-system-mips32-soc-ref qemu-system-sram-uart-mailbox-gate qemu-system-peripheral-contract-gate qemu-system-qspi-gate qemu-system-ddr-gate qemu-system-current-contract-gate qemu-system-selected-differential-gate qemu-system-retire-capture-gate qemu-system-retire-differential-gate qemu-system-isa-r2-differential-gate qemu-system-exception-differential-gate qemu-system-break-differential-gate qemu-system-trap-differential-gate qemu-system-trap-imm-differential-gate qemu-system-di-ei-differential-gate qemu-system-wait-differential-gate qemu-system-bd-exception-differential-gate qemu-system-peripheral-differential-gate qemu-system-vic-differential-gate qemu-system-vic-cpu-differential-gate qemu-system-vic-full-sources-differential-gate qemu-system-mmu-contract-gate qemu-system-mmu-process-pressure-gate qemu-system-mmu-refill-differential-gate qemu-system-dma-v2-model-gate qemu-system-dma-v2-event-contract-gate qemu-system-dma-fault-gate qemu-system-unaligned-gate qemu-system-unaligned-differential-gate qemu-system-uhi-dtb-gate
.PHONY: isa-implementation-audit branch-likely-gate bitswap-gate fpu-branch-gate qemu-system-fpu-branch-differential-gate mips-fpu-recip-gate mips-fpu-flags-gate mips-regfile-srs-gate mips-control-srs-gate srs-map-gate srs-firmware srs-gate srs-exception-firmware srs-exception-gate srs-nested-firmware srs-nested-gate srs-scheduler-context-gate qemu-system-srs-exception-differential-gate qemu-system-srs-nested-differential-gate qemu-system-srs-map-differential-gate llsc-interrupt-boundary-gate
.PHONY: l1-nonblocking-maintenance-compat-gate l1-nonblocking-ddr-gate qemu-system-l1-ddr-differential-gate
.PHONY: l2-nonblocking-end-to-end-gate
.PHONY: qemu-system-dma-sg-data-gate qemu-system-dma-sg-differential-gate
.PHONY: l1-nonblocking-cpu-two-error-reset-gate
.PHONY: qemu-system-mmu-os-pressure-gate qemu-system-mmu-ipi-contract-gate qemu-system-gpio-input-gate qemu-system-ddr-fault-gate
.PHONY: linux-boot-build-gate
.PHONY: linux-uboot-build-gate
.PHONY: linux-uboot-custom-machine-probe
.PHONY: qemu-system-architecture-closure-gate
.PHONY: soc-filelist-audit
.PHONY: qspi-vendor-neutral-complete-gate
.PHONY: perf-cpu-gate perf-workloads-gate vic-nested-gate
.PHONY: fpu-context-gate
.PHONY: dcache-parity-gate

isa-implementation-audit:
	@mkdir -p $(BUILD_DIR)/isa_audit
	python3 scripts/check_isa_matrix.py | tee $(BUILD_DIR)/isa_audit/isa_implementation_audit.log
	@printf '# ISA Implementation Audit\n\n- Result: PASS\n- Evidence: `scripts/check_isa_matrix.py` and `docs/isa_implementation_matrix.md`\n- Boundary: this is not full ISA compliance.\n' > $(BUILD_DIR)/isa_audit/isa_implementation_audit_report.md

branch-likely-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/branch_likely tb/soc_test/run_branch_likely_gate.sh

bitswap-gate:
	$(MAKE) -C tb/soc_test/fw/tests/bitswap OUT_DIR=$(BUILD_DIR)/firmware/bitswap FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/bitswap FW_DIR=$(BUILD_DIR)/firmware/bitswap \
	FW_HEX=$(BUILD_DIR)/firmware/bitswap/firmware.hex \
	VCS_EXTRA_ARGS='+define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-branch-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_branch OUT_DIR=$(BUILD_DIR)/firmware/fpu_branch FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_branch FW_DIR=$(BUILD_DIR)/firmware/fpu_branch \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_branch/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK +define+TB_FPU_ROUND_DEBUG' \
	tb/soc_test/run.sh

qemu-system-fpu-branch-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_branch RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_branch_differential \
	RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
	tb/isa_ref/run_qemu_system_differential_gate.sh

mips-fpu-recip-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_fpu_recip tb/unit/cpu_test/run_mips_fpu_recip.sh
.PHONY: dma-reset-inflight-gate

linux-boot-dependency-gate:
	bash tb/linux_boot/check_dependencies.sh

linux-boot-fetch-sources:
	bash tb/linux_boot/fetch_sources.sh

mdu-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=mdu_cpu OUT_DIR=$(MDU_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(MDU_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_MDU_CPU_DIR) tb/soc_test/run_mdu_cpu_gate.sh

dma-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=dma_cpu OUT_DIR=$(DMA_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(DMA_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_DMA_CPU_DIR) tb/soc_test/run_dma_cpu_gate.sh

dma-axi-error-gate:
	chmod +x tb/soc_test/run_dma_axi_error_gate.sh
	RUN_DIR=$(BUILD_DIR)/soc_test/dma_axi_error \
	FW_DIR=$(BUILD_DIR)/firmware/dma_axi_error \
	tb/soc_test/run_dma_axi_error_gate.sh

dma-reset-inflight-gate:
	chmod +x tb/soc_test/run_dma_reset_inflight_gate.sh
	RUN_DIR=$(BUILD_DIR)/soc_test/dma_reset_inflight \
	FW_DIR=$(BUILD_DIR)/firmware/dma_reset_inflight \
	tb/soc_test/run_dma_reset_inflight_gate.sh


vic-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=vic_cpu OUT_DIR=$(VIC_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(VIC_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_VIC_CPU_DIR) tb/soc_test/run_vic_cpu_gate.sh

uart-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=uart_cpu OUT_DIR=$(UART_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(UART_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_UART_CPU_DIR) tb/soc_test/run_uart_cpu_gate.sh

uart-external-rx-gate:
	RUN_DIR=$(UART_EXTERNAL_RX_DIR) tb/unit/uart/run_uart_external_rx.sh

uart-pad-wrapper-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/uart_pad_wrapper tb/unit/uart/run_uart_pad_wrapper.sh

uart-external-rx-soc-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=uart_external_rx OUT_DIR=$(abspath $(UART_EXTERNAL_RX_FW_DIR)) FW_BASE=firmware all
	FW_HEX=$(abspath $(UART_EXTERNAL_RX_FW_DIR))/firmware.hex RUN_DIR=$(SOC_TEST_UART_EXTERNAL_RX_DIR) tb/soc_test/run_uart_external_rx_gate.sh

uart-cts-soc-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=uart_cts OUT_DIR=$(abspath $(UART_CTS_FW_DIR)) FW_BASE=firmware all
	FW_HEX=$(UART_CTS_FW_HEX) RUN_DIR=$(SOC_TEST_UART_CTS_DIR) tb/soc_test/run_uart_cts_gate.sh

ddr4-status-soc-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=ddr4_status OUT_DIR=$(abspath $(DDR4_STATUS_FW_DIR)) FW_BASE=firmware all
	FW_HEX=$(abspath $(DDR4_STATUS_FW_DIR))/firmware.hex RUN_DIR=$(DDR4_STATUS_SOC_DIR) tb/soc_test/run_ddr4_status_gate.sh

l2-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=l2_cpu OUT_DIR=$(L2_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(L2_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_L2_CPU_DIR) tb/soc_test/run_l2_cpu_gate.sh

l2-end-to-end-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=l2_e2e OUT_DIR=$(L2_E2E_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(L2_E2E_FW_HEX) RUN_DIR=$(SOC_TEST_L2_E2E_DIR) tb/soc_test/run_l2_end_to_end_gate.sh

l2-nonblocking-end-to-end-gate:
	L2_NONBLOCKING=1 $(MAKE) l2-end-to-end-gate \
		SOC_TEST_L2_E2E_DIR=$(BUILD_DIR)/soc_test/l2_end_to_end_nonblocking

llsc-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=llsc OUT_DIR=$(abspath $(LLSC_FW_DIR)) FW_BASE=firmware all
	FW_HEX=$(abspath $(LLSC_FW_DIR))/firmware.hex RUN_DIR=$(SOC_TEST_LLSC_DIR) tb/soc_test/run_llsc_gate.sh

llsc-coherency-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=llsc COHERENCY=1 OUT_DIR=$(abspath $(LLSC_COHERENCY_FW_DIR)) FW_BASE=firmware all
	FW_HEX=$(abspath $(LLSC_COHERENCY_FW_DIR))/firmware.hex RUN_DIR=$(SOC_TEST_LLSC_COHERENCY_DIR) tb/soc_test/run_llsc_coherency_gate.sh

product-mmu-boot-gate:
	RUN_DIR=$(PRODUCT_MMU_BOOT_DIR) tb/unit/bootrom/run_product_mmu_boot.sh

product-mmu-micro-tlb-gate:
	SOC_MICRO_TLB_ENABLE=1 RUN_DIR=$(BUILD_DIR)/unit_tb/product_mmu_micro_tlb tb/unit/bootrom/run_product_mmu_boot.sh
	SOC_MICRO_TLB_ENABLE=1 RUN_DIR=$(BUILD_DIR)/unit_tb/product_tlb_vectors_micro tb/unit/bootrom/run_product_tlb_vectors.sh

product-mmu-ebase-modified-gate:
	RUN_DIR=$(PRODUCT_MMU_EBASE_MODIFIED_DIR) tb/unit/bootrom/run_product_mmu_ebase_modified.sh

product-vectored-interrupt-gate:
	RUN_DIR=$(PRODUCT_VECTORED_INTERRUPT_DIR) tb/unit/bootrom/run_product_vectored_interrupt.sh

spi-flash-unit-gate:
	RUN_DIR=$(SPI_FLASH_UNIT_DIR) tb/unit/flash/run_axi_spi_flash.sh

xip-read-timeout-unit-gate:
	RUN_DIR=$(XIP_READ_TIMEOUT_UNIT_DIR) tb/unit/flash/run_axi_read_timeout_guard.sh

qspi-status-integration-gate:
	RUN_DIR=$(QSPI_STATUS_INTEGRATION_DIR) tb/unit/flash/run_qspi_status_integration.sh

qspi-error-taxonomy-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/qspi_error_taxonomy tb/unit/flash/run_qspi_error_taxonomy.sh

qspi-retry-policy-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/qspi_retry_policy tb/unit/flash/run_qspi_retry_policy.sh

tlb-shootdown-mailbox-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/tlb_shootdown_mailbox tb/unit/tlb/run_tlb_shootdown_mailbox.sh

mmu-ipi-shootdown-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mmu_ipi_shootdown tb/unit/tlb/run_mmu_ipi_shootdown.sh

mmu-ipi-shootdown-pressure-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mmu_ipi_shootdown_pressure tb/unit/tlb/run_mmu_ipi_shootdown_pressure.sh

apb-mmu-ipi-status-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/apb_mmu_ipi_status tb/unit/tlb/run_apb_mmu_ipi_status.sh

tlb-asid-allocator-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/tlb_asid_allocator tb/unit/tlb/run_tlb_asid_allocator.sh

mmu-context-contract-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mmu_context_contract tb/unit/tlb/run_mmu_context_contract.sh

mmu-active-gate:
	RUN_DIR=$(BUILD_DIR)/unit/mmu_active tb/unit/mmu/run_active.sh

micro-tlb-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/micro_tlb tb/unit/tlb/run_micro_tlb.sh

mips-control-fpu-cond-gate:
	chmod +x tb/unit/cpu_test/run_mips_control_fpu_cond.sh
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_control_fpu_cond tb/unit/cpu_test/run_mips_control_fpu_cond.sh

mips-fpu-compare-gate:
	chmod +x tb/unit/cpu_test/run_mips_fpu_compare.sh
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_fpu_compare tb/unit/cpu_test/run_mips_fpu_compare.sh

mips-fpu-flags-gate:
	chmod +x tb/unit/cpu_test/run_mips_fpu_flags.sh
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_fpu_flags tb/unit/cpu_test/run_mips_fpu_flags.sh

interrupt-priority-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/vic_priority_checker tb/unit/vic/run_priority_checker.sh

mmu-context-status-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mmu_context_status tb/unit/tlb/run_mmu_context_status.sh

axi2apb-write-timing-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/axi2apb_write_timing tb/unit/axi/run_axi2apb_bridge.sh

dcache-attr-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/dcache_attr tb/unit/dcache/run_attr.sh

product-mmu-context-cpu-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/product_mmu_context_cpu tb/soc_test/run_product_mmu_context_cpu.sh

qspi-cmd-behavioral-gate:
	RUN_DIR=$(QSPI_CMD_BEHAVIORAL_DIR) tb/unit/flash/run_qspi_cmd_behavioral.sh

qspi-flash-behavioral-gate:
	RUN_DIR=$(QSPI_FLASH_BEHAVIORAL_DIR) tb/unit/flash/run_qspi_flash_behavioral.sh

qspi-pad-wrapper-gate:
	RUN_DIR=$(QSPI_PAD_WRAPPER_DIR) tb/unit/flash/run_qspi_pad_wrapper.sh

qspi-axi-xip-gate:
	RUN_DIR=$(QSPI_AXI_XIP_DIR) tb/unit/flash/run_qspi_axi_xip.sh

qspi-axi-xip-quad-gate:
	RUN_DIR=$(QSPI_AXI_XIP_QUAD_DIR) tb/unit/flash/run_qspi_axi_xip_quad.sh

qspi-soc-memory-quad-xip-gate:
	RUN_DIR=$(QSPI_SOC_MEMORY_QUAD_XIP_DIR) tb/unit/flash/run_soc_memory_quad_xip.sh

qspi-shared-pin-arbiter-gate:
	RUN_DIR=$(QSPI_SHARED_PIN_ARBITER_DIR) tb/unit/flash/run_qspi_shared_pin_arbiter.sh

qspi-soc-pad-mux-gate:
	RUN_DIR=$(QSPI_SOC_PAD_MUX_DIR) tb/unit/flash/run_qspi_soc_pad_mux.sh

qspi-soc-quad-gate:
	RUN_DIR=$(QSPI_SOC_QUAD_DIR) tb/unit/flash/run_qspi_status_integration.sh

qspi-vendor-neutral-complete-gate: spi-flash-unit-gate xip-read-timeout-unit-gate qspi-status-integration-gate qspi-error-taxonomy-gate qspi-retry-policy-gate qspi-cmd-behavioral-gate qspi-flash-behavioral-gate qspi-pad-wrapper-gate qspi-axi-xip-gate qspi-axi-xip-quad-gate qspi-soc-memory-quad-xip-gate qspi-shared-pin-arbiter-gate qspi-soc-pad-mux-gate qspi-soc-quad-gate
	@echo "QSPI vendor-neutral functional closure gate: PASS"

qspi-vendor-neutral-boot-gate: product-manifest-handoff-gate product-manifest-handoff-quad-gate
	@echo "QSPI vendor-neutral development boot gate: PASS"

product-manifest-handoff-gate:
	RUN_DIR=$(PRODUCT_MANIFEST_HANDOFF_DIR) tb/unit/bootrom/run_product_manifest_handoff.sh

.PHONY: product-manifest-handoff-quad-gate
product-manifest-handoff-quad-gate:
	QSPI_QUAD=1 RUN_DIR=$(PRODUCT_MANIFEST_HANDOFF_QUAD_DIR) tb/unit/bootrom/run_product_manifest_handoff.sh

product-kseg0-runtime-gate:
	SOC_MMU_ENABLE=1 RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_DIR) tb/unit/bootrom/run_product_manifest_handoff.sh

product-kseg0-runtime-depth-gate:
	SOC_MMU_ENABLE=1 RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_DEPTH_DIR) tb/unit/bootrom/run_product_kseg0_runtime_depth.sh

product-kseg0-runtime-layout-gate:
	RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_LAYOUT_DIR) tb/unit/bootrom/run_product_kseg0_runtime_layout.sh

product-kseg0-runtime-abi-gate:
	RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_ABI_DIR) tb/unit/bootrom/run_product_kseg0_runtime_abi.sh

product-kseg0-runtime-multi-gate:
	RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_MULTI_DIR) tb/unit/bootrom/run_product_kseg0_runtime_multi.sh

product-kernel-boot-gate:
	RUN_DIR=$(PRODUCT_KERNEL_BOOT_DIR) tb/unit/bootrom/run_product_kernel_boot.sh

product-mmu-asid-context-gate:
	RUN_DIR=$(PRODUCT_MMU_ASID_CONTEXT_DIR) tb/soc_test/run_product_mmu_asid_context.sh

product-mmu-process-pressure-gate:
	RUN_DIR=$(PRODUCT_MMU_PROCESS_PRESSURE_DIR) tb/soc_test/run_product_mmu_process_pressure.sh

product-mmu-pagemask-gate:
	RUN_DIR=$(PRODUCT_MMU_PAGEMASK_DIR) tb/soc_test/run_product_mmu_pagemask.sh

cpu-cache-error-gate:
	RUN_DIR=$(CPU_CACHE_ERROR_DIR) tb/unit/cpu_test/run_cache_error.sh

cpu-cache-op-gate:
	RUN_DIR=$(CPU_CACHE_OP_DIR) tb/unit/cpu_test/run_cache_op.sh

cpu-cache-tag-gate:
	RUN_DIR=$(CPU_CACHE_TAG_DIR) tb/unit/cpu_test/run_cache_tag.sh

cpu-icache-exec-gate:
	RUN_DIR=$(CPU_ICACHE_EXEC_DIR) tb/unit/cpu_test/run_mips_core_icache_exec.sh

cpu-icache-error-gate:
	RUN_DIR=$(CPU_ICACHE_ERROR_DIR) tb/unit/cpu_test/run_mips_core_icache_error.sh

cpu-icache-product-error-gate:
	RUN_DIR=$(CPU_ICACHE_PRODUCT_ERROR_DIR) tb/unit/cpu_test/run_mips_core_icache_product_error.sh

cpu-icache-stress-gate:
	RUN_DIR=$(CPU_ICACHE_STRESS_DIR) tb/unit/cpu_test/run_mips_core_icache_stress.sh

cpu-icache-tag-gate:
	RUN_DIR=$(CPU_ICACHE_TAG_DIR) tb/unit/cpu_test/run_mips_core_icache_tag.sh

product-cacheerr-gate:
	RUN_DIR=$(PRODUCT_CACHEERR_DIR) tb/unit/bootrom/run_product_cacheerr.sh

tlb-asid-policy-gate:
	RUN_DIR=$(TLB_ASID_POLICY_DIR) tb/unit/tlb/run_tlb_asid_policy.sh

tlb-invalidate-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/tlb_invalidate tb/unit/tlb/run_tlb_invalidate.sh

tlb-os-context-gate:
	RUN_DIR=$(TLB_OS_CONTEXT_DIR) tb/unit/tlb/run_tlb_os_context.sh

wdt-unit-gate:
	RUN_DIR=$(WDT_UNIT_DIR) tb/unit/wdt/run_wdt.sh

wdt-peripheral-gate:
	RUN_DIR=$(WDT_PERIPHERAL_DIR) tb/unit/wdt/run_wdt_peripheral.sh

boot-status-unit-gate:
	RUN_DIR=$(BOOT_STATUS_UNIT_DIR) tb/unit/wdt/run_boot_status.sh

wdt-boot-failure-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=wdt_boot_failure OUT_DIR=$(WDT_BOOT_FAILURE_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(WDT_BOOT_FAILURE_FW_HEX) RUN_DIR=$(WDT_BOOT_FAILURE_DIR) tb/soc_test/run_wdt_boot_failure_gate.sh

product-wdt-boot-failure-gate:
	RUN_DIR=$(PRODUCT_WDT_BOOT_FAILURE_DIR) tb/unit/bootrom/run_product_wdt_boot_failure.sh

ddr-contract-entry-audit:
	RUN_DIR=$(DDR_ENTRY_AUDIT_DIR) tb/unit/run_ddr_contract_entry_audit.sh

.PHONY: ddr4-phy-behavioral-gate
ddr4-status-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/apb_ddr4_status tb/unit/ddr4/run_apb_ddr4_status.sh

ddr4-pic-integration-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/ddr4_pic_integration tb/unit/ddr4/run_ddr4_pic_integration.sh

ddr4-phy-behavioral-gate:
	RUN_DIR=$(DDR4_PHY_BEHAVIORAL_DIR) tb/unit/ddr4/run_ddr4_phy_behavioral.sh

ddr4-controller-gate:
	RUN_DIR=$(DDR4_CONTROLLER_DIR) tb/unit/ddr4/run_axi_ddr4_controller.sh

ddr4-controller-stress-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/axi_ddr4_controller_stress tb/unit/ddr4/run_axi_ddr4_controller_stress.sh

ddr4-complete-gate: ddr4-controller-gate ddr4-controller-stress-gate ddr4-status-gate ddr4-pic-integration-gate
	@echo "DDR4 RTL functional closure gate: PASS"


ecc-secded-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/ecc_secded_32 tb/unit/ddr4/run_ecc_secded_32.sh

isa-r2-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/isa_r2_sweep FW_DIR=$(BUILD_DIR)/firmware/isa_r2_sweep tb/soc_test/run_isa_r2_gate.sh

mips-control-special3-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_control_special3 tb/unit/cpu_test/run_mips_control_special3.sh

mips-regfile-srs-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_regfile_srs tb/unit/cpu_test/run_mips_regfile_srs.sh

mips-control-srs-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_control_srs tb/unit/cpu_test/run_mips_control_srs.sh

srs-map-gate:
	SRS_MAP_TEST=1 RUN_DIR=$(BUILD_DIR)/unit_tb/cp0_srs_map tb/unit/cp0/run.sh

mips-control-cache-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_control_cache tb/unit/cpu_test/run_mips_control_cache.sh

mips-control-cp0-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/mips_control_cp0 tb/unit/cpu_test/run_mips_control_cp0.sh

cpu-reference-gate:
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu tb/isa_ref/run_qemu_reference_gate.sh

cpu-lockstep-gate:
	RUN_DIR=$(BUILD_DIR)/isa_ref/lockstep tb/isa_ref/run_cpu_lockstep_gate.sh

qemu-system-mips32-soc-ref:
	scripts/qemu/build_mips32_soc_ref.sh

qemu-linux-user:
	chmod +x scripts/qemu/build_mips32_linux_user.sh
	scripts/qemu/build_mips32_linux_user.sh

qemu-system-sram-uart-mailbox-gate: qemu-system-mips32-soc-ref
	tb/soc_test/run_qemu_system_smoke_gate.sh

qemu-system-uhi-dtb-gate: qemu-system-mips32-soc-ref
	chmod +x tb/linux_boot/run_uhi_dtb_gate.sh
	RUN_DIR=$(BUILD_DIR)/linux_boot/uhi_dtb tb/linux_boot/run_uhi_dtb_gate.sh

linux-boot-build-gate: qemu-system-mips32-soc-ref
	chmod +x tb/linux_boot/build_linux_boot.sh tb/linux_boot/run_linux_boot_gate.sh
	RUN_DIR=$(BUILD_DIR)/linux_boot/real tb/linux_boot/run_linux_boot_gate.sh

linux-uboot-build-gate:
	chmod +x tb/linux_boot/run_uboot_build_gate.sh
	RUN_DIR=$(BUILD_DIR)/linux_boot/uboot tb/linux_boot/run_uboot_build_gate.sh

linux-uboot-custom-machine-probe: qemu-system-mips32-soc-ref
	chmod +x tb/linux_boot/run_uboot_custom_machine_probe.sh
	RUN_DIR=$(BUILD_DIR)/linux_boot/uboot_custom_probe tb/linux_boot/run_uboot_custom_machine_probe.sh

qemu-system-peripheral-contract-gate: qemu-system-mips32-soc-ref
	chmod +x tb/soc_test/run_qemu_system_peripherals_gate.sh
	tb/soc_test/run_qemu_system_peripherals_gate.sh

qemu-system-retire-capture-gate: qemu-system-mips32-soc-ref qemu-system-sram-uart-mailbox-gate
	chmod +x tb/isa_ref/run_qemu_system_retire_capture_gate.sh
	tb/isa_ref/run_qemu_system_retire_capture_gate.sh

qemu-system-retire-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-dma-sg-data-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_dma_sg_data_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_dma_sg_data \
		tb/isa_ref/run_qemu_system_dma_sg_data_gate.sh

qemu-system-dma-sg-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=qemu_system_dma_sg QEMU_CPU=24Kc RTL_TIMEOUT=180 \
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_dma_sg_differential \
	RTL_VCS_EXTRA_ARGS='+define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-dma-v2-model-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_dma_v2_model_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_dma_v2_model tb/isa_ref/run_qemu_system_dma_v2_model_gate.sh

qemu-system-dma-v2-event-contract-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_dma_v2_event_contract_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_dma_v2_event_contract tb/isa_ref/run_qemu_system_dma_v2_event_contract_gate.sh

qemu-system-dma-fault-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_dma_fault_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_dma_fault tb/isa_ref/run_qemu_system_dma_fault_gate.sh

qemu-system-unaligned-gate:
	chmod +x tb/soc_test/run_qemu_system_unaligned_gate.sh
	tb/soc_test/run_qemu_system_unaligned_gate.sh

qemu-system-unaligned-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_unaligned_differential_gate.sh
	tb/isa_ref/run_qemu_system_unaligned_differential_gate.sh

qemu-system-qspi-gate: qemu-system-mips32-soc-ref
	chmod +x tb/soc_test/run_qemu_system_qspi_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_qspi tb/soc_test/run_qemu_system_qspi_gate.sh

qemu-system-ddr-gate: qemu-system-mips32-soc-ref
	chmod +x tb/soc_test/run_qemu_system_ddr_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_ddr tb/soc_test/run_qemu_system_ddr_gate.sh

qemu-system-current-contract-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_current_contract_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_current_contract tb/isa_ref/run_qemu_system_current_contract_gate.sh

qemu-system-architecture-closure-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_architecture_closure_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_architecture_closure tb/isa_ref/run_qemu_system_architecture_closure_gate.sh

qemu-system-selected-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_selected_differential_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_selected_differential tb/isa_ref/run_qemu_system_selected_differential_gate.sh

qemu-system-isa-r2-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=isa_r2_sweep RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_isa_r2_differential tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-single-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_single QEMU_CPU=24Kf RTL_TIMEOUT=120 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_single_differential RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-double-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_double QEMU_CPU=24Kf RTL_TIMEOUT=120 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_double_differential RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-cu1-exception-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_cu1_exception QEMU_CPU=24Kf RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_cu1_exception_differential RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-fpe-inexact-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_fpe_inexact QEMU_CPU=24Kf QEMU_CAPTURE_TMPDIR=1 RTL_TIMEOUT=120 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_fpe_inexact_differential_v2 RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-fpe-double-inexact-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_fpe_double_inexact QEMU_CPU=24Kf QEMU_CAPTURE_TMPDIR=1 RTL_TIMEOUT=120 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_fpe_double_inexact_differential RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-fpu-fpe-double-underflow-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=fpu_fpe_double_underflow QEMU_CPU=24Kf QEMU_CAPTURE_TMPDIR=1 RTL_TIMEOUT=120 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_fpu_fpe_double_underflow_differential RTL_VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-branch-likely-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=branch_likely RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_branch_likely_differential tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-exception-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_exception_differential_gate.sh
	tb/isa_ref/run_qemu_system_exception_differential_gate.sh

qemu-system-break-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_break_differential_gate.sh
	tb/isa_ref/run_qemu_system_break_differential_gate.sh

qemu-system-trap-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_trap_differential_gate.sh
	tb/isa_ref/run_qemu_system_trap_differential_gate.sh

qemu-system-trap-imm-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_trap_imm_differential_gate.sh
	tb/isa_ref/run_qemu_system_trap_imm_differential_gate.sh

qemu-system-di-ei-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_di_ei_differential_gate.sh
	tb/isa_ref/run_qemu_system_di_ei_differential_gate.sh

qemu-system-wait-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_wait_differential_gate.sh
	tb/isa_ref/run_qemu_system_wait_differential_gate.sh

qemu-system-bd-exception-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_bd_exception_differential_gate.sh
	tb/isa_ref/run_qemu_system_bd_exception_differential_gate.sh

qemu-system-peripheral-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_peripheral_differential_gate.sh
	tb/isa_ref/run_qemu_system_peripheral_differential_gate.sh

qemu-system-vic-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_vic_differential_gate.sh
	tb/isa_ref/run_qemu_system_vic_differential_gate.sh

qemu-system-vic-cpu-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_vic_cpu_differential_gate.sh
	tb/isa_ref/run_qemu_system_vic_cpu_differential_gate.sh

qemu-system-vic-full-sources-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_vic_full_sources_differential_gate.sh
	FW_TEST=vic_full_sources RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_vic_full_sources_differential \
		tb/isa_ref/run_qemu_system_vic_full_sources_differential_gate.sh

qemu-system-mmu-contract-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_contract_gate.sh
	tb/isa_ref/run_qemu_system_mmu_contract_gate.sh

qemu-system-mmu-process-pressure-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_process_pressure_gate.sh
	tb/isa_ref/run_qemu_system_mmu_process_pressure_gate.sh

qemu-system-mmu-refill-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_refill_differential_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_mmu_refill_differential \
		tb/isa_ref/run_qemu_system_mmu_refill_differential_gate.sh

qemu-system-mmu-os-pressure-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_refill_differential_gate.sh
	OS_PRESSURE=1 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_mmu_os_pressure \
		tb/isa_ref/run_qemu_system_mmu_refill_differential_gate.sh

qemu-system-mmu-ipi-contract-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_ipi_contract_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_mmu_ipi_contract \
		tb/isa_ref/run_qemu_system_mmu_ipi_contract_gate.sh

qemu-system-gpio-input-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_gpio_input_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_gpio_input \
		tb/isa_ref/run_qemu_system_gpio_input_gate.sh

qemu-system-ddr-fault-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_ddr_fault_gate.sh
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_ddr_fault \
		tb/isa_ref/run_qemu_system_ddr_fault_gate.sh

qemu-system-mmu-pagemask-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_mmu_pagemask_differential_gate.sh
	tb/isa_ref/run_qemu_system_mmu_pagemask_differential_gate.sh

perf-counters-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/perf_counters tb/unit/cpu_test/run_perf_counters.sh

perf-cpu-gate:
	$(MAKE) -C tb/soc_test/fw/tests/perf_cpu OUT_DIR=$(PERF_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(PERF_CPU_FW_HEX) RUN_DIR=$(BUILD_DIR)/soc_test/perf_cpu \
	VCS_EXTRA_ARGS='+define+SOC_PERF_COUNTERS=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh
	grep -q 'perf_cpu: REGRESSION_TEST_SUCCESS' $(BUILD_DIR)/soc_test/perf_cpu/sim.log
	@echo "CPU performance counter SoC gate: PASS"

perf-workloads-gate:
	$(MAKE) -C tb/soc_test/fw/tests/perf_workloads OUT_DIR=$(PERF_WORKLOADS_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(PERF_WORKLOADS_FW_HEX) RUN_DIR=$(BUILD_DIR)/soc_test/perf_workloads \
	VCS_EXTRA_ARGS='+define+SOC_PERF_COUNTERS=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh
	grep -q 'perf_workloads: REGRESSION_TEST_SUCCESS' $(BUILD_DIR)/soc_test/perf_workloads/sim.log
	@test "$$(grep -c 'perf_workloads: .* cycles=' $(BUILD_DIR)/soc_test/perf_workloads/sim.log)" -eq 4
	@echo "CPU performance workload observation gate: PASS"

vic-nested-gate:
	$(MAKE) -C tb/soc_test/fw/tests/vic_nested OUT_DIR=$(VIC_NESTED_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(VIC_NESTED_FW_HEX) RUN_DIR=$(BUILD_DIR)/soc_test/vic_nested \
	VCS_EXTRA_ARGS='+define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh
	grep -q 'vic_nested: REGRESSION_TEST_SUCCESS' $(BUILD_DIR)/soc_test/vic_nested/sim.log
	@echo "VIC nested interrupt SoC gate: PASS"

vic-full-sources-gate:
	chmod +x tb/soc_test/run_vic_full_sources_gate.sh
	RUN_DIR=$(BUILD_DIR)/soc_test/vic_full_sources \
		tb/soc_test/run_vic_full_sources_gate.sh

rtl-frontend-compile:
	RUN_ROOT=$(BUILD_DIR)/unit_tb/rtl_frontend_compile tb/unit/run_rtl_frontend_compile.sh

dut-block-unit-gate:
	RUN_ROOT=$(DUT_BLOCK_UNIT_DIR) tb/unit/run_dut_block_unit_gate.sh

fabric-unit-gate:
	RUN_ROOT=$(FABRIC_UNIT_DIR) tb/unit/run_fabric_unit_gate.sh

firmware:
	$(MAKE) -C tb/soc_test/fw OUT_DIR=$(FW_BUILD_DIR) FW_BASE=firmware all

srs-firmware:
	$(MAKE) -C tb/soc_test/fw/tests/srs OUT_DIR=$(SRS_FW_DIR) FW_BASE=firmware all

srs-gate: srs-firmware mips-control-srs-gate mips-regfile-srs-gate
	FW_HEX=$(SRS_FW_HEX) RUN_DIR=$(SOC_TEST_SRS_DIR) tb/soc_test/run_srs_gate.sh

srs-exception-firmware:
	$(MAKE) -C tb/soc_test/fw/tests/srs_exception OUT_DIR=$(SRS_EXCEPTION_FW_DIR) FW_BASE=firmware all

srs-exception-gate: srs-exception-firmware srs-gate
	FW_HEX=$(SRS_EXCEPTION_FW_HEX) RUN_DIR=$(SOC_TEST_SRS_EXCEPTION_DIR) tb/soc_test/run_srs_exception_gate.sh

srs-nested-firmware:
	$(MAKE) -C tb/soc_test/fw/tests/srs_nested OUT_DIR=$(SRS_NESTED_FW_DIR) FW_BASE=firmware all

srs-nested-gate: srs-nested-firmware srs-gate
	FW_DIR=$(SRS_NESTED_FW_DIR) RUN_DIR=$(SOC_TEST_SRS_NESTED_DIR) tb/soc_test/run_srs_nested_gate.sh

qemu-system-srs-exception-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=srs_exception QEMU_CPU=24Kc RTL_TIMEOUT=180 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_srs_exception_differential RTL_VCS_EXTRA_ARGS='+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-srs-nested-differential-gate: qemu-system-mips32-soc-ref
	FW_TEST=srs_nested QEMU_CPU=24Kc RTL_TIMEOUT=180 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_srs_nested_differential RTL_VCS_EXTRA_ARGS='+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' tb/isa_ref/run_qemu_system_differential_gate.sh

qemu-system-srs-map-differential-gate: qemu-system-mips32-soc-ref
	FW_TEST=qemu_system_srs_irq QEMU_CPU=24Kc RTL_TIMEOUT=180 RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_srs_map_differential RTL_VCS_EXTRA_ARGS='+define+SOC_SRS_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' tb/isa_ref/run_qemu_system_differential_gate.sh

srs-scheduler-context-gate:
	VCS_EXTRA_ARGS='+define+SOC_SRS_ENABLE=1 +define+SRS_CONTEXT_TEST' RUN_DIR=$(BUILD_DIR)/unit_tb/cpu_scheduler_srs tb/unit/cpu_test/run_cpu_scheduler_integration.sh

firmwares:
	$(MAKE) -C tb/soc_test/fw all-firmwares OUT_DIR=$(BUILD_DIR)/firmware

uvm:
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_FLASH_IMAGE) TESTNAME=$(UVM_TEST) SEED=$(UVM_SEED) RUN_DIR=$(UVM_RUN_DIR) L2_WRITEBACK=$(L2_WRITEBACK) tb/uvm_tb/run_uvm.sh

uvm-regression:
	FW_HEX=$(FW_HEX) TESTNAME=$(UVM_TEST) NUM_TESTS=$(NUM_TESTS) RUN_DIR=$(UVM_REG_DIR) tb/uvm_tb/run_regression.sh

uvm-directed-regression:
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_TESTLIST) RUN_DIR=$(UVM_DIRECTED_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

regression: firmware uvm-regression

phase2-regression: firmware uvm-directed-regression

phase2-complete: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_TESTLIST) RUN_ROOT=$(BUILD_DIR)/uvm/phase2_complete tb/uvm_tb/run_phase2_complete.sh

phase3-regression: firmware
	$(MAKE) -C tb/soc_test/fw all-firmwares OUT_DIR=$(BUILD_DIR)/firmware
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_PHASE3_FLASH_IMAGE) TESTLIST=$(UVM_PHASE3_TESTLIST) RUN_DIR=$(UVM_PHASE3_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3-complete: firmware
	$(MAKE) -C tb/soc_test/fw all-firmwares OUT_DIR=$(BUILD_DIR)/firmware
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_PHASE3_FLASH_IMAGE) TESTLIST=$(UVM_PHASE3_TESTLIST) RUN_ROOT=$(UVM_PHASE3_COMPLETE_DIR) L2_WRITEBACK=$(L2_WRITEBACK) tb/uvm_tb/run_phase3_complete.sh

phase3b-regression: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3B_TESTLIST) RUN_DIR=$(UVM_PHASE3B_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3b-complete: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3B_TESTLIST) RUN_ROOT=$(UVM_PHASE3B_COMPLETE_DIR) tb/uvm_tb/run_phase3b_complete.sh

phase3c-regression: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3C_TESTLIST) RUN_DIR=$(UVM_PHASE3C_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3c-complete: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3C_TESTLIST) RUN_ROOT=$(UVM_PHASE3C_COMPLETE_DIR) tb/uvm_tb/run_phase3c_complete.sh

current-contract-signoff: soc-filelist-audit rtl-frontend-compile firmware firmwares micro-tlb-gate product-mmu-micro-tlb-gate interrupt-priority-gate dcache-parity-gate verification-foundation-gate cache-concurrency-gate l1-nonblocking-gate l1-nonblocking-maintenance-compat-gate l1-nonblocking-cpu-error-gate l1-nonblocking-cpu-two-error-reset-gate sva-gate qspi-vendor-neutral-complete-gate qspi-vendor-neutral-boot-gate ddr-contract-entry-audit ecc-secded-gate ddr4-complete-gate
	FW_HEX=$(FW_HEX) FW_ROOT_DIR=$(BUILD_DIR)/firmware RUN_ROOT=$(SIGNOFF_DIR) NUM_TESTS=$(NUM_TESTS) SEED_BASE=$(SEED_BASE) tb/uvm_tb/run_current_contract_signoff.sh

soc-smoke: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(SOC_TEST_RUN_DIR) L2_WRITEBACK=$(L2_WRITEBACK) L2_NONBLOCKING=$(L2_NONBLOCKING) tb/soc_test/run.sh

cpu-cp0-gate: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(SOC_TEST_CPU_CP0_DIR) tb/soc_test/run_cpu_cp0_gate.sh

cpu-load-return-gate:
	tb/soc_test/run_cpu_load_return_gate.sh

cpu-mmu-complete:
	RUN_ROOT=$(BUILD_DIR)/cpu_mmu_complete tb/soc_test/run_cpu_mmu_complete.sh

mmu-refill-gate:
	RUN_DIR=$(MMU_REFILL_DIR) tb/soc_test/run_mmu_refill.sh

mmu-hardware-walker-soc-gate:
	HW_WALKER=1 RUN_DIR=$(BUILD_DIR)/soc_test/mmu_hardware_walker_soc tb/soc_test/run_mmu_refill.sh

# Current P1 is the verified RTL/simulation extension bundle. Full ISA
# compliance, FPU, coherency protocol evolution and OS boot remain separate
# contracts and are intentionally not hidden behind this aggregate gate.
p1-current-complete: rtl-frontend-compile dcache-coherency-gate coherency-stress-gate page-table-walker-gate page-table-tlb-refill-gate cpu-hardware-walker-gate cpu-dside-hardware-walker-gate mmu-hardware-walker-soc-gate mmu-page-table-allocator-gate cpu-scheduler-gate cpu-scheduler-integration-gate scheduler-timer-ipi-gate ecc-secded-gate product-vectored-interrupt-gate isa-r2-gate dual-core-frontend-compile dual-core-soc-gate cpu-mmu-complete product-mmu-pagemask-gate ddr4-complete-gate
	@mkdir -p $(P1_COMPLETE_DIR)
	@{ \
		echo '# P1 RTL/Simulation Extension Completion Report'; \
		echo; \
		echo '- Baseline commit: '`git rev-parse --short HEAD`; \
		echo '- Result: PASS'; \
		echo '- Scope: coherency v0.4 firmware stress, I/D and SoC hardware walker refill/retry plus permission matrix, bounded page-table root allocator, scheduler context, SoC 16KB PageMask, SECDED primitive, finite VEIC routing, ISA R2 implemented subset, strict coverage metadata hygiene, and existing P0 regressions'; \
		echo '- Excluded: full MESI/directory protocol, full ISA compliance/FPU, Linux/OS boot, and production software policy'; \
	} > $(P1_COMPLETE_DIR)/p1_completion_report.md
	@echo "P1 current RTL/simulation extension gate: PASS"

dual-core-frontend-compile:
	RUN_ROOT=$(BUILD_DIR)/dual_core_frontend tb/unit/run_dual_core_frontend_compile.sh

dual-core-soc-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/dual_core tb/soc_test/run_dual_core_gate.sh

dcache-coherency-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/dcache_coherency tb/unit/dcache/run_coherency.sh

cache-concurrency-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cache_concurrency tb/unit/cache/run_concurrency_gate.sh

soc-filelist-audit:
	bash tb/unit/run_soc_filelist_audit.sh

l1-nonblocking-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cache_concurrency/l1nb tb/unit/cache/run_l1_nb_gate.sh

l1-nonblocking-errors-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cache_concurrency/l1nb_errors tb/unit/cache/run_l1_nb_errors_gate.sh

l1-nonblocking-axi-bridge-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cache_concurrency/l1nb_axi_bridge tb/unit/cache/run_l1_nb_axi_bridge_gate.sh

l1-nonblocking-cpu-compat-gate: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_compat \
	VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1' tb/soc_test/run.sh

l1-nonblocking-cpu-multi-gate: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_multi \
	VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+TB_L1_NONBLOCKING +define+TB_SKIP_JTAG_RESET_STRESS' tb/soc_test/run.sh

l1-nonblocking-cpu-stress-gate: firmware
	FW_HEX=$(FW_HEX) RUN_ROOT=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_stress \
	SEEDS='11 29 47' tb/soc_test/run_l1_nonblocking_cpu_stress_gate.sh

l1-nonblocking-cpu-error-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_error \
	FW_DIR=$(BUILD_DIR)/firmware/l1_axi_error \
	tb/soc_test/run_l1_nonblocking_cpu_error_gate.sh

l1-nonblocking-cpu-two-error-gate:
	chmod +x tb/soc_test/run_l1_nonblocking_cpu_two_error_gate.sh
	RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_two_error \
	FW_DIR=$(BUILD_DIR)/firmware/l1_axi_error_two \
	tb/soc_test/run_l1_nonblocking_cpu_two_error_gate.sh

l1-nonblocking-cpu-error-reset-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_error_reset \
	FW_DIR=$(BUILD_DIR)/firmware/l1_axi_error \
	tb/soc_test/run_l1_nonblocking_cpu_error_reset_gate.sh

l1-nonblocking-cpu-two-error-reset-gate:
	RUN_DIR=$(BUILD_DIR)/soc_test/l1_nonblocking_cpu_two_error_reset \
	FW_DIR=$(BUILD_DIR)/firmware/l1_axi_error_two \
	tb/soc_test/run_l1_nonblocking_cpu_two_error_reset_gate.sh

l1-nonblocking-maintenance-compat-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cache_concurrency/l1nb_maintenance_compat \
	tb/unit/cache/run_l1_nb_maintenance_compat_gate.sh

l1-nonblocking-ddr-gate:
	chmod +x tb/soc_test/run_l1_ddr_nonblocking_gate.sh
	RUN_DIR=$(BUILD_DIR)/soc_test/l1_ddr_nonblocking \
	tb/soc_test/run_l1_ddr_nonblocking_gate.sh

qemu-system-l1-ddr-differential-gate: qemu-system-mips32-soc-ref
	chmod +x tb/isa_ref/run_qemu_system_differential_gate.sh
	FW_TEST=qemu_system_l1_ddr \
	RUN_DIR=$(BUILD_DIR)/isa_ref/qemu_system_l1_ddr_differential \
	RTL_TIMEOUT=180 \
	RTL_VCS_EXTRA_ARGS='+define+SOC_L1_NONBLOCKING_ENABLE=1 +define+SOC_CPU_NONBLOCKING_ENABLE=1 +define+SOC_ROB_FIFO_ENABLE=1 +define+SOC_L1_NONBLOCKING_DDR_ENABLE=1 +define+TB_SKIP_UART_PIN_CHECK' \
	tb/isa_ref/run_qemu_system_differential_gate.sh


fpu-double-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_double OUT_DIR=$(BUILD_DIR)/firmware/fpu_double FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_double FW_DIR=$(BUILD_DIR)/firmware/fpu_double \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_double/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
	tb/soc_test/run.sh

fpu-single-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_single OUT_DIR=$(BUILD_DIR)/firmware/fpu_single FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_single FW_DIR=$(BUILD_DIR)/firmware/fpu_single \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_single/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
	tb/soc_test/run.sh

fpu-cu1-exception-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_cu1_exception OUT_DIR=$(BUILD_DIR)/firmware/fpu_cu1_exception FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_cu1_exception FW_DIR=$(BUILD_DIR)/firmware/fpu_cu1_exception \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_cu1_exception/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS' \
	tb/soc_test/run.sh

fpu-fpe-exception-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_exception OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_exception FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_exception FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_exception \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_exception/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK +define+TB_FPU_FPE_DEBUG' \
	tb/soc_test/run.sh

fpu-fpe-double-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_double OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_double FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_double/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK +define+TB_FPU_FPE_DEBUG' \
	tb/soc_test/run.sh

fpu-fpe-inexact-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_inexact OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_inexact FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_inexact FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_inexact \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_inexact/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-fpe-double-inexact-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_double_inexact OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double_inexact FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_double_inexact FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double_inexact \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_double_inexact/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-fpe-double-underflow-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_double_underflow OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double_underflow FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_double_underflow FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_double_underflow \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_double_underflow/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-rounding-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_rounding OUT_DIR=$(BUILD_DIR)/firmware/fpu_rounding FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_rounding FW_DIR=$(BUILD_DIR)/firmware/fpu_rounding \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_rounding/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK +define+TB_FPU_ROUND_DEBUG' \
	tb/soc_test/run.sh

fpu-fpe-invalid-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_invalid OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_invalid FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_invalid FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_invalid \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_invalid/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-fpe-overflow-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_overflow OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_overflow FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_overflow FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_overflow \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_overflow/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

fpu-fpe-underflow-gate:
	$(MAKE) -C tb/soc_test/fw/tests/fpu_fpe_underflow OUT_DIR=$(BUILD_DIR)/firmware/fpu_fpe_underflow FW_BASE=firmware all
	RUN_DIR=$(BUILD_DIR)/soc_test/fpu_fpe_underflow FW_DIR=$(BUILD_DIR)/firmware/fpu_fpe_underflow \
	FW_HEX=$(BUILD_DIR)/firmware/fpu_fpe_underflow/firmware.hex \
	VCS_EXTRA_ARGS='+define+SOC_FPU_ENABLE=1 +define+TB_SKIP_JTAG_RESET_STRESS +define+TB_SKIP_UART_PIN_CHECK' \
	tb/soc_test/run.sh

rob-fifo-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cpu_test/rob_fifo tb/unit/cpu_test/run_rob_fifo.sh

coherency-stress-gate:
	RUN_DIR=$(COHERENCY_STRESS_DIR) FW_DIR=$(COHERENCY_STRESS_FW_DIR) tb/soc_test/run_coherency_stress_gate.sh

page-table-walker-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/page_table_walker tb/unit/mmu/run_page_table_walker.sh

page-table-walker-page-sizes-gate:
	@set -e; \
	for spec in "4K:" "16K:WALKER_16K" "64K:WALKER_64K" "256K:WALKER_256K"; do \
		name=$${spec%%:*}; define=$${spec#*:}; \
		dir=$(BUILD_DIR)/unit_tb/page_table_walker_pages/$${name}; \
		if [ -n "$${define}" ]; then VCS_DEFINES="+define+$${define}" RUN_DIR="$${dir}" tb/unit/mmu/run_page_table_walker.sh; \
		else RUN_DIR="$${dir}" tb/unit/mmu/run_page_table_walker.sh; fi; \
	done

page-table-tlb-refill-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/page_table_tlb_refill tb/unit/mmu/run_page_table_tlb_refill.sh

cpu-hardware-walker-gate:
	RUN_DIR=$(CPU_HARDWARE_WALKER_DIR) tb/unit/mmu/run_cpu_hardware_walker.sh

cpu-hardware-walker-page-size-gate:
	VCS_DEFINES="+define+SOC_HARDWARE_WALKER_PAGE_MASK=16'h0003" \
	RUN_DIR=$(BUILD_DIR)/unit_tb/cpu_hardware_walker_16k \
	tb/unit/mmu/run_cpu_hardware_walker.sh

cpu-hardware-walker-page-sizes-gate:
	@set -e; \
	for spec in "16K:16'h0003" "64K:16'h000f" "256K:16'h003f"; do \
		name=$${spec%%:*}; mask=$${spec#*:}; \
		VCS_DEFINES="+define+SOC_HARDWARE_WALKER_PAGE_MASK=$${mask}" \
		RUN_DIR=$(BUILD_DIR)/unit_tb/cpu_hardware_walker_$${name} \
		tb/unit/mmu/run_cpu_hardware_walker.sh; \
	done

cpu-dside-hardware-walker-gate:
	RUN_DIR=$(CPU_DSIDE_HARDWARE_WALKER_DIR) tb/unit/mmu/run_cpu_dside_hardware_walker.sh

coverage-strict-clean-gate:
	tb/coverage/run_strict_clean_gate.sh

mmu-page-table-allocator-gate:
	RUN_DIR=$(MMU_PAGE_TABLE_ALLOCATOR_DIR) tb/unit/tlb/run_mmu_page_table_allocator.sh

cpu-scheduler-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/cpu_scheduler tb/unit/cpu_test/run_cpu_scheduler.sh

cpu-scheduler-integration-gate:
	RUN_DIR=$(CPU_SCHEDULER_INTEGRATION_DIR) tb/unit/cpu_test/run_cpu_scheduler_integration.sh

llsc-interrupt-boundary-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/llsc_interrupt_boundary \
	VCS_EXTRA_ARGS='+define+LL_INTERRUPT_BOUNDARY_TEST' \
	tb/unit/cpu_test/run_cpu_scheduler_integration.sh

fpu-context-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/fpu_context tb/unit/cpu_test/run_cpu_scheduler_integration.sh

scheduler-timer-ipi-gate:
	RUN_DIR=$(BUILD_DIR)/unit_tb/scheduler_timer_ipi tb/unit/cpu_test/run_scheduler_timer_ipi.sh

cp0-rdhwr-gate:
	RUN_DIR=$(abspath $(CP0_RDHWR_DIR)) FW_DIR=$(abspath $(CP0_RDHWR_FW_DIR)) tb/soc_test/run_cp0_rdhwr_gate.sh

soc-random-regression:
	RUN_DIR=$(SOC_TEST_RANDOM_DIR) NUM_TESTS=$(NUM_TESTS) python3 tb/soc_test/run_regression.py

stage-sim:
	$(MAKE) -C sim STAGE=$(STAGE) BUILD_DIR=$(BUILD_DIR) all

project-tree:
	@echo "Source directories:"
	@find rtl tb docs sim .agents \( -path '*/csrc' -o -path '*/simv.daidir' -o -path '*.vdb' -o -path '*/coverage_report' -o -path '*/soc_cov_report' -o -path '*/textReport*' -o -path '*/__pycache__' \) -prune -o -type d -print | sort
	@echo
	@echo "Generated build directories:"
	@if [ -d "$(BUILD_DIR)" ]; then find "$(BUILD_DIR)" -maxdepth 4 \( -path '*/csrc/*' -o -path '*/simv.daidir/*' -o -path '*.vdb/*' -o -path '*/urgReport/*' \) -prune -o -type d -print | sort; else echo "$(BUILD_DIR) does not exist"; fi

clean-firmware:
	$(MAKE) -C tb/soc_test/fw OUT_DIR=$(FW_BUILD_DIR) FW_BASE=firmware clean

clean-build:
	rm -rf $(BUILD_DIR)

clean-legacy-artifacts:
	rm -rf sim/simv sim/simv.daidir sim/csrc sim/cov_dir.vdb sim/cov_html sim/urgReport
	rm -rf sim/compile.log sim/sim.log sim/novas.fsdb sim/novas.conf sim/verdiLog sim/ucli.key sim/vc_hdrs.h sim/firmware.hex sim/.fsm.sch.verilog.xml
	rm -rf tb/soc_test/simv tb/soc_test/simv.daidir tb/soc_test/csrc tb/soc_test/simv.vdb
	rm -rf tb/soc_test/coverage_report tb/soc_test/soc_cov_report tb/soc_test/textReport tb/soc_test/textReportExclude tb/soc_test/textReportExclude4 tb/soc_test/textReportExclude5 tb/soc_test/textReportFinal
	rm -rf tb/soc_test/vcs.log tb/soc_test/sim.log tb/soc_test/cm.log tb/soc_test/ucli.key tb/soc_test/firmware.hex tb/soc_test/.fsm.sch.verilog.xml
	rm -rf tb/soc_test/fw/firmware.elf tb/soc_test/fw/firmware.bin tb/soc_test/fw/firmware.hex tb/soc_test/fw/firmware.map tb/soc_test/fw/firmware.objdump tb/soc_test/fw/firmware.manifest tb/soc_test/fw/rand_test.s
	rm -rf tb/soc_test/__pycache__

clean: clean-build
