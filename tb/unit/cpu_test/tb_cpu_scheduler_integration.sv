`timescale 1ns/1ps
module tb_cpu_scheduler_integration;
  reg clk=0, rst_n=0, yield_req=0;
  reg [5:0] ext_int=6'd0;
  wire save_req, save_done, restore_req, restore_ack;
  wire [7:0] save_task, restore_task;
  wire [31:0] save_pc, save_status, restore_pc, restore_status;
  wire [7:0] save_asid, restore_asid;
  wire [31:0] save_srsctl, restore_srsctl;
  wire [1023:0] save_gpr, restore_gpr;
  wire [16383:0] save_srs_gpr, restore_srs_gpr;
  wire [1023:0] save_fpr, restore_fpr;
  wire [31:0] save_fcsr, restore_fcsr;
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
    .ctx_save_srsctl(save_srsctl), .ctx_save_srs_gpr(save_srs_gpr),
    .ctx_save_gpr(save_gpr), .ctx_save_fpr(save_fpr), .ctx_save_fcsr(save_fcsr),
    .ctx_restore_req(restore_req),
    .ctx_restore_task(restore_task), .ctx_restore_ack(restore_ack),
    .ctx_restore_pc(restore_pc), .ctx_restore_sp(),
    .ctx_restore_status(restore_status), .ctx_restore_asid(restore_asid),
    .ctx_restore_srsctl(restore_srsctl), .ctx_restore_srs_gpr(restore_srs_gpr),
    .ctx_restore_gpr(restore_gpr), .ctx_restore_fpr(restore_fpr),
    .ctx_restore_fcsr(restore_fcsr)
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
    .data_cache_op_error(1'b0), .ext_int(ext_int), .tlb_inv_en(1'b0),
    .tlb_inv_vpn2(19'd0), .tlb_inv_asid(8'd0), .tlb_inv_scope(2'd0),
    .tlb_inv_wired_floor(6'd0), .sim_exception_req(1'b0),
    .sim_exception_code(5'd0), .coh_snoop_valid(1'b0),
    .coh_snoop_addr(32'd0), .ctx_save_req(save_req),
    .ctx_save_done(save_done), .ctx_save_pc(save_pc),
    .ctx_save_status(save_status), .ctx_save_asid(save_asid),
    .ctx_save_srsctl(save_srsctl), .ctx_save_srs_gpr(save_srs_gpr),
    .ctx_save_gpr(save_gpr), .ctx_save_fpr(save_fpr), .ctx_save_fcsr(save_fcsr),
    .ctx_restore_req(restore_req),
    .ctx_restore_pc(restore_pc), .ctx_restore_status(restore_status),
    .ctx_restore_asid(restore_asid), .ctx_restore_srsctl(restore_srsctl),
    .ctx_restore_gpr(restore_gpr), .ctx_restore_srs_gpr(restore_srs_gpr),
    .ctx_restore_set(restore_srsctl[3:0]),
    .ctx_restore_fpr(restore_fpr), .ctx_restore_fcsr(restore_fcsr),
    .ctx_restore_ack(restore_ack), .hardware_walker_enable(1'b0),
    .hardware_walker_ptbr(32'd0), .ptw_mem_ready(1'b0),
    .ptw_mem_rdata(ptw_rdata), .ptw_mem_error(1'b0)
  );

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    u_cpu.u_mips_id_stage.u_mips_regfile.regs[1] = 32'h1111_0001;
`ifdef SRS_CONTEXT_TEST
    u_cpu.u_mips_id_stage.u_mips_regfile.regs[33] = 32'h1111_5001;
