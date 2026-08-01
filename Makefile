ROOT_DIR := $(CURDIR)
BUILD_DIR ?= $(ROOT_DIR)/build
FW_NAME ?= soc_smoke
FW_BUILD_DIR ?= $(BUILD_DIR)/firmware/$(FW_NAME)
FW_HEX ?= $(FW_BUILD_DIR)/firmware.hex
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
SOC_TEST_RANDOM_DIR ?= $(BUILD_DIR)/soc_test/random_regression
SIGNOFF_DIR ?= $(BUILD_DIR)/signoff/current_contract
STAGE ?= ex
NUM_TESTS ?= 10
SEED_BASE ?= 1
DUT_BLOCK_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/dut_block_readiness
PRODUCT_MMU_BOOT_DIR ?= $(BUILD_DIR)/unit_tb/product_mmu_boot
PRODUCT_MMU_EBASE_MODIFIED_DIR ?= $(BUILD_DIR)/unit_tb/product_mmu_ebase_modified
PRODUCT_VECTORED_INTERRUPT_DIR ?= $(BUILD_DIR)/unit_tb/product_vectored_interrupt
SPI_FLASH_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/axi_spi_flash
XIP_READ_TIMEOUT_UNIT_DIR ?= $(BUILD_DIR)/unit_tb/axi_read_timeout_guard
PRODUCT_MANIFEST_HANDOFF_DIR ?= $(BUILD_DIR)/unit_tb/product_manifest_handoff
TLB_ASID_POLICY_DIR ?= $(BUILD_DIR)/unit_tb/tlb_asid_policy
PRODUCT_KSEG0_RUNTIME_DIR ?= $(BUILD_DIR)/unit_tb/product_kseg0_runtime

SOC_TEST_MDU_CPU_DIR ?= $(BUILD_DIR)/soc_test/mdu_cpu_gate
MDU_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/mdu_cpu
MDU_CPU_FW_HEX ?= $(MDU_CPU_FW_DIR)/firmware.hex

SOC_TEST_DMA_CPU_DIR ?= $(BUILD_DIR)/soc_test/dma_cpu_gate
DMA_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/dma_cpu
DMA_CPU_FW_HEX ?= $(DMA_CPU_FW_DIR)/firmware.hex

SOC_TEST_VIC_CPU_DIR ?= $(BUILD_DIR)/soc_test/vic_cpu_gate
VIC_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/vic_cpu
VIC_CPU_FW_HEX ?= $(VIC_CPU_FW_DIR)/firmware.hex

SOC_TEST_UART_CPU_DIR ?= $(BUILD_DIR)/soc_test/uart_cpu_gate
UART_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/uart_cpu
UART_CPU_FW_HEX ?= $(UART_CPU_FW_DIR)/firmware.hex

SOC_TEST_L2_CPU_DIR ?= $(BUILD_DIR)/soc_test/l2_cpu_gate
L2_CPU_FW_DIR ?= $(BUILD_DIR)/firmware/l2_cpu
L2_CPU_FW_HEX ?= $(L2_CPU_FW_DIR)/firmware.hex

.PHONY: firmware firmwares uvm uvm-regression uvm-directed-regression regression phase2-regression phase2-complete phase3-regression phase3-complete phase3b-regression phase3b-complete phase3c-regression phase3c-complete current-contract-signoff soc-smoke cpu-cp0-gate mdu-cpu-gate dma-cpu-gate vic-cpu-gate uart-cpu-gate l2-cpu-gate product-mmu-boot-gate product-mmu-ebase-modified-gate product-vectored-interrupt-gate spi-flash-unit-gate xip-read-timeout-unit-gate product-manifest-handoff-gate product-kseg0-runtime-gate tlb-asid-policy-gate soc-random-regression stage-sim dut-block-unit-gate project-tree clean-firmware clean-build clean-legacy-artifacts clean

