// Directed CPU contract test for MIPS CacheErr (ExcCode 30).
// A single data-cache sideband pulse is injected on a load. The test checks
// the distinct error vector and CP0 ERL/ErrorEPC state; ordinary DBE is not
// used for this stimulus.
`timescale 1ns/1ps

module tb_mips_cpu_cacheerr;
    reg clk;
    reg rst_n;

    wire        inst_req;
    wire [31:0] inst_addr;
    wire [31:0] inst_rdata;
    wire        data_req;
    wire        data_we;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_be;
    wire [31:0] data_rdata;
    wire        debug_stall;
    wire        debug_flush;

    wire inst_addr_ok = 1'b1;
    wire inst_data_ok = 1'b1;
    wire inst_bus_error = 1'b0;
    wire inst_cache_error = 1'b0;
    wire data_addr_ok = 1'b1;
    wire data_data_ok = 1'b1;
    wire data_bus_error = 1'b0;

    reg data_cache_error_seen;
    wire data_cache_error = data_req && !data_we && !data_cache_error_seen;

    reg [31:0] imem [0:1023];
    reg [31:0] fetch_addr_q;
    integer i;

    // Model the I-cache contract: data_ok returns the prior request while the
    // CPU presents the look-ahead address for the next request.
    assign inst_rdata = imem[fetch_addr_q[11:2]];
    assign data_rdata = 32'hCAFE_0001;

    mips_cpu u_cpu (
        .clk             (clk),
        .rst_n           (rst_n),
        .inst_req        (inst_req),
        .inst_addr       (inst_addr),
        .inst_addr_ok    (inst_addr_ok),
        .inst_data_ok    (inst_data_ok),
        .inst_bus_error  (inst_bus_error),
        .inst_cache_error(inst_cache_error),
        .inst_rdata      (inst_rdata),
        .data_req        (data_req),
        .data_we         (data_we),
        .data_addr       (data_addr),
        .data_wdata      (data_wdata),
        .data_be         (data_be),
        .data_uncacheable(),
        .data_addr_ok    (data_addr_ok),
        .data_data_ok    (data_data_ok),
        .data_bus_error  (data_bus_error),
        .data_cache_error(data_cache_error),
        .data_rdata      (data_rdata),
        .ext_int         (6'd0),
        .debug_stall     (debug_stall),
        .debug_flush     (debug_flush)
    );

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_cache_error_seen <= 1'b0;
        else if (data_cache_error)
            data_cache_error_seen <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fetch_addr_q <= 32'd0;
        else
            fetch_addr_q <= inst_addr;
    end

    reg vector_seen;
    always @(posedge clk) begin
        if (rst_n && inst_addr == 32'h0000_0100)
            vector_seen <= 1'b1;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        data_cache_error_seen = 1'b0;
        vector_seen = 1'b0;
        for (i = 0; i < 1024; i = i + 1)
            imem[i] = 32'd0;

        // Product reset entry (BFC0_0000), mapped by low address bits.
        imem[32'h000/4] = 32'h2401_0000; // addiu $1,$zero,0: clear BEV/ERL
        imem[32'h004/4] = 32'h4081_6000; // mtc0  $1,$12 (Status)
        imem[32'h008/4] = 32'h0000_0000; // nop (allow CP0 write to retire)
        imem[32'h00c/4] = 32'h3c02_a000; // lui  $2,0xa000 (kseg1 avoids TLB)
        imem[32'h010/4] = 32'h8c43_0000; // lw   $3,0($2): inject CacheErr
        imem[32'h014/4] = 32'h0000_0000;
        // CacheErr vector is EBase+0x100 = 0x8000_0100 when BEV=0.
        imem[32'h100/4] = 32'h0000_0000;

        #17 rst_n = 1'b1;
        #600;

        if (!data_cache_error_seen) begin
            $display("FAIL cacheerr stimulus was not accepted pc=%h inst=%h",
                     inst_addr, inst_rdata);
        end else if (!vector_seen) begin
            $display("FAIL CacheErr did not redirect to EBase+0x100 (addr=%h cause=%h status=%h errorepc=%h)",
                     inst_addr, u_cpu.u_mips_cp0.cp0_cause[6:2],
                     u_cpu.u_mips_cp0.cp0_status, u_cpu.u_mips_cp0.cp0_errorepc);
        end else if (u_cpu.u_mips_cp0.cp0_cause[6:2] !== 5'h1E) begin
            $display("FAIL Cause.ExcCode=%h expected 1e", u_cpu.u_mips_cp0.cp0_cause[6:2]);
        end else if (u_cpu.u_mips_cp0.cp0_status[2] !== 1'b1 ||
                     u_cpu.u_mips_cp0.cp0_status[1] !== 1'b0) begin
            $display("FAIL Status ERL/EXL=%b/%b expected 1/0",
                     u_cpu.u_mips_cp0.cp0_status[2], u_cpu.u_mips_cp0.cp0_status[1]);
        end else if (u_cpu.u_mips_cp0.cp0_errorepc !== 32'hBFC0_0010) begin
            $display("FAIL ErrorEPC=%h expected bfc00010", u_cpu.u_mips_cp0.cp0_errorepc);
        end else begin
            $display("REGRESSION_TEST_SUCCESS mips_cpu_cacheerr");
        end
        $finish;
    end

    initial begin
        #5000;
        $display("FAIL timeout");
        $finish;
    end
endmodule
