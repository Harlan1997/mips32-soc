`timescale 1ns/1ps

module tb_mips_control_special3;
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
    wire branch_likely;
    wire [1:0] jump_op;
    wire illegal_inst;
    wire cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap;
    wire [3:0] trap_op;
    wire [2:0] tlb_op;
    wire is_movn, is_movz;

    mips_control dut (
        .inst(inst), .alu_op(alu_op), .mdu_op(mdu_op),
        .mdu_start(mdu_start), .sel_mdu_out(sel_mdu_out), .alu_src(alu_src),
        .reg_write(reg_write), .reg_dst(reg_dst), .imm_signed(imm_signed),
        .use_sa(use_sa), .mem_read(mem_read), .mem_write(mem_write),
        .mem_op(mem_op), .cache_op_valid(cache_op_valid), .cache_op(cache_op),
        .mem_to_reg(mem_to_reg), .branch_op(branch_op),
        .branch_likely(branch_likely), .jump_op(jump_op),
        .illegal_inst(illegal_inst), .cp0_we(cp0_we), .is_mfc0(is_mfc0),
        .is_eret(is_eret), .is_syscall(is_syscall), .is_break(is_break),
        .is_di(is_di), .is_ei(is_ei), .is_wait(is_wait), .is_trap(is_trap),
        .trap_op(trap_op), .tlb_op(tlb_op), .is_movn(is_movn), .is_movz(is_movz)
    );

    integer failures;

    function automatic [31:0] special3;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] sa;
        input [5:0] funct;
        begin special3 = {6'b011111, rs, rt, rd, sa, funct}; end
    endfunction

    task automatic expect_reserved;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (!illegal_inst || reg_write || mem_read || mem_write ||
                cache_op_valid || cp0_we || branch_op != 3'b000 ||
                jump_op != 2'b00) begin
                $display("FAIL reserved inst=%08h illegal=%b reg=%b mem=%b/%b cache=%b cp0=%b branch=%b jump=%b",
                         inst, illegal_inst, reg_write, mem_read, mem_write,
                         cache_op_valid, cp0_we, branch_op, jump_op);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_valid;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (illegal_inst || !reg_write || mem_read || mem_write) begin
                $display("FAIL valid inst=%08h illegal=%b reg=%b mem=%b/%b",
                         inst, illegal_inst, reg_write, mem_read, mem_write);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_bshfl_valid;
        input [4:0] subop;
        input [4:0] expected_alu;
        begin
            inst = special3(5'd0, 5'd2, 5'd3, subop, 6'b100000);
            #1;
            if (illegal_inst || !reg_write || mem_read || mem_write ||
                alu_op != expected_alu || reg_dst != 2'b01) begin
                $display("FAIL BSHFL subop=%02h illegal=%b reg=%b alu=%02h dst=%b",
                         subop, illegal_inst, reg_write, alu_op, reg_dst);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        expect_valid(special3(5'd1, 5'd2, 5'd0, 5'd0, 6'b000000));
        expect_valid(special3(5'd1, 5'd2, 5'd7, 5'd0, 6'b000100));
        expect_valid(special3(5'd3, 5'd2, 5'd0, 5'd0, 6'b111011));
        expect_valid(special3(5'd0, 5'd2, 5'd0, 5'b00010, 6'b100000));
        // ALIGN consumes both rs and rt; all four byte positions are legal.
        for (integer bp = 8; bp < 12; bp = bp + 1)
            expect_bshfl_valid(bp[4:0], 5'b11010);
        expect_bshfl_valid(5'b01001, 5'b11010);
        expect_reserved(special3(5'd1, 5'd2, 5'd31, 5'd1, 6'b000000));
        expect_reserved(special3(5'd1, 5'd2, 5'd7, 5'd8, 6'b000100));
        expect_reserved(special3(5'd1, 5'd2, 5'd0, 5'd0, 6'b000001));
        expect_reserved(special3(5'd2, 5'd2, 5'd0, 5'd0, 6'b111011));
        expect_reserved(special3(5'd3, 5'd2, 5'd28, 5'd0, 6'b111011));
        expect_reserved(special3(5'd0, 5'd2, 5'd0, 5'b00001, 6'b100000));
        expect_reserved(special3(5'd0, 5'd2, 5'd0, 5'b00100, 6'b100000));
        expect_reserved(special3(5'd0, 5'd2, 5'd0, 5'b00010, 6'b111111));

        // Complete the MIPS32r2 BSHFL/BITSWAP sub-op matrix.
        expect_bshfl_valid(5'b00000, 5'b11001); // BITSWAP
        expect_bshfl_valid(5'b00010, 5'b10100); // WSBH
        expect_bshfl_valid(5'b10000, 5'b10010); // SEB
        expect_bshfl_valid(5'b11000, 5'b10011); // SEH
        for (integer subop = 0; subop < 32; subop = subop + 1) begin
            if (subop != 0 && subop != 2 && subop != 8 && subop != 9 &&
                subop != 10 && subop != 11 && subop != 16 && subop != 24)
                expect_reserved(special3(5'd0, 5'd2, 5'd3, subop[4:0], 6'b100000));
        end
        // rs remains reserved for the non-ALIGN BSHFL operations.
        expect_reserved(special3(5'd1, 5'd2, 5'd3, 5'b00010, 6'b100000));

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_special3 reserved=37");
        else
            $display("REGRESSION_TEST_FAIL mips_control_special3 failures=%0d", failures);
        $finish;
    end
endmodule
