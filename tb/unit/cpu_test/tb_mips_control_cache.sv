`timescale 1ns/1ps

module tb_mips_control_cache;
    reg [31:0] inst;
    wire [4:0] alu_op, cache_op;
    wire [3:0] mdu_op;
    wire mdu_start, sel_mdu_out, alu_src, reg_write;
    wire [1:0] reg_dst, mem_to_reg;
    wire imm_signed, use_sa, mem_read, mem_write, cache_op_valid;
    wire [2:0] mem_op, branch_op;
    wire branch_likely;
    wire [1:0] jump_op;
    wire illegal_inst, cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap;
    wire [3:0] trap_op;
    wire [2:0] tlb_op;
    wire is_movn, is_movz;

    mips_control dut (
        .inst(inst), .alu_op(alu_op), .mdu_op(mdu_op), .mdu_start(mdu_start),
        .sel_mdu_out(sel_mdu_out), .alu_src(alu_src), .reg_write(reg_write),
        .reg_dst(reg_dst), .imm_signed(imm_signed), .use_sa(use_sa),
        .mem_read(mem_read), .mem_write(mem_write), .mem_op(mem_op),
        .cache_op_valid(cache_op_valid), .cache_op(cache_op),
        .mem_to_reg(mem_to_reg), .branch_op(branch_op),
        .branch_likely(branch_likely), .jump_op(jump_op),
        .illegal_inst(illegal_inst), .cp0_we(cp0_we), .is_mfc0(is_mfc0),
        .is_eret(is_eret), .is_syscall(is_syscall), .is_break(is_break),
        .is_di(is_di), .is_ei(is_ei), .is_wait(is_wait), .is_trap(is_trap),
        .trap_op(trap_op), .tlb_op(tlb_op), .is_movn(is_movn), .is_movz(is_movz)
    );

    integer failures, i;
    reg [4:0] valid_ops [0:9];

    task automatic check_cache;
        input [4:0] op;
        input expect_valid;
        begin
            inst = {6'b101111, 5'd1, op, 16'h0040};
            #1;
            if (expect_valid) begin
                if (illegal_inst || !cache_op_valid || cache_op != op ||
                    reg_write || mem_read || mem_write) begin
                    $display("FAIL CACHE valid op=%02h illegal=%b valid=%b decoded=%02h",
                             op, illegal_inst, cache_op_valid, cache_op);
                    failures = failures + 1;
                end
            end else if (!illegal_inst || cache_op_valid || reg_write ||
                         mem_read || mem_write) begin
                $display("FAIL CACHE reserved op=%02h illegal=%b valid=%b reg=%b mem=%b/%b",
                         op, illegal_inst, cache_op_valid, reg_write,
                         mem_read, mem_write);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        valid_ops[0]=5'h00; valid_ops[1]=5'h01; valid_ops[2]=5'h04;
        valid_ops[3]=5'h05; valid_ops[4]=5'h08; valid_ops[5]=5'h09;
        valid_ops[6]=5'h10; valid_ops[7]=5'h15; valid_ops[8]=5'h19;
        valid_ops[9]=5'h1d;
        for (i=0; i<10; i=i+1) check_cache(valid_ops[i], 1'b1);
        check_cache(5'h02, 1'b0);
        check_cache(5'h03, 1'b0);
        check_cache(5'h06, 1'b0);
        check_cache(5'h0f, 1'b0);
        check_cache(5'h1f, 1'b0);

        // SYNC is represented internally as an ordered-cache barrier.
        inst = 32'h0000000f; #1;
        if (illegal_inst || reg_write || mem_read || mem_write ||
            !cache_op_valid || cache_op != 5'h1e) failures = failures + 1;
        inst = 32'hcc200000; #1; // PREF 0, 0($1)
        if (illegal_inst || reg_write || mem_read || mem_write ||
            cache_op_valid) failures = failures + 1;

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_cache valid=10 reserved=5");
        else
            $display("REGRESSION_TEST_FAIL mips_control_cache failures=%0d", failures);
        $finish;
    end
endmodule
