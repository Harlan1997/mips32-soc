// Unit test: mips_mdu — MULT/MULTU/DIV/DIVU/MADD/MADDU/MSUB/MSUBU/MFHI/MFLO/MTHI/MTLO
module tb_mdu;
    reg         clk = 0;
    reg         rst_n = 0;
    reg         flush = 0;
    reg         issue_valid = 0;
    reg  [3:0]  op = 0;
    reg  [31:0] rs_val = 0;
    reg  [31:0] rt_val = 0;
    wire [31:0] hi_out, lo_out;
    wire        busy;
    wire        done_pulse;
    integer     errs = 0;

    always #5 clk = ~clk;

    mips_mdu dut (
        .clk(clk), .rst_n(rst_n),
        .flush(flush),
        .issue_valid(issue_valid), .op(op),
        .rs_val(rs_val), .rt_val(rt_val),
        .hi_out(hi_out), .lo_out(lo_out),
        .busy(busy), .done_pulse(done_pulse));

    task issue_op(input [3:0] o, input [31:0] a, input [31:0] b);
    begin
        @(negedge clk);
        issue_valid = 1; op = o; rs_val = a; rt_val = b;
        @(negedge clk);
        issue_valid = 0;
        wait (done_pulse == 1);
        @(negedge clk);
    end
    endtask

    task cancel_op(input [3:0] o, input [31:0] a, input [31:0] b);
    begin
        @(negedge clk);
        issue_valid = 1; op = o; rs_val = a; rt_val = b;
        @(negedge clk);
        issue_valid = 0;
        @(negedge clk);
        flush = 1;
        @(negedge clk);
        flush = 0;
        if (busy !== 1'b0 || done_pulse !== 1'b0) begin
            $display("FAIL cancel op=%0d: busy=%b done=%b", o, busy, done_pulse);
            errs = errs + 1;
        end
    end
    endtask

    task check_hilo(input [31:0] exp_hi, input [31:0] exp_lo, input [255:0] name);
    begin
        if (hi_out !== exp_hi || lo_out !== exp_lo) begin
            $display("FAIL %0s: got HI=%h LO=%h expected HI=%h LO=%h",
                     name, hi_out, lo_out, exp_hi, exp_lo);
            errs = errs + 1;
        end
    end
    endtask

    task check_lo(input [31:0] exp_lo, input [255:0] name);
    begin
        if (lo_out !== exp_lo) begin
            $display("FAIL %0s: LO=%h expected %h", name, lo_out, exp_lo);
            errs = errs + 1;
        end
    end
    endtask

    initial begin
        #12 rst_n = 1;
        @(negedge clk);

        // ---- Flush cancellation: in-flight work must not commit HI/LO ----
        issue_op(4'd6, 32'h1357_9BDF, 32'h0);
        issue_op(4'd7, 32'h2468_ACE0, 32'h0);
        cancel_op(4'd0, 32'hFFFF_FFFF, 32'h0000_0003);
        check_hilo(32'h1357_9BDF, 32'h2468_ACE0, "flush cancelled MULT");
        cancel_op(4'd2, 32'h7FFF_FFFF, 32'h0000_0003);
        check_hilo(32'h1357_9BDF, 32'h2468_ACE0, "flush cancelled DIV");

        // A cancelled operation must leave the unit reusable.
        issue_op(4'd1, 32'd7, 32'd8);
        check_hilo(32'h0, 32'd56, "post-flush MULTU");

        // ---- MULTU: small × small early-exit path ----
        issue_op(4'd1, 32'd123, 32'd456);
        check_hilo(32'h0, 32'd56088, "MULTU 123*456");

        // ---- MULTU: large × large full pipeline ----
        issue_op(4'd1, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        check_hilo(32'hFFFF_FFFE, 32'h0000_0001, "MULTU (2^32-1)^2");

        // ---- MULT: signed negative × positive ----
        issue_op(4'd0, -32'd3, 32'd5);
        check_hilo(32'hFFFF_FFFF, -32'd15, "MULT -3*5");

        // ---- MULT: negative × negative ----
        issue_op(4'd0, -32'd7, -32'd9);
        check_hilo(32'h0, 32'd63, "MULT -7*-9");

        // ---- DIVU: normal ----
        issue_op(4'd3, 32'd100, 32'd7);
        check_hilo(32'd2, 32'd14, "DIVU 100/7");

        // ---- DIVU: normalized restoring path (sparse and 16-bit boundary) ----
        issue_op(4'd3, 32'h1234_5678, 32'h0000_1234);
        check_hilo(32'h0000_0DA8, 32'h0001_0004, "DIVU normalized 0x12345678/0x1234");
        issue_op(4'd3, 32'hFFFF_FFFF, 32'h8000_0001);
        check_hilo(32'h7FFF_FFFE, 32'h0000_0001, "DIVU full-width");

        // ---- DIVU: divisor > dividend (early exit) ----
        issue_op(4'd3, 32'd5, 32'd100);
        check_hilo(32'd5, 32'd0, "DIVU 5/100");

        // ---- DIVU: divide by zero ----
        issue_op(4'd3, 32'd42, 32'd0);
        check_hilo(32'd42, 32'hFFFF_FFFF, "DIVU 42/0");

        // ---- DIV: signed negative ÷ positive ----
        issue_op(4'd2, -32'd20, 32'd3);
        // -20 / 3 = -6 rem -2 (MIPS: rem sign follows dividend)
        check_hilo(-32'd2, -32'd6, "DIV -20/3");
        issue_op(4'd2, 32'h1234_5678, 32'h0000_1234);
        check_hilo(32'h0000_0DA8, 32'h0001_0004, "DIV normalized positive");

        // ---- DIV: signed divide by zero ----
        issue_op(4'd2, -32'd42, 32'd0);
        check_hilo(-32'd42, 32'hFFFF_FFFF, "DIV -42/0");

        // ---- MULT: signed INT_MIN * INT_MIN edge case ----
        issue_op(4'd0, 32'h8000_0000, 32'h8000_0000);
        check_hilo(32'h4000_0000, 32'h0, "MULT INT_MIN*INT_MIN");

        // ---- MTHI / MTLO / MFHI / MFLO ----
        issue_op(4'd6, 32'hDEAD_BEEF, 32'h0);   // MTHI
        if (hi_out !== 32'hDEAD_BEEF) begin
            $display("FAIL MTHI: HI=%h", hi_out); errs = errs + 1; end
        issue_op(4'd7, 32'hCAFE_BABE, 32'h0);   // MTLO
        if (lo_out !== 32'hCAFE_BABE) begin
            $display("FAIL MTLO: LO=%h", lo_out); errs = errs + 1; end

        // ---- MADDU: {HI, LO} += rs*rt ----
        // Set HI:LO = 0:100 first via MULTU 1×100
        issue_op(4'd1, 32'd1, 32'd100);
        check_hilo(32'h0, 32'd100, "MULTU 1*100 (setup)");
        // Now MADDU 5×6 = 30, expect HI:LO = 0:130
        issue_op(4'd9, 32'd5, 32'd6);
        check_hilo(32'h0, 32'd130, "MADDU 100+5*6");

        // ---- MADD: signed accumulate negative operand ----
        // Currently HI:LO = 0:130. MADD (-5, 6) = -30 -> 100
        issue_op(4'd8, -32'd5, 32'd6);
        check_hilo(32'h0, 32'd100, "MADD 130+(-5)*6");

        // ---- MSUBU: {HI, LO} -= rs*rt ----
        // Currently HI:LO = 0:100. MSUBU 2*10 = 20 → 80
        issue_op(4'd11, 32'd2, 32'd10);
        check_hilo(32'h0, 32'd80, "MSUBU 100-2*10");

        // ---- MSUB: signed accumulate negative operand ----
        // Currently HI:LO = 0:80. MSUB (-5, 6) = -30 → 80 - (-30) = 110
        issue_op(4'd10, -32'd5, 32'd6);
        check_hilo(32'h0, 32'd110, "MSUB 80-(-5)*6");

        // ---- MUL rd = (rs*rt)[31:0] ----
        issue_op(4'd12, 32'd7, 32'd8);
        check_lo(32'd56, "MUL 7*8");

        issue_op(4'd12, -32'd5, 32'd6);
        check_lo(-32'd30, "MUL -5*6");

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS mdu");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #100000 $display("FAIL timeout"); $finish;
    end
endmodule
