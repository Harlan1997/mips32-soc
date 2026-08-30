`timescale 1ns/1ps

module tb_mips_control_special2;
    reg [31:0] inst;
    wire [4:0] alu_op;
    wire [3:0] mdu_op;
    wire mdu_start, sel_mdu_out, alu_src, reg_write;
    wire [1:0] reg_dst;
    wire imm_signed, use_sa, mem_read, mem_write;
    wire [2:0] mem_op;
    wire cache_op_valid;
    wire [4:0] cache_op;
    wire [1:0] mem_to_reg;
    wire [2:0] branch_op;
    wire branch_likely, fpu_branch_invert;
    wire [1:0] jump_op;
    wire illegal_inst;
    wire cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap;
    wire [3:0] trap_op;
    wire [2:0] tlb_op;
    wire is_movn, is_movz, is_movf, is_movt;
    wire is_rdpgpr, is_wrpgpr;
    wire [2:0] fpu_condition_code;

    mips_control dut (
        .inst(inst), .alu_op(alu_op), .mdu_op(mdu_op),
        .mdu_start(mdu_start), .sel_mdu_out(sel_mdu_out), .alu_src(alu_src),
        .reg_write(reg_write), .reg_dst(reg_dst), .imm_signed(imm_signed),
        .use_sa(use_sa), .mem_read(mem_read), .mem_write(mem_write),
        .mem_op(mem_op), .cache_op_valid(cache_op_valid), .cache_op(cache_op),
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

    integer failures;

    function automatic [31:0] special2;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] sa;
        input [5:0] funct;
        begin special2 = {6'b011100, rs, rt, rd, sa, funct}; end
    endfunction

    function automatic [31:0] special;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] sa;
        input [5:0] funct;
        begin special = {6'b000000, rs, rt, rd, sa, funct}; end
    endfunction

    function automatic [31:0] branch_i;
        input [5:0] op;
        input [4:0] rs;
        input [4:0] rt;
        input [15:0] imm;
        begin branch_i = {op, rs, rt, imm}; end
    endfunction

    task automatic expect_reserved;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (!illegal_inst || reg_write || mdu_start || sel_mdu_out ||
                mem_read || mem_write || cache_op_valid || cp0_we ||
                branch_op != 3'b000 || jump_op != 2'b00) begin
                $display("FAIL reserved inst=%08h illegal=%b reg=%b mdu=%b/%0d mem=%b/%b",
                         inst, illegal_inst, reg_write, mdu_start, mdu_op,
                         mem_read, mem_write);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_mdu;
        input [31:0] value;
        input [3:0] expected_op;
        input expected_write;
        begin
            inst = value;
            #1;
            if (illegal_inst || !mdu_start || mdu_op != expected_op ||
                reg_write != expected_write ||
                (expected_write && reg_dst != 2'b01)) begin
                $display("FAIL valid inst=%08h illegal=%b mdu=%b/%0d reg=%b dst=%b",
                         inst, illegal_inst, mdu_start, mdu_op, reg_write, reg_dst);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_alu;
        input [31:0] value;
        input [4:0] expected_op;
        begin
            inst = value;
            #1;
            if (illegal_inst || !reg_write || alu_op != expected_op ||
                reg_dst != 2'b01) begin
                $display("FAIL ALU inst=%08h illegal=%b reg=%b alu=%0d dst=%b",
                         inst, illegal_inst, reg_write, alu_op, reg_dst);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        expect_mdu(special2(5'd1, 5'd2, 5'd0, 5'd0, 6'h00), 4'd8, 1'b0);
        expect_mdu(special2(5'd1, 5'd2, 5'd0, 5'd0, 6'h01), 4'd9, 1'b0);
        expect_mdu(special2(5'd1, 5'd2, 5'd7, 5'd0, 6'h02), 4'd12, 1'b1);
        expect_mdu(special2(5'd1, 5'd2, 5'd0, 5'd0, 6'h04), 4'd10, 1'b0);
        expect_mdu(special2(5'd1, 5'd2, 5'd0, 5'd0, 6'h05), 4'd11, 1'b0);
        expect_alu(special2(5'd1, 5'd7, 5'd7, 5'd0, 6'h20), 5'b10000);
        expect_alu(special2(5'd1, 5'd7, 5'd7, 5'd0, 6'h21), 5'b10001);

        // MADD-family rd and sa are reserved; MUL only reserves sa.
        expect_reserved(special2(5'd1, 5'd2, 5'd3, 5'd0, 6'h00));
        expect_reserved(special2(5'd1, 5'd2, 5'd0, 5'd1, 6'h01));
        expect_reserved(special2(5'd1, 5'd2, 5'd7, 5'd1, 6'h02));
        expect_reserved(special2(5'd1, 5'd2, 5'd3, 5'd0, 6'h04));
        expect_reserved(special2(5'd1, 5'd2, 5'd0, 5'd1, 6'h05));
        // CLZ/CLO require rt=rd and sa=0.
        expect_reserved(special2(5'd1, 5'd2, 5'd7, 5'd0, 6'h20));
        expect_reserved(special2(5'd1, 5'd7, 5'd7, 5'd1, 6'h21));

        // SPECIAL fixed-field checks, including the R2 EHB alias.
        expect_alu(special(5'd1, 5'd2, 5'd3, 5'd0, 6'h20), 5'b00000);
        expect_alu(special(5'd0, 5'd2, 5'd3, 5'd0, 6'h00), 5'b01000);
        expect_alu(special(5'd1, 5'd2, 5'd3, 5'd0, 6'h04), 5'b01000);
        inst = special(5'd0, 5'd0, 5'd0, 5'd3, 6'h00);
        #1;
        if (illegal_inst || !reg_write || alu_op != 5'b01000) begin
            $display("FAIL EHB alias inst=%08h illegal=%b reg=%b alu=%0d",
                     inst, illegal_inst, reg_write, alu_op);
            failures = failures + 1;
        end
        expect_reserved(special(5'd1, 5'd2, 5'd3, 5'd1, 6'h20));
        expect_reserved(special(5'd1, 5'd2, 5'd3, 5'd1, 6'h04));
        expect_reserved(special(5'd1, 5'd2, 5'd3, 5'd1, 6'h00));
        expect_reserved(special(5'd1, 5'd2, 5'd3, 5'd0, 6'h08));
        expect_reserved(special(5'd1, 5'd2, 5'd3, 5'd0, 6'h18));
        expect_reserved(branch_i(6'b000110, 5'd1, 5'd2, 16'd1));
        expect_reserved(branch_i(6'b010110, 5'd1, 5'd2, 16'd1));
        expect_reserved(branch_i(6'b000111, 5'd1, 5'd2, 16'd1));
        expect_reserved(branch_i(6'b010111, 5'd1, 5'd2, 16'd1));

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_special2 reserved=19");
        else
            $display("REGRESSION_TEST_FAIL mips_control_special2 failures=%0d", failures);
        $finish;
    end
endmodule
