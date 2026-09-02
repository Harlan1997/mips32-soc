`timescale 1ns/1ps

module tb_mips_control_fpu_cond;
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
    wire fpu_branch_invert;
    wire [1:0] jump_op;
    wire illegal_inst;
    wire cp0_we, is_mfc0, is_eret, is_syscall, is_break;
    wire is_di, is_ei, is_wait, is_trap;
    wire [3:0] trap_op;
    wire [2:0] tlb_op;
    wire is_movn, is_movz, is_movf, is_movt;
    wire [2:0] fpu_condition_code;
    integer failures;

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
        .is_movn(is_movn), .is_movz(is_movz), .is_movf(is_movf), .is_movt(is_movt),
        .fpu_condition_code(fpu_condition_code)
    );

    function automatic [31:0] movcond;
        input [4:0] rs;
        input [4:0] rt;
        input [4:0] rd;
        input [2:0] cc;
        input [1:0] reserved;
        begin
            // MOVF/MOVT encode cc in rt[4:2], rt[1] reserved, and tf in rt[0].
            movcond = {6'b000000, rs, {cc, 1'b0, rt[0]}, rd, 3'd0, reserved, 6'b000001};
        end
    endfunction

    function automatic [31:0] fpu_cond_move;
        input [4:0] fmt;
        input [4:0] rt_gpr;
        input [4:0] fs;
        input [4:0] fd;
        input [5:0] funct;
        begin
            fpu_cond_move = {6'b010001, fmt, rt_gpr, fs, fd, funct};
        end
    endfunction

    function automatic [31:0] fpu_cop1x;
        input [4:0] fr;
        input [4:0] ft;
        input [4:0] fs;
        input [4:0] fd;
        input [5:0] funct;
        begin
            fpu_cop1x = {6'b010011, fr, ft, fs, fd, funct};
        end
    endfunction

    task automatic expect_valid;
        input [31:0] value;
        input want_f;
        input want_t;
        input [2:0] want_cc;
        begin
            inst = value;
            #1;
            if (illegal_inst || !reg_write || reg_dst != 2'b01 ||
                alu_op != 5'b10110 || is_movf != want_f || is_movt != want_t ||
                fpu_condition_code != want_cc) begin
                $display("FAIL valid inst=%08h illegal=%b reg=%b dst=%b alu=%02h f=%b t=%b",
                         inst, illegal_inst, reg_write, reg_dst, alu_op, is_movf, is_movt);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_reserved;
        input [31:0] value;
        begin
            inst = value;
            #1;
            if (!illegal_inst || reg_write || mem_read || mem_write ||
                is_movf || is_movt) begin
                $display("FAIL reserved inst=%08h illegal=%b reg=%b mem=%b/%b f=%b t=%b",
                         inst, illegal_inst, reg_write, mem_read, mem_write, is_movf, is_movt);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        expect_valid(movcond(5'd8, 5'd0, 5'd10, 3'd0, 2'd0), 1'b1, 1'b0, 3'd0);
        expect_valid(movcond(5'd9, 5'd1, 5'd11, 3'd0, 2'd0), 1'b0, 1'b1, 3'd0);
        expect_valid(movcond(5'd8, 5'd0, 5'd10, 3'd1, 2'd0), 1'b1, 1'b0, 3'd1);
        expect_valid(movcond(5'd8, 5'd1, 5'd10, 3'd7, 2'd0), 1'b0, 1'b1, 3'd7);
        expect_reserved(32'h01025001); // MOVF/MOVT rt[1] is reserved
        // Reserved low fields are independent of the MOVF/MOVT cc encoding.
        expect_reserved(32'h01005041);

        // COP1 MOVZ/MOVN use rt as an integer GPR condition.  For fmt=D,
        // only fs/fd are FPR-pair selectors; an odd GPR condition must not
        // be rejected as an odd ft field.
        inst = fpu_cond_move(5'b10001, 5'd5, 5'd0, 5'd12, 6'h12);
        #1;
        if (illegal_inst) begin
            $display("FAIL MOVZ.D rejected with odd integer rt");
            failures = failures + 1;
        end
        expect_reserved(fpu_cond_move(5'b10001, 5'd5, 5'd0, 5'd13, 6'h12));
        expect_reserved(fpu_cond_move(5'b10001, 5'd5, 5'd1, 5'd12, 6'h13));

        // COP1 MOVF/MOVT use funct=0x11.  The condition is encoded in ft
        // (cc[4:2], reserved bit 1, tf bit 0), while fs/fd are FPR pairs in
        // the D format.
        inst = fpu_cond_move(5'b10000, 5'd0, 5'd2, 5'd4, 6'h11);
        #1;
        if (illegal_inst) begin
            $display("FAIL MOVF.S rejected");
            failures = failures + 1;
        end
        inst = fpu_cond_move(5'b10001, 5'd1, 5'd2, 5'd4, 6'h11);
        #1;
        if (illegal_inst) begin
            $display("FAIL MOVT.D rejected");
            failures = failures + 1;
        end
        expect_reserved(fpu_cond_move(5'b10001, 5'd1, 5'd2, 5'd4, 6'h11) |
                        32'h00020000); // reserved ft[1]

        // MTHC1/MFHC1 use the high-word transfer encodings and require the
        // same zeroed low fields as the other COP1 register transfers.
        inst = {6'b010001, 5'b00111, 5'd8, 5'd2, 11'd0};
        #1;
        if (illegal_inst) begin
            $display("FAIL MTHC1 rejected");
            failures = failures + 1;
        end
        inst = {6'b010001, 5'b00011, 5'd9, 5'd2, 11'd0};
        #1;
        if (illegal_inst) begin
            $display("FAIL MFHC1 rejected");
            failures = failures + 1;
        end
        expect_reserved({6'b010001, 5'b00111, 5'd8, 5'd2, 11'd1});

        // RECIP/RSQRT are unary COP1 operations: single and even-pair D
        // formats are legal, while W-format and odd D-pair selectors are RI.
        inst = fpu_cond_move(5'b10000, 5'd0, 5'd0, 5'd2, 6'h15);
        #1;
        if (illegal_inst) begin
            $display("FAIL RECIP.S rejected");
            failures = failures + 1;
        end
        inst = fpu_cond_move(5'b10001, 5'd0, 5'd0, 5'd2, 6'h16);
        #1;
        if (illegal_inst) begin
            $display("FAIL RSQRT.D rejected");
            failures = failures + 1;
        end
        expect_reserved(fpu_cond_move(5'b10100, 5'd0, 5'd0, 5'd2, 6'h15));
        expect_reserved(fpu_cond_move(5'b10001, 5'd0, 5'd1, 5'd2, 6'h15));
        inst = fpu_cop1x(5'd2, 5'd4, 5'd0, 5'd2, 6'h20);
        #1;
        if (illegal_inst) begin
            $display("FAIL MADD.S rejected");
            failures = failures + 1;
        end
        inst = fpu_cop1x(5'd2, 5'd4, 5'd0, 5'd2, 6'h39);
        #1;
        if (illegal_inst) begin
            $display("FAIL NMSUB.D rejected");
            failures = failures + 1;
        end
        expect_reserved(fpu_cop1x(5'd2, 5'd4, 5'd1, 5'd2, 6'h39));
        expect_reserved(fpu_cond_move(5'b10000, 5'd0, 5'd4, 5'd2, 6'h18));

        // MOVT must not consume the existing MTHI encoding (funct=0x11).
        inst = {6'b000000, 5'd8, 5'd0, 5'd0, 5'd0, 6'b010001};
        #1;
        if (illegal_inst || !mdu_start || mdu_op != 4'd6) begin
            $display("FAIL MTHI regression illegal=%b start=%b mdu=%0d", illegal_inst, mdu_start, mdu_op);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("REGRESSION_TEST_SUCCESS mips_control_fpu_cond fcc=8 reserved=2");
        else
            $display("REGRESSION_TEST_FAIL mips_control_fpu_cond failures=%0d", failures);
        $finish;
    end
endmodule
