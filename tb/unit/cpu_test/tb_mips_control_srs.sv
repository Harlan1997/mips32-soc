`timescale 1ns/1ps

module tb_mips_control_srs;
    reg [31:0] inst;
    wire [4:0] alu_op;
    wire [3:0] mdu_op;
    wire mdu_start, sel_mdu_out, alu_src, reg_write;
    wire [1:0] reg_dst, mem_to_reg;
    wire imm_signed, use_sa, mem_read, mem_write, cache_op_valid;
    wire [4:0] cache_op;
    wire [2:0] mem_op, branch_op, tlb_op;
    wire branch_likely, fpu_branch_invert;
    wire [1:0] jump_op;
    wire illegal_inst, cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap, is_movn, is_movz;
    wire is_movf, is_movt, is_rdpgpr, is_wrpgpr;
    wire [3:0] trap_op;
    wire [2:0] fpu_condition_code;
    integer failures;

    mips_control dut (
        .inst(inst), .alu_op(alu_op), .mdu_op(mdu_op), .mdu_start(mdu_start),
        .sel_mdu_out(sel_mdu_out), .alu_src(alu_src), .reg_write(reg_write),
        .reg_dst(reg_dst), .imm_signed(imm_signed), .use_sa(use_sa),
        .mem_read(mem_read), .mem_write(mem_write), .mem_op(mem_op),
        .cache_op_valid(cache_op_valid), .cache_op(cache_op),
        .mem_to_reg(mem_to_reg), .branch_op(branch_op),
        .branch_likely(branch_likely), .fpu_branch_invert(fpu_branch_invert),
        .jump_op(jump_op), .illegal_inst(illegal_inst), .cp0_we(cp0_we),
        .is_mfc0(is_mfc0), .is_eret(is_eret), .is_syscall(is_syscall),
        .is_break(is_break), .is_di(is_di), .is_ei(is_ei), .is_wait(is_wait),
        .is_trap(is_trap), .trap_op(trap_op), .tlb_op(tlb_op),
        .is_movn(is_movn), .is_movz(is_movz), .is_movf(is_movf),
        .is_movt(is_movt), .is_rdpgpr(is_rdpgpr), .is_wrpgpr(is_wrpgpr),
        .fpu_condition_code(fpu_condition_code)
    );

    function automatic [31:0] cop0;
        input [4:0] rs, rt, rd, sa;
        input [5:0] funct;
        begin cop0 = {6'b010000, rs, rt, rd, sa, funct}; end
    endfunction

    task automatic check;
        input [31:0] value;
        input [4:0] expected_alu;
        input [1:0] expected_dst;
        input expected_rd, expected_wr;
        begin
            inst = value;
            #1;
            if (illegal_inst || alu_op != expected_alu ||
                reg_write != expected_rd || reg_dst != expected_dst ||
                is_rdpgpr != expected_rd || is_wrpgpr != expected_wr ||
                mem_read || mem_write || cp0_we) begin
                $display("FAIL SRS inst=%08h ill=%b alu=%b rw=%b dst=%b rdpgpr=%b wrpgpr=%b",
                         inst, illegal_inst, alu_op, reg_write, reg_dst,
                         is_rdpgpr, is_wrpgpr);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        // RDPGPR rt=$t0 -> rd=$t1 and WRPGPR rt=$t1 -> rd=$t0.
        check(cop0(5'b01010, 5'd8, 5'd9, 5'd0, 6'd0), 5'b10110, 2'b01, 1'b1, 1'b0);
        check(cop0(5'b01110, 5'd9, 5'd8, 5'd0, 6'd0), 5'b00000, 2'b00, 1'b0, 1'b1);
        // Fixed fields remain reserved even when SRS is enabled.
        inst = cop0(5'b01010, 5'd8, 5'd9, 5'd1, 6'd0); #1;
        if (!illegal_inst || is_rdpgpr || reg_write) failures = failures + 1;
        inst = cop0(5'b01110, 5'd9, 5'd8, 5'd0, 6'd1); #1;
        if (!illegal_inst || is_wrpgpr || reg_write) failures = failures + 1;
        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_srs optin=1");
        else
            $display("REGRESSION_TEST_FAIL mips_control_srs failures=%0d", failures);
        $finish;
    end
endmodule
