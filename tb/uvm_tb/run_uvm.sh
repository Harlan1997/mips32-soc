#!/bin/bash
source /etc/profile.d/modules.sh
module load vcs

echo "Copying firmware to UVM directory..."
cp ../soc_test/fw/firmware.hex .

echo "Compiling UVM Testbench with VCS..."
vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps -debug_access+all \
+incdir+../../rtl/cpu +incdir+../../rtl/axi +incdir+../../rtl/perips +incdir+../../rtl/cache \
+incdir+./agents +incdir+./env +incdir+./tests \
../../rtl/cpu/*.v ../../rtl/axi/*.v ../../rtl/perips/*.v ../../rtl/cache/*.v ../../rtl/mips_soc.v \
tb_top/tb_top.sv \
-l vcs_uvm.log

echo "Running UVM Simulation..."
./simv +UVM_TESTNAME=soc_bus_stress_test +ntb_random_seed=$SEED 2>&1 | tee vcs_uvm.log
