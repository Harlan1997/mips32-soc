`timescale 1ns/1ps
module tb_cpu_scheduler_integration;
  reg clk=0, rst_n=0, yield_req=0;
  wire save_req, save_done, restore_req, restore_ack;
  wire [7:0] save_task, restore_task;
  wire [31:0] save_pc, save_status, restore_pc, restore_status;
  wire [7:0] save_asid, restore_asid;
  wire [1023:0] save_gpr, restore_gpr;
  wire [31:0] save_sp = save_gpr[29*32 +: 32];
  integer errors=0, cycles=0;

  always #5 clk = ~clk;

  cpu_scheduler u_sched (
    .clk(clk), .rst_n(rst_n), .enable(1'b1), .timer_tick(1'b0),
    .ipi_resched(1'b0), .yield_req(yield_req), .active_mask(4'b0011),
    .resched_ack(), .scheduler_busy(), .current_task(),
    .switch_valid(), .switch_from(), .switch_to(),
    .ctx_save_req(save_req), .ctx_save_task(save_task),
    .ctx_save_done(save_done), .ctx_save_pc(save_pc), .ctx_save_sp(save_sp),
    .ctx_save_status(save_status), .ctx_save_asid(save_asid),
    .ctx_save_gpr(save_gpr), .ctx_restore_req(restore_req),
    .ctx_restore_task(restore_task), .ctx_restore_ack(restore_ack),
    .ctx_restore_pc(restore_pc), .ctx_restore_sp(),
    .ctx_restore_status(restore_status), .ctx_restore_asid(restore_asid),
    .ctx_restore_gpr(restore_gpr)
  );

  wire [31:0] inst_rdata = 32'd0;
  wire [31:0] data_rdata = 32'd0;
  wire [31:0] data_tag_rdata = 32'd0;
  wire [31:0] ptw_rdata = 32'd0;

  mips_cpu u_cpu (
    .clk(clk), .rst_n(rst_n), .inst_addr_ok(1'b1), .inst_data_ok(1'b1),
    .inst_bus_error(1'b0), .inst_cache_error(1'b0), .inst_rdata(inst_rdata),
    .data_addr_ok(1'b1), .data_data_ok(1'b0), .data_bus_error(1'b0),
    .data_cache_error(1'b0), .data_cache_tag_rdata(data_tag_rdata),
    .data_rdata(data_rdata), .data_cache_op_done(1'b0),
    .data_cache_op_error(1'b0), .ext_int(6'd0), .tlb_inv_en(1'b0),
    .tlb_inv_vpn2(19'd0), .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0),
    .tlb_inv_wired_floor(6'd0), .sim_exception_req(1'b0),
    .sim_exception_code(5'd0), .coh_snoop_valid(1'b0),
    .coh_snoop_addr(32'd0), .ctx_save_req(save_req),
    .ctx_save_done(save_done), .ctx_save_pc(save_pc),
    .ctx_save_status(save_status), .ctx_save_asid(save_asid),
    .ctx_save_gpr(save_gpr), .ctx_restore_req(restore_req),
    .ctx_restore_pc(restore_pc), .ctx_restore_status(restore_status),
    .ctx_restore_asid(restore_asid), .ctx_restore_gpr(restore_gpr),
    .ctx_restore_ack(restore_ack), .hardware_walker_enable(1'b0),
    .hardware_walker_ptbr(32'd0), .ptw_mem_ready(1'b0),
    .ptw_mem_rdata(ptw_rdata), .ptw_mem_error(1'b0)
  );

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    u_cpu.u_mips_id_stage.u_mips_regfile.regs[1] = 32'h1111_0001;
    u_sched.pc_bank[1] = 32'h0000_0200;
    u_sched.status_bank[1] = 32'h0000_0001;
    u_sched.asid_bank[1] = 8'h2a;
    u_sched.gpr_bank[1] = 1024'd0;
    u_sched.gpr_bank[1][32 +: 32] = 32'h2222_0002;
    yield_req = 1'b1;
    @(posedge clk);
    yield_req = 1'b0;
    while (!restore_req && cycles < 100) begin @(posedge clk); cycles=cycles+1; end
    if (!restore_req) errors = errors + 1;
    @(posedge clk);
    #1;
    if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[1] !== 32'h2222_0002) errors = errors + 1;
    if (restore_pc !== 32'h0000_0200) errors = errors + 1;
    if (u_cpu.u_mips_if_stage.pc !== 32'h0000_0200 &&
        u_cpu.u_mips_if_stage.pc !== 32'h0000_0204) errors = errors + 1;
    if (u_cpu.u_mips_cp0.cp0_entryhi_asid !== 8'h2a) errors = errors + 1;
    if (u_cpu.u_mips_cp0.cp0_status[0] !== 1'b1) errors = errors + 1;
    if (u_sched.gpr_bank[0][32 +: 32] !== 32'h1111_0001) errors = errors + 1;
    if (errors == 0) $display("REGRESSION_TEST_SUCCESS cpu_scheduler_integration");
    else $display("REGRESSION_TEST_FAILED cpu_scheduler_integration errors=%0d", errors);
    $finish;
  end
endmodule
