`timescale 1ns/1ps

module tb_mips_control_cp0;
    reg [31:0] inst;
    wire [4:0] alu_op;
    wire [3:0] mdu_op;
    wire mdu_start, sel_mdu_out, alu_src, reg_write;
    wire [1:0] reg_dst, mem_to_reg;
    wire imm_signed, use_sa, mem_read, mem_write, cache_op_valid;
    wire [4:0] cache_op;
    wire [2:0] mem_op, branch_op, tlb_op;
    wire branch_likely;
    wire [1:0] jump_op;
    wire illegal_inst, cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap;
    wire [3:0] trap_op;
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

    integer failures;

    function automatic [31:0] cop0;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [4:0] sa;
        input [5:0] funct;
        begin cop0 = {6'b010000, rs, rt, rd, sa, funct}; end
    endfunction

    function automatic [31:0] cop1_arith;
        input [4:0] fmt;
        input [4:0] ft;
        input [4:0] fs;
        input [4:0] fd;
        input [5:0] funct;
        begin cop1_arith = {6'b010001, fmt, ft, fs, fd, funct}; end
    endfunction

    task automatic expect_reserved;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (!illegal_inst || reg_write || cp0_we || is_mfc0 || is_eret ||
                is_di || is_ei || is_wait || tlb_op != 3'b000 || mem_read ||
                mem_write || cache_op_valid || branch_op != 3'b000 ||
                jump_op != 2'b00) begin
                $display("FAIL COP0 reserved inst=%08h illegal=%b reg=%b cp0=%b mfc=%b eret=%b di/ei=%b/%b wait=%b tlb=%b",
                         inst, illegal_inst, reg_write, cp0_we, is_mfc0,
                         is_eret, is_di, is_ei, is_wait, tlb_op);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_valid;
        input [31:0] value;
        input [2:0] expected_tlb;
        begin
            inst = value;
            #1;
            if (illegal_inst || mem_read || mem_write ||
                (tlb_op != expected_tlb)) begin
                $display("FAIL COP0 valid inst=%08h illegal=%b tlb=%b expected=%b",
                         inst, illegal_inst, tlb_op, expected_tlb);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_cop1_valid;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (illegal_inst) begin
                $display("FAIL COP1 valid inst=%08h illegal=%b", inst, illegal_inst);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_cop1_mem;
        input [5:0] op;
        input expect_read;
        input expect_write;
        begin
            inst = {op, 5'd1, 5'd2, 16'h0010};
            #1;
            if (illegal_inst || mem_read != expect_read ||
                mem_write != expect_write || mem_op != 3'b100 ||
                alu_op != 5'b00001 || reg_write) begin
                $display("FAIL COP1 memory op=%02h illegal=%b rd/wr=%b/%b", op,
                         illegal_inst, mem_read, mem_write);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        // MFC0/MTC0 and the five supported CO operations.
        expect_valid(cop0(5'b00000, 5'd2, 5'd12, 5'd0, 6'b000000), 3'b000);
        expect_valid(cop0(5'b00000, 5'd2, 5'd16, 5'd0, 6'b000001), 3'b000); // MFC0 Config1
        expect_valid(cop0(5'b00100, 5'd2, 5'd12, 5'd0, 6'b000000), 3'b000);
        expect_valid(cop0(5'b00100, 5'd2, 5'd16, 5'd0, 6'b000001), 3'b000); // MTC0 Config1 sel
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b011000), 3'b000); // ERET
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b000001), 3'b001); // TLBR
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b000010), 3'b010); // TLBWI
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b000110), 3'b011); // TLBWR
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b001000), 3'b100); // TLBP
        expect_valid(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b100000), 3'b000); // WAIT
        expect_valid(cop0(5'b01011, 5'd2, 5'd12, 5'd0, 6'b000000), 3'b000); // DI
        expect_valid(cop0(5'b01011, 5'd2, 5'd12, 5'd0, 6'b100000), 3'b000); // EI

        // Unsupported COP0 rs/function and malformed MFMC0/TLB fields.
        expect_reserved(cop0(5'b00001, 5'd2, 5'd12, 5'd0, 6'b000000));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b011000));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b000001));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b000010));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b000110));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b001000));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd1, 6'b100000));
        expect_reserved(cop0(5'b10000, 5'd0, 5'd0, 5'd0, 6'b000011));
        expect_reserved(cop0(5'b01011, 5'd2, 5'd11, 5'd0, 6'b000000));
        expect_reserved(cop0(5'b01011, 5'd2, 5'd12, 5'd1, 6'b000000));
        expect_reserved(cop0(5'b01011, 5'd2, 5'd12, 5'd0, 6'b000001));
        expect_reserved(cop0(5'b01010, 5'd2, 5'd12, 5'd0, 6'b000000));
        // RDPGPR/WRPGPR require a non-zero shadow register set.  SRSCtl.SS
        // is tied to zero in this implementation, so both are RI.
        expect_reserved(cop0(5'b01010, 5'd9, 5'd8, 5'd0, 6'b000000));
        expect_reserved(cop0(5'b01110, 5'd9, 5'd8, 5'd0, 6'b000000));

        // The low three bits are sel; bits [10:3] remain reserved.
        expect_reserved(cop0(5'b00000, 5'd2, 5'd12, 5'd1, 6'b000000));
        expect_reserved(cop0(5'b00100, 5'd2, 5'd12, 5'd1, 6'b000000));

        // COP1 double arithmetic accepts only even-numbered register pairs.
        expect_cop1_valid(cop1_arith(5'b10001, 5'd0, 5'd2, 5'd4, 6'h00));
        expect_reserved(cop1_arith(5'b10001, 5'd0, 5'd2, 5'd5, 6'h00));
        expect_reserved(cop1_arith(5'b10001, 5'd1, 5'd2, 5'd4, 6'h00));
        expect_reserved(cop1_arith(5'b10001, 5'd0, 5'd3, 5'd4, 6'h00));
        expect_reserved({6'b010001, 5'b00000, 5'd2, 5'd4, 11'b00000000001});
        expect_reserved({6'b010001, 5'b00010, 5'd2, 5'd30, 11'b0});
        expect_reserved({6'b010001, 5'b00110, 5'd2, 5'd30, 11'b0});
        expect_cop1_mem(6'b110001, 1'b1, 1'b0); // LWC1
        expect_cop1_mem(6'b111001, 1'b0, 1'b1); // SWC1
        expect_cop1_mem(6'b110101, 1'b1, 1'b0); // LDC1, even FPR pair
        expect_cop1_mem(6'b111101, 1'b0, 1'b1); // SDC1, even FPR pair
        expect_reserved({6'b110101, 5'd1, 5'd3, 16'h0010}); // odd pair
        expect_reserved({6'b111101, 5'd1, 5'd3, 16'h0010}); // odd pair

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_cp0 valid=13 reserved=22");
        else
            $display("REGRESSION_TEST_FAIL mips_control_cp0 failures=%0d", failures);
        $finish;
    end
endmodule