mdu-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=mdu_cpu OUT_DIR=$(MDU_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(MDU_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_MDU_CPU_DIR) tb/soc_test/run_mdu_cpu_gate.sh

dma-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=dma_cpu OUT_DIR=$(DMA_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(DMA_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_DMA_CPU_DIR) tb/soc_test/run_dma_cpu_gate.sh

vic-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=vic_cpu OUT_DIR=$(VIC_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(VIC_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_VIC_CPU_DIR) tb/soc_test/run_vic_cpu_gate.sh

uart-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=uart_cpu OUT_DIR=$(UART_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(UART_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_UART_CPU_DIR) tb/soc_test/run_uart_cpu_gate.sh

l2-cpu-gate:
	$(MAKE) -C tb/soc_test/fw FW_NAME=l2_cpu OUT_DIR=$(L2_CPU_FW_DIR) FW_BASE=firmware all
	FW_HEX=$(L2_CPU_FW_HEX) RUN_DIR=$(SOC_TEST_L2_CPU_DIR) tb/soc_test/run_l2_cpu_gate.sh

product-mmu-boot-gate:
	RUN_DIR=$(PRODUCT_MMU_BOOT_DIR) tb/unit/bootrom/run_product_mmu_boot.sh

product-mmu-ebase-modified-gate:
	RUN_DIR=$(PRODUCT_MMU_EBASE_MODIFIED_DIR) tb/unit/bootrom/run_product_mmu_ebase_modified.sh

product-vectored-interrupt-gate:
	RUN_DIR=$(PRODUCT_VECTORED_INTERRUPT_DIR) tb/unit/bootrom/run_product_vectored_interrupt.sh

spi-flash-unit-gate:
	RUN_DIR=$(SPI_FLASH_UNIT_DIR) tb/unit/flash/run_axi_spi_flash.sh

xip-read-timeout-unit-gate:
	RUN_DIR=$(XIP_READ_TIMEOUT_UNIT_DIR) tb/unit/flash/run_axi_read_timeout_guard.sh

product-manifest-handoff-gate:
	RUN_DIR=$(PRODUCT_MANIFEST_HANDOFF_DIR) tb/unit/bootrom/run_product_manifest_handoff.sh

product-kseg0-runtime-gate:
	SOC_MMU_ENABLE=1 RUN_DIR=$(PRODUCT_KSEG0_RUNTIME_DIR) tb/unit/bootrom/run_product_manifest_handoff.sh

tlb-asid-policy-gate:
	RUN_DIR=$(TLB_ASID_POLICY_DIR) tb/unit/tlb/run_tlb_asid_policy.sh

dut-block-unit-gate:
	RUN_ROOT=$(DUT_BLOCK_UNIT_DIR) tb/unit/run_dut_block_unit_gate.sh

fabric-unit-gate:
	RUN_ROOT=$(BUILD_DIR)/unit_tb/fabric tb/unit/run_fabric_unit_gate.sh

firmware:
	$(MAKE) -C tb/soc_test/fw OUT_DIR=$(FW_BUILD_DIR) FW_BASE=firmware all

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
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_PHASE3_FLASH_IMAGE) TESTLIST=$(UVM_PHASE3_TESTLIST) RUN_DIR=$(UVM_PHASE3_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3-complete: firmware
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_PHASE3_FLASH_IMAGE) TESTLIST=$(UVM_PHASE3_TESTLIST) RUN_ROOT=$(UVM_PHASE3_COMPLETE_DIR) L2_WRITEBACK=$(L2_WRITEBACK) tb/uvm_tb/run_phase3_complete.sh

phase3b-regression: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3B_TESTLIST) RUN_DIR=$(UVM_PHASE3B_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3b-complete: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3B_TESTLIST) RUN_ROOT=$(UVM_PHASE3B_COMPLETE_DIR) tb/uvm_tb/run_phase3b_complete.sh

phase3c-regression: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3C_TESTLIST) RUN_DIR=$(UVM_PHASE3C_DIR) ENABLE_COV=$(UVM_ENABLE_COV) tb/uvm_tb/run_testlist.sh

phase3c-complete: firmware
	FW_HEX=$(FW_HEX) TESTLIST=$(UVM_PHASE3C_TESTLIST) RUN_ROOT=$(UVM_PHASE3C_COMPLETE_DIR) tb/uvm_tb/run_phase3c_complete.sh

current-contract-signoff: firmware firmwares
	FW_HEX=$(FW_HEX) FW_ROOT_DIR=$(BUILD_DIR)/firmware RUN_ROOT=$(SIGNOFF_DIR) NUM_TESTS=$(NUM_TESTS) SEED_BASE=$(SEED_BASE) tb/uvm_tb/run_current_contract_signoff.sh

soc-smoke: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(SOC_TEST_RUN_DIR) L2_WRITEBACK=$(L2_WRITEBACK) L2_NONBLOCKING=$(L2_NONBLOCKING) tb/soc_test/run.sh

cpu-cp0-gate: firmware
	FW_HEX=$(FW_HEX) RUN_DIR=$(SOC_TEST_CPU_CP0_DIR) tb/soc_test/run_cpu_cp0_gate.sh

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
