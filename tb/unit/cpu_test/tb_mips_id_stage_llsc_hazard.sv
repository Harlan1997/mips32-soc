`timescale 1ns/1ps

// The SC source value is read from rt.  A load producing that register must
// hold SC in ID until the value is architecturally available.
module tb_mips_id_stage_llsc_hazard;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [31:0] inst;
    reg [31:0] nb_pending_reg;
    reg [4:0] ex_waddr;
    wire stall_req;
    wire ctx_save_done_unused, ctx_restore_done_unused;
    wire [1023:0] ctx_save_data_unused;
    wire [16383:0] ctx_save_srs_data_unused;
    wire branch_taken_unused, branch_likely_annul_unused;
    wire branch_likely_taken_unused, jump_taken_unused;
    wire control_valid_unused, control_taken_unused;
    wire [31:0] branch_target_unused, jump_target_unused, control_target_unused;
    wire [1:0] control_type_unused;
    wire [4:0] id_cp0_raddr_unused, sa_out_unused, rs_addr_unused;
    wire [2:0] id_cp0_sel_unused;
    wire [31:0] val_rs_unused, val_rt_unused, imm_ext_unused;
    wire [4:0] waddr_out_unused, rt_addr_unused, rd_addr_unused;
    wire [4:0] alu_op_unused, cache_op_unused;
    wire [3:0] mdu_op_unused, trap_op_unused;
    wire mdu_start_unused, sel_mdu_out_unused, alu_src_unused;
    wire reg_write_unused, mem_read_unused, mem_write_unused;
    wire [2:0] mem_op_unused;
    wire [1:0] mem_to_reg_unused;
    wire cache_op_valid_unused;
    wire cp0_we_unused, is_mfc0_unused, is_eret_unused, illegal_inst_unused;
    wire is_syscall_unused, is_break_unused, is_di_unused, is_ei_unused;
    wire is_wait_unused, is_trap_unused;
    wire [2:0] tlb_op_unused;
    integer failures;

    always #5 clk = ~clk;

    mips_id_stage dut (
        .clk(clk), .rst_n(rst_n),
        .fpu_condition(8'd0), .fpu_branch_invert(1'b0),
        .inst(inst), .pc_plus_4(32'd4),
        .rf_waddr(5'd0), .rf_wdata(32'd0), .rf_we(1'b0),
        .srs_current_set(4'd0), .srs_previous_set(4'd0),
        .srs_shadow_we(1'b0), .srs_shadow_wset(4'd0),
        .srs_shadow_waddr(5'd0), .srs_shadow_wdata(32'd0),
        .ctx_save_req(1'b0), .ctx_restore_req(1'b0),
        .ctx_restore_data(1024'd0), .ctx_restore_srs_data(16384'd0),
        .ctx_restore_set(4'd0),
        .ctx_save_done(ctx_save_done_unused), .ctx_save_data(ctx_save_data_unused),
        .ctx_save_srs_data(ctx_save_srs_data_unused), .ctx_restore_done(ctx_restore_done_unused),
        .fw_ex_we(1'b0), .fw_ex_waddr(5'd0), .fw_ex_val(32'd0),
        .fw_mem_we(1'b0), .fw_mem_waddr(5'd0), .fw_mem_val(32'd0),
        .fw_wb_we(1'b0), .fw_wb_waddr(5'd0), .fw_wb_val(32'd0),
        .ex_mem_read(1'b1), .ex_waddr(ex_waddr), .mem_mem_read(1'b0),
        .ex_mem_to_reg(2'b01), .mem_mem_to_reg(2'b00),
        .nb_pending_reg(nb_pending_reg), .stall_req(stall_req),
        .branch_taken(branch_taken_unused), .branch_likely_annul(branch_likely_annul_unused),
        .branch_likely_taken(branch_likely_taken_unused), .branch_target(branch_target_unused),
        .jump_taken(jump_taken_unused), .jump_target(jump_target_unused),
        .control_valid(control_valid_unused), .control_taken(control_taken_unused),
        .control_target(control_target_unused), .control_type(control_type_unused),
        .id_cp0_raddr(id_cp0_raddr_unused), .id_cp0_sel(id_cp0_sel_unused),
        .val_rs(val_rs_unused), .val_rt(val_rt_unused), .imm_ext(imm_ext_unused),
        .waddr_out(waddr_out_unused), .sa_out(sa_out_unused), .rs_addr(rs_addr_unused),
        .rt_addr(rt_addr_unused), .rd_addr(rd_addr_unused), .alu_op(alu_op_unused),
        .mdu_op(mdu_op_unused), .mdu_start(mdu_start_unused), .sel_mdu_out(sel_mdu_out_unused),
        .alu_src(alu_src_unused), .reg_write(reg_write_unused), .mem_read(mem_read_unused),
        .mem_write(mem_write_unused), .mem_op(mem_op_unused), .mem_to_reg(mem_to_reg_unused),
        .cache_op_valid(cache_op_valid_unused), .cache_op(cache_op_unused),
        .cp0_we(cp0_we_unused), .is_mfc0(is_mfc0_unused), .is_eret(is_eret_unused),
        .illegal_inst(illegal_inst_unused), .is_syscall(is_syscall_unused),
        .is_break(is_break_unused), .is_di(is_di_unused), .is_ei(is_ei_unused),
        .is_wait(is_wait_unused), .is_trap(is_trap_unused), .trap_op(trap_op_unused),
        .tlb_op(tlb_op_unused)
    );

    initial begin
        failures = 0;
        nb_pending_reg = 32'd0;
        ex_waddr = 5'd2;
        // SC $2, 0($1): rt=$2 is the conditional store data source.
        inst = 32'he022_0000;
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL SC load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end

        // A producer for another register must not stall this SC.
        ex_waddr = 5'd3;
        #1;
        if (stall_req !== 1'b0) begin
            $display("FAIL unrelated producer stalled SC: stall=%b", stall_req);
            failures = failures + 1;
        end
        ex_waddr = 5'd2;

        // The same source dependency is also tracked for nonblocking loads.
        nb_pending_reg = 32'd0;
        nb_pending_reg[2] = 1'b1;
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL SC nonblocking load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end

        // COP1X indexed memory and PREFX also use GPR[rt] as an address
        // index.  Fused COP1X arithmetic uses rt as an FPR selector instead
        // and must not inherit this integer-source hazard.
        nb_pending_reg = 32'd0;
        inst = {6'b010011, 5'd1, 5'd2, 5'd3, 5'd0, 6'h00}; // LWXC1
        ex_waddr = 5'd2;
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL LWXC1 index load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010011, 5'd1, 5'd2, 5'd3, 5'd0, 6'h0f}; // PREFX
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL PREFX index load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010011, 5'd1, 5'd2, 5'd3, 5'd0, 6'h20}; // MADD.S
        #1;
        if (stall_req !== 1'b0) begin
            $display("FAIL COP1X arithmetic falsely stalled on GPR rt: stall=%b", stall_req);
            failures = failures + 1;
        end

        // COP1 transfers and MOVZ/MOVN use rt as a GPR source/condition.
        inst = {6'b010001, 5'b00100, 5'd2, 5'd3, 5'd0, 6'h00}; // MTC1
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL MTC1 load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010001, 5'b00110, 5'd2, 5'd31, 5'd0, 6'h00}; // CTC1
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL CTC1 load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010001, 5'b00111, 5'd2, 5'd3, 5'd0, 6'h00}; // MTHC1
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL MTHC1 load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010001, 5'b10000, 5'd2, 5'd3, 5'd0, 6'h12}; // MOVZ.S
        #1;
        if (stall_req !== 1'b1) begin
            $display("FAIL MOVZ.S load/use hazard was not detected: stall=%b", stall_req);
            failures = failures + 1;
        end
        inst = {6'b010001, 5'b10000, 5'd2, 5'd3, 5'd0, 6'h00}; // ADD.S
        #1;
        if (stall_req !== 1'b0) begin
            $display("FAIL COP1 arithmetic falsely stalled on GPR rt: stall=%b", stall_req);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_id_stage_llsc_hazard");
        else
            $display("REGRESSION_TEST_FAIL mips_id_stage_llsc_hazard failures=%0d", failures);
        $finish;
    end
endmodule
