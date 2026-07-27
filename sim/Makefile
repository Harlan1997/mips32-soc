# =============================================================================
# File Name: Makefile
# Design:    MIPS32 Stage Verification Simulation Makefile
# Author:    Antigravity
# Description:
#   Makefile for compiling, simulating, and debugging block-level verification
#   environments using VCS and Verdi. Supports EX, ID, and IF stages.
# =============================================================================

# Tool environment initialization wrapper
ENV_LOAD = export PATH=/home/admin/.local/bin:$$PATH MODULES_PAGER=cat PAGER=cat TERM=dumb && . /etc/profile.d/modules.sh && module use /tool/module && module load vcs verdi

VERDI_HOME ?= /data/disk/verdi/verdi/X-2025.06-SP1

# Directories
ROOT_DIR := $(abspath ..)
BUILD_DIR ?= $(ROOT_DIR)/build
RUN_DIR ?= $(BUILD_DIR)/stage/$(STAGE)
RTL_DIR = $(ROOT_DIR)/rtl/cpu

# Select Stage: ex, id, or if
STAGE ?= ex

ifeq ($(STAGE), ex)
    RTL_FILES = $(RTL_DIR)/mips_alu.v \
                $(RTL_DIR)/mips_mdu.v \
                $(RTL_DIR)/mips_ex_stage.v
    TB_DIR    = $(ROOT_DIR)/tb/ex_stage
    TB_FILES  = $(TB_DIR)/mips_ex_stage_if.sv \
                $(TB_DIR)/mips_ex_stage_pkg.sv \
                $(TB_DIR)/mips_ex_stage_tb_top.sv
    TEST      = mixed_test
else ifeq ($(STAGE), id)
    RTL_FILES = $(RTL_DIR)/mips_regfile.v \
                $(RTL_DIR)/mips_control.v \
                $(RTL_DIR)/mips_id_stage.v
    TB_DIR    = $(ROOT_DIR)/tb/id_stage
    TB_FILES  = $(TB_DIR)/mips_id_stage_if.sv \
                $(TB_DIR)/mips_id_stage_pkg.sv \
                $(TB_DIR)/mips_id_stage_tb_top.sv
    TEST      = id_test
else ifeq ($(STAGE), if)
    RTL_FILES = $(RTL_DIR)/mips_if_stage.v
    TB_DIR    = $(ROOT_DIR)/tb/if_stage
    TB_FILES  = $(TB_DIR)/mips_if_stage_if.sv \
                $(TB_DIR)/mips_if_stage_pkg.sv \
                $(TB_DIR)/mips_if_stage_tb_top.sv
    TEST      = if_test
else ifeq ($(STAGE), mem)
    RTL_FILES = $(RTL_DIR)/mips_mem_stage.v
    TB_DIR    = $(ROOT_DIR)/tb/mem_stage
    TB_FILES  = $(TB_DIR)/mips_mem_stage_if.sv \
                $(TB_DIR)/mips_mem_stage_pkg.sv \
                $(TB_DIR)/mips_mem_stage_tb_top.sv
    TEST      = mem_test
endif

# Compiler & Simulator Options
VCS_OPTS = -full64 \
           -sverilog \
           -ntb_opts uvm-1.2 \
           -timescale=1ns/1ps \
           -debug_access+all \
           -kdb \
           -P $(VERDI_HOME)/share/PLI/VCS/linux64/novas.tab $(VERDI_HOME)/share/PLI/VCS/linux64/pli.a \
           -l compile.log \
           +incdir+$(TB_DIR)

SIM_OPTS = +UVM_NO_RELNOTES \
           +UVM_VERBOSITY=UVM_LOW \
           +DUMP_FSDB \
           -l sim.log

# Coverage Options
COV_OPTS = -cm line+cond+fsm+tgl+branch -cm_dir ./cov_dir

.PHONY: all compile sim cov verdi clean

all: compile sim

compile:
	mkdir -p $(RUN_DIR)
	cd $(RUN_DIR) && $(ENV_LOAD) && vcs $(VCS_OPTS) $(COV_OPTS) $(RTL_FILES) $(TB_FILES)

sim:
	cd $(RUN_DIR) && $(ENV_LOAD) && ./simv $(SIM_OPTS) $(COV_OPTS) +UVM_TESTNAME=$(TEST)

cov:
	cd $(RUN_DIR) && $(ENV_LOAD) && urg -dir ./cov_dir.vdb -format both -report cov_html
	@echo "Coverage report generated in: $(RUN_DIR)/cov_html/dashboard.html"

verdi:
	cd $(RUN_DIR) && $(ENV_LOAD) && verdi -dbdir ./simv.daidir -ssf novas.fsdb &

clean:
	rm -rf $(RUN_DIR)
