`timescale 1ns/1ps

module coh_axi_mem #(
    parameter integer MEM_WORDS = 1024
) (
    input wire clk, input wire rst_n,
    input wire [31:0] awaddr, input wire awvalid, output wire awready,
    input wire [31:0] wdata, input wire [3:0] wstrb, input wire wvalid,
    input wire wlast, output wire wready,
    output reg bvalid, input wire bready, output wire [1:0] bresp,
    input wire [31:0] araddr, input wire [7:0] arlen, input wire arvalid,
    output wire arready, output reg [31:0] rdata, output reg rlast,
    output reg rvalid, input wire rready, output wire [1:0] rresp,
    input wire inject_write_error
);
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] wr_addr;
    reg wr_pending;
    reg rd_pending;
    reg [31:0] rd_addr;
    reg [7:0] rd_count, rd_len;
    integer i;

    assign awready = !wr_pending && !bvalid;
    assign wready  = !bvalid;
    assign arready = !rd_pending && !rvalid && !bvalid;
    assign bresp = inject_write_error ? 2'b10 : 2'b00;
    assign rresp = 2'b00;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'h1000_0000 + i;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid <= 1'b0; rvalid <= 1'b0; rlast <= 1'b0;
            wr_pending <= 1'b0; rd_pending <= 1'b0;
            wr_addr <= 0; rd_addr <= 0; rd_count <= 0; rd_len <= 0;
            rdata <= 0;
        end else begin
            if (awvalid && awready) begin
                wr_addr <= awaddr;
                wr_pending <= 1'b1;
            end
            if (wvalid && wready) begin
                if (wr_pending)
                    mem[wr_addr[31:2] % MEM_WORDS] <=
                        (wstrb[0] ? wdata[7:0]   : mem[wr_addr[31:2] % MEM_WORDS][7:0]) |
                        ((wstrb[1] ? wdata[15:8] : mem[wr_addr[31:2] % MEM_WORDS][15:8]) << 8) |
                        ((wstrb[2] ? wdata[23:16]: mem[wr_addr[31:2] % MEM_WORDS][23:16]) << 16) |
                        ((wstrb[3] ? wdata[31:24]: mem[wr_addr[31:2] % MEM_WORDS][31:24]) << 24);
                else if (awvalid)
                    mem[awaddr[31:2] % MEM_WORDS] <=
                        (wstrb[0] ? wdata[7:0]   : mem[awaddr[31:2] % MEM_WORDS][7:0]) |
                        ((wstrb[1] ? wdata[15:8] : mem[awaddr[31:2] % MEM_WORDS][15:8]) << 8) |
                        ((wstrb[2] ? wdata[23:16]: mem[awaddr[31:2] % MEM_WORDS][23:16]) << 16) |
                        ((wstrb[3] ? wdata[31:24]: mem[awaddr[31:2] % MEM_WORDS][31:24]) << 24);
                wr_pending <= 1'b0;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;

            if (arvalid && arready) begin
                rd_pending <= 1'b1;
                rd_addr <= araddr;
                rd_count <= 0;
                rd_len <= arlen;
            end
            if (rd_pending && !rvalid) begin
                rvalid <= 1'b1;
                rdata <= mem[(rd_addr[31:2] + rd_count) % MEM_WORDS];
                rlast <= (rd_count == rd_len);
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                if (rlast) begin
                    rlast <= 1'b0;
                    rd_pending <= 1'b0;
                end else rd_count <= rd_count + 1'b1;
            end
        end
    end
endmodule

module tb_dcache_coherency;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg req0, we0, req1, we1;
    reg [31:0] addr0, addr1, wd0, wd1;
    reg [3:0] be0, be1;
    wire [31:0] rd0, rd1;
    wire ok0, done0, err0, ce0, ok1, done1, err1, ce1;
    wire sv0, sv1; wire [31:0] sa0, sa1;
    reg inject_write_error1;

    wire [3:0] awid0, awid1; wire [31:0] awaddr0, awaddr1;
    wire [7:0] awlen0, awlen1; wire [2:0] awsize0, awsize1;
    wire [1:0] awburst0, awburst1, awlock0, awlock1;
    wire [3:0] awcache0, awcache1; wire [2:0] awprot0, awprot1;
    wire awvalid0, awvalid1, awready0, awready1;
    wire [31:0] wdata0, wdata1; wire [3:0] wstrb0, wstrb1;
    wire wlast0, wlast1, wvalid0, wvalid1, wready0, wready1;
    wire [3:0] bid0, bid1; wire [1:0] bresp0, bresp1;
    wire bvalid0, bvalid1, bready0, bready1;
    wire [3:0] arid0, arid1; wire [31:0] araddr0, araddr1;
    wire [7:0] arlen0, arlen1; wire [2:0] arsize0, arsize1;
    wire [1:0] arburst0, arburst1, arlock0, arlock1;
    wire [3:0] arcache0, arcache1; wire [2:0] arprot0, arprot1;
    wire arvalid0, arvalid1, arready0, arready1;
    wire [3:0] rid0, rid1; wire [31:0] rdata0, rdata1;
    wire [1:0] rresp0, rresp1; wire rlast0, rlast1, rvalid0, rvalid1, rready0, rready1;

    dcache #(.ENABLE_LEGACY_ADDR_HEURISTIC(1'b0), .ENABLE_COHERENCY(1'b1)) c0 (
        .clk(clk),.rst_n(rst_n),.cpu_req(req0),.cpu_we(we0),.cpu_addr(addr0),.cpu_wdata(wd0),.cpu_be(be0),.cpu_uncacheable(1'b0),.cpu_rdata(rd0),.cpu_addr_ok(),.cpu_data_ok(ok0),.cpu_bus_error(err0),.cpu_cache_error(ce0),
        .cache_op_valid(1'b0),.cache_op(5'd0),.cache_op_addr(32'd0),.cache_op_ready(),.cache_op_done(),.cache_op_error(),.cache_tag_wdata(32'd0),.cache_tag_rdata(),
        .awid(awid0),.awaddr(awaddr0),.awlen(awlen0),.awsize(awsize0),.awburst(awburst0),.awlock(awlock0),.awcache(awcache0),.awprot(awprot0),.awvalid(awvalid0),.awready(awready0),.wdata(wdata0),.wstrb(wstrb0),.wlast(wlast0),.wvalid(wvalid0),.wready(wready0),.bid(bid0),.bresp(bresp0),.bvalid(bvalid0),.bready(bready0),.arid(arid0),.araddr(araddr0),.arlen(arlen0),.arsize(arsize0),.arburst(arburst0),.arlock(arlock0),.arcache(arcache0),.arprot(arprot0),.arvalid(arvalid0),.arready(arready0),.rid(rid0),.rdata(rdata0),.rresp(rresp0),.rlast(rlast0),.rvalid(rvalid0),.rready(rready0),.coh_store_valid(sv0),.coh_store_addr(sa0),.coh_snoop_valid(sv1),.coh_snoop_addr(sa1));
    dcache #(.ENABLE_LEGACY_ADDR_HEURISTIC(1'b0), .ENABLE_COHERENCY(1'b1)) c1 (
        .clk(clk),.rst_n(rst_n),.cpu_req(req1),.cpu_we(we1),.cpu_addr(addr1),.cpu_wdata(wd1),.cpu_be(be1),.cpu_uncacheable(1'b0),.cpu_rdata(rd1),.cpu_addr_ok(),.cpu_data_ok(ok1),.cpu_bus_error(err1),.cpu_cache_error(ce1),
        .cache_op_valid(1'b0),.cache_op(5'd0),.cache_op_addr(32'd0),.cache_op_ready(),.cache_op_done(),.cache_op_error(),.cache_tag_wdata(32'd0),.cache_tag_rdata(),
        .awid(awid1),.awaddr(awaddr1),.awlen(awlen1),.awsize(awsize1),.awburst(awburst1),.awlock(awlock1),.awcache(awcache1),.awprot(awprot1),.awvalid(awvalid1),.awready(awready1),.wdata(wdata1),.wstrb(wstrb1),.wlast(wlast1),.wvalid(wvalid1),.wready(wready1),.bid(bid1),.bresp(bresp1),.bvalid(bvalid1),.bready(bready1),.arid(arid1),.araddr(araddr1),.arlen(arlen1),.arsize(arsize1),.arburst(arburst1),.arlock(arlock1),.arcache(arcache1),.arprot(arprot1),.arvalid(arvalid1),.arready(arready1),.rid(rid1),.rdata(rdata1),.rresp(rresp1),.rlast(rlast1),.rvalid(rvalid1),.rready(rready1),.coh_store_valid(sv1),.coh_store_addr(sa1),.coh_snoop_valid(sv0),.coh_snoop_addr(sa0));

    assign bid0 = 4'd0; assign rid0 = 4'd0;
    assign bid1 = 4'd0; assign rid1 = 4'd0;
    coh_axi_mem m0(.clk(clk),.rst_n(rst_n),.awaddr(awaddr0),.awvalid(awvalid0),.awready(awready0),.wdata(wdata0),.wstrb(wstrb0),.wvalid(wvalid0),.wlast(wlast0),.wready(wready0),.bvalid(bvalid0),.bready(bready0),.bresp(bresp0),.araddr(araddr0),.arlen(arlen0),.arvalid(arvalid0),.arready(arready0),.rdata(rdata0),.rlast(rlast0),.rvalid(rvalid0),.rready(rready0),.rresp(rresp0),.inject_write_error(1'b0));
    coh_axi_mem m1(.clk(clk),.rst_n(rst_n),.awaddr(awaddr1),.awvalid(awvalid1),.awready(awready1),.wdata(wdata1),.wstrb(wstrb1),.wvalid(wvalid1),.wlast(wlast1),.wready(wready1),.bvalid(bvalid1),.bready(bready1),.bresp(bresp1),.araddr(araddr1),.arlen(arlen1),.arvalid(arvalid1),.arready(arready1),.rdata(rdata1),.rlast(rlast1),.rvalid(rvalid1),.rready(rready1),.rresp(rresp1),.inject_write_error(inject_write_error1));

    integer errors = 0; integer notif_count;
    always @(posedge clk) if (sv0 || sv1) notif_count = notif_count + 1;
    // The two AXI endpoints model independent ports into one backing store.
    // Reflect a completed peer write into port 0 at the same visibility edge.
    always @(posedge clk) if (sv1)
        m0.mem[sa1[31:2] % 1024] <= m1.mem[sa1[31:2] % 1024];
    task read0(input [31:0] a, output [31:0] d); begin @(negedge clk); req0=1;we0=0;addr0=a;be0=4'hf; @(posedge clk); while(!ok0) @(posedge clk); d=rd0; @(negedge clk);req0=0; end endtask
    task write1(input [31:0] a,input [31:0] d,input [3:0] b); begin @(negedge clk);req1=1;we1=1;addr1=a;wd1=d;be1=b; @(posedge clk); while(!ok1) @(posedge clk); @(negedge clk);req1=0; end endtask
    reg [31:0] d; integer n;
    initial begin
        req0=0;we0=0;addr0=0;wd0=0;be0=0;req1=0;we1=0;addr1=0;wd1=0;be1=0;inject_write_error1=0;notif_count=0;
        #23 rst_n=1;
        read0(32'h0000_0100,d); if (d !== 32'h1000_0040) errors=errors+1;
        n=notif_count; write1(32'h0000_0104,32'hCAFE_BABE,4'hf);
        if (notif_count !== n+1) begin $display("FAIL no peer notification"); errors=errors+1; end
        read0(32'h0000_0104,d); if (d !== 32'hCAFE_BABE) begin $display("FAIL peer word=%h",d); errors=errors+1; end
        write1(32'h0000_0108,32'h0000_00AA,4'h1);
        read0(32'h0000_0108,d); if (d !== 32'h1000_00AA) begin $display("FAIL partial word=%h",d); errors=errors+1; end
        inject_write_error1=1; n=notif_count; write1(32'h0000_0110,32'hDEAD_BEEF,4'hf);
        if (notif_count !== n) begin $display("FAIL error store notified"); errors=errors+1; end
        inject_write_error1=0;
        if (errors == 0) $display("REGRESSION_TEST_SUCCESS dcache_coherency");
        else $display("REGRESSION_TEST_FAILED dcache_coherency errors=%0d",errors);
        $finish;
    end
endmodule
