// =============================================================================
// tb_mips_rob.v — unit test for mips_rob.
//
// Instantiates a DEPTH=1 (golden, old-register-equivalent) and a DEPTH=2
// (Stage 2 skeleton) mips_rob side by side, drives both with the identical
// allocate/stall/flush stimulus, and checks every commit-visible wb_* output
// matches every cycle. This is the parity claim Stage 2 depends on: with the
// D-cache still blocking, DEPTH=2's circular-buffer bookkeeping must be
// undetectable from the outside.
// =============================================================================
`timescale 1ns/1ps

module tb_mips_rob;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg        stall, flush;
    reg [31:0] mem_rdata_fmt, mem_ex_out, mem_pc_plus_8;
    reg [4:0]  mem_waddr, mem_rd_addr, mem_cp0_raddr;
    reg [2:0]  mem_cp0_sel;
    reg        mem_reg_write, mem_cp0_we, mem_is_eret;
    reg [2:0]  mem_tlb_op;
    reg        mem_except_req;
    reg [4:0]  mem_except_code;
    reg        mem_except_is_data, mem_bd;
    reg [1:0]  mem_mem_to_reg;

    wire [31:0] g_wb_rdata_fmt, g_wb_ex_out, g_wb_pc_plus_8;
    wire [4:0]  g_wb_waddr, g_wb_rd_addr, g_wb_cp0_raddr;
    wire [2:0]  g_wb_cp0_sel;
    wire        g_wb_reg_write, g_wb_cp0_we, g_wb_is_eret;
    wire [2:0]  g_wb_tlb_op;
    wire        g_wb_except_req;
    wire [4:0]  g_wb_except_code;
    wire        g_wb_except_is_data, g_wb_bd;
    wire [1:0]  g_wb_mem_to_reg;

    wire [31:0] d_wb_rdata_fmt, d_wb_ex_out, d_wb_pc_plus_8;
    wire [4:0]  d_wb_waddr, d_wb_rd_addr, d_wb_cp0_raddr;
    wire [2:0]  d_wb_cp0_sel;
    wire        d_wb_reg_write, d_wb_cp0_we, d_wb_is_eret;
    wire [2:0]  d_wb_tlb_op;
    wire        d_wb_except_req;
    wire [4:0]  d_wb_except_code;
    wire        d_wb_except_is_data, d_wb_bd;
    wire [1:0]  d_wb_mem_to_reg;

    integer errs = 0;

    mips_rob #(.DEPTH(1)) golden (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .mem_rdata_fmt(mem_rdata_fmt), .mem_ex_out(mem_ex_out), .mem_pc_plus_8(mem_pc_plus_8),
        .mem_waddr(mem_waddr), .mem_rd_addr(mem_rd_addr), .mem_cp0_raddr(mem_cp0_raddr),
        .mem_cp0_sel(mem_cp0_sel), .mem_reg_write(mem_reg_write), .mem_cp0_we(mem_cp0_we),
        .mem_is_eret(mem_is_eret), .mem_tlb_op(mem_tlb_op), .mem_except_req(mem_except_req),
        .mem_except_code(mem_except_code), .mem_except_is_data(mem_except_is_data),
        .mem_bd(mem_bd), .mem_mem_to_reg(mem_mem_to_reg),
        .wb_rdata_fmt(g_wb_rdata_fmt), .wb_ex_out(g_wb_ex_out), .wb_pc_plus_8(g_wb_pc_plus_8),
        .wb_waddr(g_wb_waddr), .wb_rd_addr(g_wb_rd_addr), .wb_cp0_raddr(g_wb_cp0_raddr),
        .wb_cp0_sel(g_wb_cp0_sel), .wb_reg_write(g_wb_reg_write), .wb_cp0_we(g_wb_cp0_we),
        .wb_is_eret(g_wb_is_eret), .wb_tlb_op(g_wb_tlb_op), .wb_except_req(g_wb_except_req),
        .wb_except_code(g_wb_except_code), .wb_except_is_data(g_wb_except_is_data),
        .wb_bd(g_wb_bd), .wb_mem_to_reg(g_wb_mem_to_reg)
    );

    mips_rob #(.DEPTH(2)) dut (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .mem_rdata_fmt(mem_rdata_fmt), .mem_ex_out(mem_ex_out), .mem_pc_plus_8(mem_pc_plus_8),
        .mem_waddr(mem_waddr), .mem_rd_addr(mem_rd_addr), .mem_cp0_raddr(mem_cp0_raddr),
        .mem_cp0_sel(mem_cp0_sel), .mem_reg_write(mem_reg_write), .mem_cp0_we(mem_cp0_we),
        .mem_is_eret(mem_is_eret), .mem_tlb_op(mem_tlb_op), .mem_except_req(mem_except_req),
        .mem_except_code(mem_except_code), .mem_except_is_data(mem_except_is_data),
        .mem_bd(mem_bd), .mem_mem_to_reg(mem_mem_to_reg),
        .wb_rdata_fmt(d_wb_rdata_fmt), .wb_ex_out(d_wb_ex_out), .wb_pc_plus_8(d_wb_pc_plus_8),
        .wb_waddr(d_wb_waddr), .wb_rd_addr(d_wb_rd_addr), .wb_cp0_raddr(d_wb_cp0_raddr),
        .wb_cp0_sel(d_wb_cp0_sel), .wb_reg_write(d_wb_reg_write), .wb_cp0_we(d_wb_cp0_we),
        .wb_is_eret(d_wb_is_eret), .wb_tlb_op(d_wb_tlb_op), .wb_except_req(d_wb_except_req),
        .wb_except_code(d_wb_except_code), .wb_except_is_data(d_wb_except_is_data),
        .wb_bd(d_wb_bd), .wb_mem_to_reg(d_wb_mem_to_reg)
    );

    task check_parity(input [255:0] name);
    begin
        if (g_wb_rdata_fmt !== d_wb_rdata_fmt || g_wb_ex_out !== d_wb_ex_out ||
            g_wb_pc_plus_8 !== d_wb_pc_plus_8 || g_wb_waddr !== d_wb_waddr ||
            g_wb_rd_addr !== d_wb_rd_addr || g_wb_cp0_raddr !== d_wb_cp0_raddr ||
            g_wb_cp0_sel !== d_wb_cp0_sel || g_wb_reg_write !== d_wb_reg_write ||
            g_wb_cp0_we !== d_wb_cp0_we || g_wb_is_eret !== d_wb_is_eret ||
            g_wb_tlb_op !== d_wb_tlb_op || g_wb_except_req !== d_wb_except_req ||
            g_wb_except_code !== d_wb_except_code ||
            g_wb_except_is_data !== d_wb_except_is_data ||
            g_wb_bd !== d_wb_bd || g_wb_mem_to_reg !== d_wb_mem_to_reg) begin
            $display("FAIL %0s: DEPTH=1 vs DEPTH=2 mismatch @%0t", name, $time);
            $display("  golden: rdata=%h ex=%h pc8=%h waddr=%h rw=%b except=%b code=%h",
                      g_wb_rdata_fmt, g_wb_ex_out, g_wb_pc_plus_8, g_wb_waddr,
                      g_wb_reg_write, g_wb_except_req, g_wb_except_code);
            $display("  dut   : rdata=%h ex=%h pc8=%h waddr=%h rw=%b except=%b code=%h",
                      d_wb_rdata_fmt, d_wb_ex_out, d_wb_pc_plus_8, d_wb_waddr,
                      d_wb_reg_write, d_wb_except_req, d_wb_except_code);
            errs = errs + 1;
        end
    end
    endtask

    task alloc(input [31:0] rdata, input [31:0] exo, input [4:0] wa);
    begin
        @(negedge clk);
        stall = 0; flush = 0;
        mem_rdata_fmt = rdata; mem_ex_out = exo; mem_pc_plus_8 = exo + 32'd8;
        mem_waddr = wa; mem_rd_addr = wa; mem_cp0_raddr = 5'd0; mem_cp0_sel = 3'd0;
        mem_reg_write = 1'b1; mem_cp0_we = 1'b0; mem_is_eret = 1'b0; mem_tlb_op = 3'd0;
        mem_except_req = 1'b0; mem_except_code = 5'd0; mem_except_is_data = 1'b0;
        mem_bd = 1'b0; mem_mem_to_reg = 2'b00;
        @(posedge clk);
        #1 check_parity("alloc");
    end
    endtask

    initial begin
        stall = 0; flush = 0;
        mem_rdata_fmt = 0; mem_ex_out = 0; mem_pc_plus_8 = 0;
        mem_waddr = 0; mem_rd_addr = 0; mem_cp0_raddr = 0; mem_cp0_sel = 0;
        mem_reg_write = 0; mem_cp0_we = 0; mem_is_eret = 0; mem_tlb_op = 0;
        mem_except_req = 0; mem_except_code = 0; mem_except_is_data = 0;
        mem_bd = 0; mem_mem_to_reg = 0;

        #12 rst_n = 1;
        @(negedge clk);
        check_parity("post-reset");

        // Back-to-back allocations, no stall.
        alloc(32'hAAAA0000, 32'h1000, 5'd1);
        alloc(32'hBBBB0000, 32'h1004, 5'd2);
        alloc(32'hCCCC0000, 32'h1008, 5'd3);

        // Stall: hold outputs, no new allocate should be visible.
        @(negedge clk);
        stall = 1;
        mem_rdata_fmt = 32'hDEAD0000; mem_ex_out = 32'h2000; mem_waddr = 5'd9;
        @(posedge clk);
        #1 check_parity("stall-hold-1");
        @(negedge clk);
        @(posedge clk);
        #1 check_parity("stall-hold-2");

        // Release stall: next allocate should be visible again.
        alloc(32'hEEEE0000, 32'h3000, 5'd4);

        // Flush: both should bubble immediately.
        @(negedge clk);
        stall = 0; flush = 1;
        mem_rdata_fmt = 32'hFFFF0000; mem_ex_out = 32'h4000; mem_waddr = 5'd5;
        @(posedge clk);
        #1 check_parity("flush");
        if (g_wb_reg_write !== 1'b0 || d_wb_reg_write !== 1'b0) begin
            $display("FAIL flush: expected bubble (reg_write=0), golden=%b dut=%b",
                      g_wb_reg_write, d_wb_reg_write);
            errs = errs + 1;
        end

        // Resume normal allocation after flush.
        @(negedge clk);
        flush = 0;
        alloc(32'h11110000, 32'h5000, 5'd6);
        alloc(32'h22220000, 32'h5004, 5'd7);

        // Exception bundle propagation.
        @(negedge clk);
        stall = 0; flush = 0;
        mem_rdata_fmt = 32'h0; mem_ex_out = 32'h6000; mem_pc_plus_8 = 32'h6008;
        mem_waddr = 5'd0; mem_rd_addr = 5'd0; mem_reg_write = 1'b0;
        mem_except_req = 1'b1; mem_except_code = 5'h04; mem_except_is_data = 1'b1;
        mem_bd = 1'b1;
        @(posedge clk);
        #1 check_parity("exception");

        @(negedge clk);
        mem_except_req = 1'b0; mem_except_is_data = 1'b0; mem_bd = 1'b0;

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS rob");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #100000 $display("FAIL timeout"); $finish;
    end
endmodule
