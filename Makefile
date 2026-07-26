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

.PHONY: firmware firmwares uvm uvm-regression uvm-directed-regression regression phase2-regression phase2-complete phase3-regression phase3-complete phase3b-regression phase3b-complete phase3c-regression phase3c-complete current-contract-signoff soc-smoke cpu-cp0-gate soc-random-regression stage-sim project-tree clean-firmware clean-build clean-legacy-artifacts clean

firmware:
	$(MAKE) -C tb/soc_test/fw OUT_DIR=$(FW_BUILD_DIR) FW_BASE=firmware all

firmwares:
	$(MAKE) -C tb/soc_test/fw all-firmwares OUT_DIR=$(BUILD_DIR)/firmware

uvm:
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_FLASH_IMAGE) TESTNAME=$(UVM_TEST) SEED=$(UVM_SEED) RUN_DIR=$(UVM_RUN_DIR) tb/uvm_tb/run_uvm.sh

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
	FW_HEX=$(FW_HEX) FLASH_IMAGE=$(UVM_PHASE3_FLASH_IMAGE) TESTLIST=$(UVM_PHASE3_TESTLIST) RUN_ROOT=$(UVM_PHASE3_COMPLETE_DIR) tb/uvm_tb/run_phase3_complete.sh

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
	FW_HEX=$(FW_HEX) RUN_DIR=$(SOC_TEST_RUN_DIR) tb/soc_test/run.sh

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
