export MODULES_PAGER=cat PAGER=cat TERM=dumb
. /etc/profile.d/modules.sh
module use /tool/module
module load vcs
vcs -full64 -sverilog -timescale=1ns/1ps -cm line+cond+fsm+branch+tgl +incdir+../../rtl/include +incdir+../../rtl/cpu \
+incdir+../../rtl/axi +incdir+../../rtl/perips ../../rtl/cpu/mips_alu.v ../../rtl/cpu/mips_control.v \
../../rtl/cpu/mips_core.v ../../rtl/cpu/mips_cp0.v ../../rtl/cpu/mips_cpu.v ../../rtl/cpu/mips_ex_mem_reg.v \
../../rtl/cpu/mips_ex_stage.v ../../rtl/cpu/mips_id_ex_reg.v ../../rtl/cpu/mips_id_stage.v \
../../rtl/cpu/mips_if_id_reg.v ../../rtl/cpu/mips_if_stage.v ../../rtl/cpu/mips_mdu.v \
../../rtl/cpu/mips_mem_stage.v ../../rtl/cpu/mips_mem_wb_reg.v ../../rtl/cpu/mips_regfile.v \
../../rtl/cpu/mips_wb_stage.v ../../rtl/axi/axi2apb_bridge.v ../../rtl/axi/axi_arbiter_2x1_full.v \
../../rtl/axi/axi_arbiter_2x1.v ../../rtl/axi/axi_decoder_1x3.v \
../../rtl/perips/apb_axi_dma.v ../../rtl/perips/apb_gpio.v ../../rtl/perips/apb_pic.v \
../../rtl/perips/apb_timer.v ../../rtl/perips/apb_uart.v ../../rtl/perips/axi_spi_flash.v \
../../rtl/perips/axi_sram.v ../../rtl/perips/axi_ddr_model.v ../../rtl/perips/jtag_debug_top.v ../../rtl/cache/dcache.v \
../../rtl/cache/icache.v ../../rtl/soc_fabric.v ../../rtl/mips_soc_impl.v ../../rtl/mips_soc.v ../../rtl/soc_top.v tb_mips_soc.v -l vcs.log
./simv -cm line+cond+fsm+branch+tgl -l sim.log
urg -dir simv.vdb -elfile exclude5.el -excl_bypass_checks -report textReportFinal -format text