`endif
    u_cpu.fpr[1] = 32'h1111_f001;
    u_cpu.fpr[2] = 32'h1111_f002;
    u_cpu.fcsr = 32'h1111_fc01;
    u_cpu.ll_reservation_valid = 1'b1;
    u_cpu.ll_reservation_addr = 32'h0000_1200;

`ifdef LL_INTERRUPT_BOUNDARY_TEST
    // Exercise the real asynchronous interrupt acceptance path.  The CPU
    // must terminate a reservation when interrupt_accept drives the common
    // exception flush, before any handler/ERET activity can resume it.
    u_cpu.u_mips_cp0.cp0_status = 32'h0000_ff01; // IE + all external IM bits
    ext_int = 6'b000001;
    repeat (3) @(posedge clk);
    #1;
    if (u_cpu.ll_reservation_valid !== 1'b0) errors = errors + 1;
    ext_int = 6'd0;
    if (errors == 0) $display("REGRESSION_TEST_SUCCESS llsc_interrupt_boundary");
    else $display("REGRESSION_TEST_FAILED llsc_interrupt_boundary errors=%0d", errors);
    $finish;
`else
    u_sched.pc_bank[1] = 32'h0000_0200;
    u_sched.status_bank[1] = 32'h0000_0001;
    u_sched.asid_bank[1] = 8'h2a;
    u_sched.gpr_bank[1] = 1024'd0;
    u_sched.gpr_bank[1][32 +: 32] = 32'h2222_0002;
`ifdef SRS_CONTEXT_TEST
    u_sched.srs_gpr_bank[1][33*32 +: 32] = 32'h2222_0002;
    u_sched.srs_gpr_bank[1][65*32 +: 32] = 32'h2222_5002;
    u_sched.srsctl_bank[1] = 32'h0000_1041;
`endif
    u_sched.fpr_bank[1][32 +: 32] = 32'h2222_f002;
    u_sched.fpr_bank[1][64 +: 32] = 32'h2222_f003;
    u_sched.fcsr_bank[1] = 32'h2222_fc02;
    yield_req = 1'b1;
    @(posedge clk);
    yield_req = 1'b0;
    while (!restore_req && cycles < 100) begin @(posedge clk); cycles=cycles+1; end
    if (!restore_req) errors = errors + 1;
    @(posedge clk);
    #1;
`ifdef SRS_CONTEXT_TEST
    if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[33] !== 32'h2222_0002) errors = errors + 1;
    if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[65] !== 32'h2222_5002) errors = errors + 1;
`else
    if (u_cpu.u_mips_id_stage.u_mips_regfile.regs[1] !== 32'h2222_0002) errors = errors + 1;
`endif
    if (restore_pc !== 32'h0000_0200) errors = errors + 1;
    if (u_cpu.u_mips_if_stage.pc !== 32'h0000_0200 &&
        u_cpu.u_mips_if_stage.pc !== 32'h0000_0204) errors = errors + 1;
    if (u_cpu.u_mips_cp0.cp0_entryhi_asid !== 8'h2a) errors = errors + 1;
    if (u_cpu.u_mips_cp0.cp0_status[0] !== 1'b1) errors = errors + 1;
`ifdef SRS_CONTEXT_TEST
    if (u_cpu.u_mips_cp0.cp0_srs_css !== 4'h1 ||
        u_cpu.u_mips_cp0.cp0_srs_ess !== 4'h1) errors = errors + 1;
`endif
    if (u_sched.gpr_bank[0][32 +: 32] !== 32'h1111_0001) errors = errors + 1;
`ifdef SRS_CONTEXT_TEST
    if (u_sched.srs_gpr_bank[0][33*32 +: 32] !== 32'h1111_5001) errors = errors + 1;
`endif
    if (u_sched.fpr_bank[0][32 +: 32] !== 32'h1111_f001) errors = errors + 1;
    if (u_sched.fpr_bank[0][64 +: 32] !== 32'h1111_f002) errors = errors + 1;
    if (u_sched.fcsr_bank[0] !== 32'h1111_fc01) errors = errors + 1;
    if (u_cpu.fpr[1] !== 32'h2222_f002 || u_cpu.fpr[2] !== 32'h2222_f003)
      errors = errors + 1;
    if (u_cpu.fcsr !== 32'h2222_fc02) errors = errors + 1;
    if (u_cpu.ll_reservation_valid !== 1'b0) errors = errors + 1;
    if (errors == 0) $display("REGRESSION_TEST_SUCCESS cpu_scheduler_integration");
    else $display("REGRESSION_TEST_FAILED cpu_scheduler_integration errors=%0d", errors);
    $finish;
`endif
  end
endmodule
