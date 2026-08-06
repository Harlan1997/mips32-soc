`timescale 1ns/1ps
`include "soc_config.vh"

module tb_cpu_dside_hardware_walker;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg [1:0] scenario = 2'd0;
  integer errors = 0;
  integer cycles = 0;
  integer ptw_i_requests = 0;
  integer ptw_d_requests = 0;
  integer data_requests = 0;
  integer data_writes = 0;
  integer fault_events = 0;
  reg [31:0] last_data_addr = 32'd0;
  reg [31:0] last_data_wdata = 32'd0;
  reg [3:0] last_data_be = 4'd0;

  always #5 clk = ~clk;

  wire [31:0] inst_addr;
  wire [31:0] data_addr;
  wire [31:0] data_wdata;
  wire [3:0] data_be;
  wire data_req;
  wire data_we;
  wire ptw_mem_valid;
  wire [31:0] ptw_mem_addr;
  wire ptw_fault_valid;
  wire [2:0] ptw_fault_code;

  function automatic [31:0] i_lui(input [4:0] rt, input [15:0] imm);
    i_lui = {6'h0f, 5'd0, rt, imm};
  endfunction
  function automatic [31:0] i_addiu(input [4:0] rs, input [4:0] rt, input [15:0] imm);
    i_addiu = {6'h09, rs, rt, imm};
  endfunction
  function automatic [31:0] i_lw(input [4:0] rs, input [4:0] rt, input [15:0] imm);
    i_lw = {6'h23, rs, rt, imm};
  endfunction
  function automatic [31:0] i_sw(input [4:0] rs, input [4:0] rt, input [15:0] imm);
    i_sw = {6'h2b, rs, rt, imm};
  endfunction

  function automatic [31:0] instruction_for(input [31:0] addr);
    begin
      case (addr)
        32'h0000_4000, 32'h0000_4004, 32'h0000_4008, 32'h0000_400c:
                                         instruction_for = i_addiu(5'd0, 5'd1, 16'h2000);
        32'h0000_4010, 32'h0000_4014, 32'h0000_4018:
                                         instruction_for = 32'd0;
        32'h0000_401c: instruction_for = (scenario == 2'd1) ?
                                         i_addiu(5'd0, 5'd2, 16'h1234) :
                                         i_lw(5'd1, 5'd2, 16'd0);
        32'h0000_4020, 32'h0000_4024, 32'h0000_4028:
                                         instruction_for = 32'd0;
        32'h0000_402c: instruction_for = (scenario == 2'd0) ?
                                         i_sw(5'd1, 5'd2, 16'd4) :
                                         (scenario == 2'd1) ?
                                         i_sw(5'd1, 5'd2, 16'd0) : 32'd0;
        default: instruction_for = 32'd0;
      endcase
    end
  endfunction

  wire [31:0] inst_rdata = instruction_for(inst_addr);
  wire [31:0] data_rdata = 32'hcafe_beef;
  wire data_complete = data_req &&
                        ((data_addr == 32'h0000_8000) ||
                         (data_addr == 32'h0000_8004));
  wire [31:0] ptw_rdata =
      (ptw_mem_addr == 32'h0000_1000) ? 32'h0000_2003 :
      (ptw_mem_addr == 32'h0000_2000) ? 32'h0000_4005 :
      (ptw_mem_addr == 32'h0000_2008) ?
          ((scenario == 2'd0) ? 32'h0000_8007 :
           (scenario == 2'd2) ? 32'h0000_8005 : 32'h0000_8001) :
      32'd0;

  mips_cpu u_cpu (
    .clk(clk), .rst_n(rst_n), .inst_addr(inst_addr),
    .inst_addr_ok(1'b1), .inst_data_ok(1'b1), .inst_bus_error(1'b0),
    .inst_cache_error(1'b0), .inst_rdata(inst_rdata),
    .data_addr(data_addr), .data_wdata(data_wdata), .data_be(data_be),
    .data_req(data_req), .data_we(data_we), .data_addr_ok(1'b1),
    .data_data_ok(data_complete), .data_bus_error(1'b0), .data_cache_error(1'b0),
    .data_cache_tag_rdata(32'd0), .data_rdata(data_rdata),
    .data_cache_op_done(1'b0), .data_cache_op_error(1'b0),
    .ext_int(6'd0), .tlb_inv_en(1'b0), .tlb_inv_vpn2(19'd0),
    .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0), .tlb_inv_wired_floor(6'd0),
    .sim_exception_req(1'b0), .sim_exception_code(5'd0),
    .coh_snoop_valid(1'b0), .coh_snoop_addr(32'd0),
    .ctx_save_req(1'b0), .ctx_restore_req(1'b0), .ctx_restore_pc(32'd0),
    .ctx_restore_status(32'd0), .ctx_restore_asid(8'd0),
    .ctx_restore_gpr(1024'd0), .hardware_walker_enable(1'b1),
    .hardware_walker_ptbr(32'h0000_1000), .ptw_mem_valid(ptw_mem_valid),
    .ptw_mem_addr(ptw_mem_addr), .ptw_mem_ready(1'b1),
    .ptw_mem_rdata(ptw_rdata), .ptw_mem_error(1'b0),
    .ptw_fault_valid(ptw_fault_valid), .ptw_fault_code(ptw_fault_code)
  );

  always @(posedge clk) begin
    if (rst_n) begin
      if (u_cpu.ptw_req_valid && u_cpu.ptw_req_ready &&
          u_cpu.ptw_req_access == 2'd0)
        ptw_i_requests = ptw_i_requests + 1;
      if (u_cpu.ptw_req_valid && u_cpu.ptw_req_ready &&
          u_cpu.ptw_req_access != 2'd0)
        ptw_d_requests = ptw_d_requests + 1;
      if (ptw_fault_valid) fault_events = fault_events + 1;
    end
  end

  always @(negedge clk) begin
    if (rst_n && data_complete) begin
      data_requests = data_requests + 1;
      last_data_addr = data_addr;
      last_data_wdata = data_wdata;
      last_data_be = data_be;
      if (data_we) data_writes = data_writes + 1;
    end
  end

  always @(data_req) begin
  end

  task automatic reset_counters;
    begin
      ptw_i_requests = 0; ptw_d_requests = 0; data_requests = 0;
      data_writes = 0; fault_events = 0; cycles = 0;
      last_data_addr = 0; last_data_wdata = 0; last_data_be = 0;
    end
  endtask

  task automatic run_case(input [1:0] selected, input integer expect_write,
                          input integer expect_fault);
    integer base_errors;
    begin
      scenario = selected;
      rst_n = 1'b0;
      reset_counters();
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      while (cycles < 240 && ((expect_fault && fault_events == 0) ||
             (!expect_fault && (data_requests == 0 ||
                                (expect_write && data_writes == 0))))) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      #1;
      base_errors = errors;
      if (ptw_i_requests != 1) errors = errors + 1;
      if (ptw_d_requests != 1) errors = errors + 1;
      if (expect_fault) begin
        if (fault_events != 1 || ptw_fault_code != 3'd2) errors = errors + 1;
        if (data_requests != 0 || data_writes != 0) errors = errors + 1;
      end else begin
        if (fault_events != 0 || data_requests != (expect_write ? 2 : 1)) errors = errors + 1;
        if (expect_write && (data_writes != 1 || last_data_addr != 32'h0000_8004 ||
                             last_data_wdata != 32'hcafe_beef || last_data_be != 4'hf))
          errors = errors + 1;
        if (!expect_write && last_data_addr != 32'h0000_8000) errors = errors + 1;
      end
      if (errors != base_errors)
        $display("DWalker case %0d failed: ireq=%0d dreq=%0d data=%0d writes=%0d faults=%0d code=%0d addr=%h",
                 selected, ptw_i_requests, ptw_d_requests, data_requests,
                 data_writes, fault_events, ptw_fault_code, last_data_addr);
    end
  endtask

  initial begin
    run_case(2'd0, 1, 0);
    run_case(2'd2, 0, 0);
    run_case(2'd1, 0, 1);
    if (errors == 0)
      $display("REGRESSION_TEST_SUCCESS cpu_dside_hardware_walker");
    else
      $display("REGRESSION_TEST_FAILED cpu_dside_hardware_walker errors=%0d", errors);
    $finish;
  end
endmodule
