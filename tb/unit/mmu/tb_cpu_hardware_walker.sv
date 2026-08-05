`timescale 1ns/1ps
module tb_cpu_hardware_walker;
  reg clk=0, rst_n=0;
  wire ptw_mem_valid;
  wire [31:0] ptw_mem_addr;
  wire ptw_fault_valid;
  wire [2:0] ptw_fault_code;
  integer errors=0, reads=0, cycles=0;
  always #5 clk=~clk;

  wire [31:0] zero32 = 32'd0;
  wire [31:0] ptw_rdata = (ptw_mem_addr == 32'h0000_1000) ? 32'h0000_2003 :
                           (ptw_mem_addr == 32'h0000_2000) ? 32'h0000_3007 : 32'd0;

  always @(posedge clk) if (ptw_mem_valid) reads = reads + 1;
  mips_cpu u_cpu (
    .clk(clk), .rst_n(rst_n), .inst_addr_ok(1'b1), .inst_data_ok(1'b1),
    .inst_bus_error(1'b0), .inst_cache_error(1'b0), .inst_rdata(zero32),
    .data_addr_ok(1'b1), .data_data_ok(1'b0), .data_bus_error(1'b0),
    .data_cache_error(1'b0), .data_cache_tag_rdata(zero32),
    .data_rdata(zero32), .data_cache_op_done(1'b0),
    .data_cache_op_error(1'b0), .ext_int(6'd0), .tlb_inv_en(1'b0),
    .tlb_inv_vpn2(19'd0), .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0),
    .tlb_inv_wired_floor(6'd0), .sim_exception_req(1'b0),
    .sim_exception_code(5'd0), .coh_snoop_valid(1'b0),
    .coh_snoop_addr(32'd0), .ctx_save_req(1'b0), .ctx_restore_req(1'b0),
    .ctx_restore_pc(32'd0), .ctx_restore_status(32'd0),
    .ctx_restore_asid(8'd0), .ctx_restore_gpr(1024'd0),
    .hardware_walker_enable(1'b1), .hardware_walker_ptbr(32'h0000_1000),
    .ptw_mem_valid(ptw_mem_valid), .ptw_mem_addr(ptw_mem_addr),
    .ptw_mem_ready(1'b1), .ptw_mem_rdata(ptw_rdata), .ptw_mem_error(1'b0),
    .ptw_fault_valid(ptw_fault_valid), .ptw_fault_code(ptw_fault_code)
  );

  initial begin
    repeat (3) @(posedge clk);
    rst_n=1'b1;
    while ((reads < 2 || u_cpu.inst_addr[31:12] !== 20'h00003) && cycles < 200) begin
      @(posedge clk); cycles=cycles+1;
    end
    #1;
    if (reads != 2) errors = errors + 1;
    if (u_cpu.inst_addr[31:12] !== 20'h00003) errors = errors + 1;
    if (ptw_fault_valid || ptw_fault_code !== 3'd0) errors = errors + 1;
    if (u_cpu.u_mips_cp0.cp0_status[1]) errors = errors + 1;
    if (errors == 0) $display("REGRESSION_TEST_SUCCESS cpu_hardware_walker");
    else $display("REGRESSION_TEST_FAILED cpu_hardware_walker errors=%0d reads=%0d addr=%h", errors, reads, u_cpu.inst_addr);
    $finish;
  end
endmodule
