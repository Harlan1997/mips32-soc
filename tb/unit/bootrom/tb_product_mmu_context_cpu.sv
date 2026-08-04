`timescale 1ns/1ps
`include "soc_config.vh"
module tb_product_mmu_context_cpu;
 reg clk=0,rst_n=0,tck=0,tms=1,tdi=0; wire tdo; wire spi_sclk,spi_cs_n,spi_mosi,uart_tx,uart_rts_n,uart_dtr_n; wire [31:0] gpio_pins; wire uart_rx=1,uart_cts_n=1,uart_dsr_n=1,uart_dcd_n=1,uart_ri_n=1,spi_miso=0; integer cycles=0; reg pass_seen=0, trace_seen=0;
 genvar i; generate for(i=0;i<32;i=i+1) begin: p pullup(gpio_pins[i]); end endgenerate
 mips_soc u_soc(.clk(clk),.rst_n(rst_n),.gpio_pins(gpio_pins),.uart_rx(uart_rx),.uart_tx(uart_tx),.uart_cts_n(uart_cts_n),.uart_rts_n(uart_rts_n),.uart_dsr_n(uart_dsr_n),.uart_dtr_n(uart_dtr_n),.uart_dcd_n(uart_dcd_n),.uart_ri_n(uart_ri_n),.spi_sclk(spi_sclk),.spi_cs_n(spi_cs_n),.spi_mosi(spi_mosi),.spi_miso(spi_miso),.tck(tck),.tms(tms),.tdi(tdi),.tdo(tdo));
 always #5 clk=~clk;
 always @(posedge clk) begin
   if(!rst_n) cycles=0; else begin cycles=cycles+1;
     if(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr==32'hC0009014) begin
       trace_seen=1; $display("CPU_CTX_TRACE va=%h uncached=%b awvalid=%b awaddr=%h apb_sel=%b apb_wr=%b",u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_uncacheable,u_soc.u_impl.u_core_subsystem.data_awvalid,u_soc.u_impl.u_core_subsystem.data_awaddr,u_soc.u_impl.u_peripheral_subsystem.mmu_context_sel,u_soc.u_impl.u_peripheral_subsystem.apb_pwrite);
     end
     if(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we && u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr==32'hA000FFFC) begin if(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata!==32'hDEADBEEF) $finish; pass_seen=1; end
     if(pass_seen && trace_seen) begin $display("REGRESSION_TEST_SUCCESS product_mmu_context_cpu"); $finish; end
     if(cycles>12000) begin $display("REGRESSION_TEST_FAILED product_mmu_context_cpu timeout trace=%b",trace_seen); $finish; end
   end
 end
 initial begin repeat(3) @(posedge clk); rst_n=1; end
endmodule
