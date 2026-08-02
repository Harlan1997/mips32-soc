// Product-boot I-cache CacheErr contract.
// The first physical Boot ROM line receives one AXI SLVERR. The product
// CacheErr vector is fetched through its kseg1 physical alias, executes ERET,
// and retries the original line without an injected error.
`timescale 1ns/1ps

module tb_mips_core_icache_product_error;
    localparam [31:0] BOOT_VA   = 32'hBFC0_0000;
    localparam [31:0] VECTOR_VA = 32'hBFC0_0100;
    localparam [31:0] BOOT_PA   = 32'h1FC0_0000;
    localparam [31:0] VECTOR_PA = 32'h1FC0_0100;
    localparam [31:0] ERET_INSN = 32'h4200_0018;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire [3:0]  inst_arid;
    wire [31:0] inst_araddr;
    wire [7:0]  inst_arlen;
    wire [2:0]  inst_arsize;
    wire [1:0]  inst_arburst, inst_arlock;
    wire [3:0]  inst_arcache;
    wire [2:0]  inst_arprot;
    wire        inst_arvalid;
    wire        inst_arready;
    reg  [3:0]  inst_rid = 4'd0;
    reg  [31:0] inst_rdata = 32'd0;
    reg  [1:0]  inst_rresp = 2'b00;
    reg         inst_rlast = 1'b0;
    reg         inst_rvalid = 1'b0;
    wire        inst_rready;

    wire [3:0]  inst_awid;
    wire [31:0] inst_awaddr;
    wire [7:0]  inst_awlen;
    wire [2:0]  inst_awsize;
    wire [1:0]  inst_awburst, inst_awlock;
    wire [3:0]  inst_awcache;
    wire [2:0]  inst_awprot;
    wire        inst_awvalid;
    wire [31:0] inst_wdata;
    wire [3:0]  inst_wstrb;
    wire        inst_wlast, inst_wvalid, inst_bready;
    wire [3:0]  inst_bid = 4'd0;
    wire [1:0]  inst_bresp = 2'b00;
    wire        inst_bvalid = 1'b0;
    wire        inst_wready = 1'b1;
    wire        inst_awready = 1'b1;

    wire [3:0]  data_awid;
    wire [31:0] data_awaddr;
    wire [7:0]  data_awlen;
    wire [2:0]  data_awsize;
    wire [1:0]  data_awburst, data_awlock;
    wire [3:0]  data_awcache;
    wire [2:0]  data_awprot;
    wire        data_awvalid;
    wire        data_awready = 1'b1;
    wire [31:0] data_wdata;
    wire [3:0]  data_wstrb;
    wire        data_wlast, data_wvalid;
    wire        data_wready = 1'b1;
    wire [3:0]  data_bid = 4'd0;
    wire [1:0]  data_bresp = 2'b00;
    wire        data_bvalid = 1'b0;
    wire        data_bready;
    wire [3:0]  data_arid;
    wire [31:0] data_araddr;
    wire [7:0]  data_arlen;
    wire [2:0]  data_arsize;
    wire [1:0]  data_arburst, data_arlock;
    wire [3:0]  data_arcache;
    wire [2:0]  data_arprot;
    wire        data_arvalid;
    wire        data_arready = 1'b1;
    wire [3:0]  data_rid = 4'd0;
    wire [31:0] data_rdata = 32'd0;
    wire [1:0]  data_rresp = 2'b00;
    wire        data_rlast = 1'b1;
    wire        data_rvalid = 1'b0;
    wire        data_rready;
    wire        debug_stall, debug_flush;

    reg         i_active;
    reg         i_error;
    reg         boot_error_used;
    reg [31:0]  i_base;
    reg [2:0]   i_beat;
    integer     ar_count;
    integer     boot_ar_count;
    integer     vector_ar_count;
    integer     cycles;

    reg boot_ar_seen;
    reg vector_ar_seen;
    reg cache_error_seen;
    reg cp0_error_seen;
    reg precise_errorepc_seen;
    reg vector_pc_seen;
    reg eret_seen;
    reg erl_clear_seen;
    reg boot_retry_seen;

    function [31:0] program_word(input [31:0] addr);
        begin
            program_word = (addr == VECTOR_PA) ? ERET_INSN : 32'h0000_0000;
        end
    endfunction

    assign inst_arready = !i_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_active        <= 1'b0;
            i_error         <= 1'b0;
            boot_error_used <= 1'b0;
            i_base          <= 32'd0;
            i_beat          <= 3'd0;
            inst_rvalid     <= 1'b0;
            inst_rlast      <= 1'b0;
            inst_rdata      <= 32'd0;
            inst_rresp      <= 2'b00;
            ar_count        <= 0;
            boot_ar_count   <= 0;
            vector_ar_count <= 0;
        end else begin
            if (inst_arvalid && inst_arready && !i_active) begin
                i_active <= 1'b1;
                i_error  <= !boot_error_used && (inst_araddr == BOOT_PA);
                if (inst_araddr == BOOT_PA) begin
                    boot_ar_count <= boot_ar_count + 1;
                end
                if (inst_araddr == VECTOR_PA)
                    vector_ar_count <= vector_ar_count + 1;
                if (!boot_error_used && (inst_araddr == BOOT_PA))
                    boot_error_used <= 1'b1;
                i_base   <= inst_araddr;
                i_beat   <= 3'd0;
                ar_count <= ar_count + 1;
            end
            if (i_active && !inst_rvalid) begin
                inst_rvalid <= 1'b1;
                inst_rdata  <= program_word(i_base + (i_beat << 2));
                inst_rresp  <= i_error ? 2'b10 : 2'b00;
                inst_rlast  <= (i_beat == 3'd7);
            end
            if (inst_rvalid && inst_rready) begin
                inst_rvalid <= 1'b0;
                if (inst_rlast) begin
                    i_active   <= 1'b0;
                    i_error    <= 1'b0;
                    inst_rlast <= 1'b0;
                end else begin
                    i_beat <= i_beat + 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_ar_seen          <= 1'b0;
            vector_ar_seen        <= 1'b0;
            cache_error_seen      <= 1'b0;
            cp0_error_seen        <= 1'b0;
            precise_errorepc_seen <= 1'b0;
            vector_pc_seen        <= 1'b0;
            eret_seen             <= 1'b0;
            erl_clear_seen        <= 1'b0;
            boot_retry_seen       <= 1'b0;
            cycles                <= 0;
        end else begin
            cycles <= cycles + 1;
            if (inst_arvalid && inst_arready && (inst_araddr == BOOT_PA))
                boot_ar_seen <= 1'b1;
            if (inst_arvalid && inst_arready && (inst_araddr == VECTOR_PA))
                vector_ar_seen <= 1'b1;
            if (inst_arvalid && inst_arready && (inst_araddr == BOOT_PA) &&
                boot_error_used)
                boot_retry_seen <= 1'b1;
            if (u_core.u_icache.cpu_cache_error === 1'b1)
                cache_error_seen <= 1'b1;
            if (u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] === 5'h1e &&
                u_core.u_cpu.u_mips_cp0.cp0_status[2] === 1'b1)
                cp0_error_seen <= 1'b1;
            if (cp0_error_seen &&
                u_core.u_cpu.u_mips_cp0.cp0_errorepc === BOOT_VA)
                precise_errorepc_seen <= 1'b1;
            if (u_core.u_cpu.u_mips_if_stage.pc == VECTOR_VA)
                vector_pc_seen <= 1'b1;
            if (u_core.u_cpu.wb_is_eret === 1'b1)
                eret_seen <= 1'b1;
            if (eret_seen && u_core.u_cpu.u_mips_cp0.cp0_status[2] === 1'b0)
                erl_clear_seen <= 1'b1;

            if (boot_ar_seen && vector_ar_seen && cache_error_seen &&
                cp0_error_seen && precise_errorepc_seen && vector_pc_seen &&
                eret_seen && erl_clear_seen && boot_retry_seen) begin
                if (vector_ar_count != 1)
                    fail("product CacheErr vector was fetched more than once");
                $display("REGRESSION_TEST_SUCCESS mips_core_icache_product_error ar_count=%0d boot_ar_count=%0d vector_ar_count=%0d",
                         ar_count, boot_ar_count, vector_ar_count);
                $finish;
            end
            if (cycles > 100000) begin
                $display("REGRESSION_TEST_FAIL mips_core_icache_product_error timeout boot_ar=%b vector_ar=%b cache=%b cp0=%b epc=%b vector_pc=%b eret=%b erl_clear=%b retry=%b ar_count=%0d pc=%h status=%h cause=%h errorepc=%h",
                         boot_ar_seen, vector_ar_seen, cache_error_seen,
                         cp0_error_seen, precise_errorepc_seen, vector_pc_seen,
                         eret_seen, erl_clear_seen, boot_retry_seen, ar_count,
                         u_core.u_cpu.u_mips_if_stage.pc,
                         u_core.u_cpu.u_mips_cp0.cp0_status,
                         u_core.u_cpu.u_mips_cp0.cp0_cause,
                         u_core.u_cpu.u_mips_cp0.cp0_errorepc);
                $finish;
            end
        end
    end

    task fail;
        input [255:0] message;
        begin
            $display("REGRESSION_TEST_FAIL %0s", message);
            $finish;
        end
    endtask

    mips_core u_core (
        .clk(clk), .rst_n(rst_n), .ext_int(6'd0),
        .inst_awid(inst_awid), .inst_awaddr(inst_awaddr), .inst_awlen(inst_awlen),
        .inst_awsize(inst_awsize), .inst_awburst(inst_awburst), .inst_awlock(inst_awlock),
        .inst_awcache(inst_awcache), .inst_awprot(inst_awprot), .inst_awvalid(inst_awvalid),
        .inst_awready(inst_awready), .inst_wdata(inst_wdata), .inst_wstrb(inst_wstrb),
        .inst_wlast(inst_wlast), .inst_wvalid(inst_wvalid), .inst_wready(inst_wready),
        .inst_bid(inst_bid), .inst_bresp(inst_bresp), .inst_bvalid(inst_bvalid),
        .inst_bready(inst_bready), .inst_arid(inst_arid), .inst_araddr(inst_araddr),
        .inst_arlen(inst_arlen), .inst_arsize(inst_arsize), .inst_arburst(inst_arburst),
        .inst_arlock(inst_arlock), .inst_arcache(inst_arcache), .inst_arprot(inst_arprot),
        .inst_arvalid(inst_arvalid), .inst_arready(inst_arready), .inst_rid(inst_rid),
        .inst_rdata(inst_rdata), .inst_rresp(inst_rresp), .inst_rlast(inst_rlast),
        .inst_rvalid(inst_rvalid), .inst_rready(inst_rready),
        .data_awid(data_awid), .data_awaddr(data_awaddr), .data_awlen(data_awlen),
        .data_awsize(data_awsize), .data_awburst(data_awburst), .data_awlock(data_awlock),
        .data_awcache(data_awcache), .data_awprot(data_awprot), .data_awvalid(data_awvalid),
        .data_awready(data_awready), .data_wdata(data_wdata), .data_wstrb(data_wstrb),
        .data_wlast(data_wlast), .data_wvalid(data_wvalid), .data_wready(data_wready),
        .data_bid(data_bid), .data_bresp(data_bresp), .data_bvalid(data_bvalid),
        .data_bready(data_bready), .data_arid(data_arid), .data_araddr(data_araddr),
        .data_arlen(data_arlen), .data_arsize(data_arsize), .data_arburst(data_arburst),
        .data_arlock(data_arlock), .data_arcache(data_arcache), .data_arprot(data_arprot),
        .data_arvalid(data_arvalid), .data_arready(data_arready), .data_rid(data_rid),
        .data_rdata(data_rdata), .data_rresp(data_rresp), .data_rlast(data_rlast),
        .data_rvalid(data_rvalid), .data_rready(data_rready),
        .debug_stall(debug_stall), .debug_flush(debug_flush)
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
