// =============================================================================
// tb_icache.v — unit test for the 4-way + tree-PLRU L1 I-cache (read-only).
// Cases: cold miss/refill/hit, intra-line sequential hits, fill 4 ways (no
// evict), 5th tag -> PLRU eviction with MRU-way retained, data integrity.
// A read-only single-outstanding behavioral memory backs the AXI master.
// =============================================================================
`timescale 1ns/1ps

module tb_icache;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg         cpu_req;
    reg  [31:0] cpu_addr;
    wire [31:0] cpu_rdata;
    wire        cpu_addr_ok, cpu_data_ok;

    wire [3:0]  arid; wire [31:0] araddr; wire [7:0] arlen; wire [2:0] arsize;
    wire [1:0]  arburst, arlock; wire [3:0] arcache; wire [2:0] arprot;
    wire        arvalid; wire arready;
    wire [3:0]  rid; wire [31:0] rdata; wire [1:0] rresp; wire rlast, rvalid; wire rready;

    icache dut (
        .clk(clk),.rst_n(rst_n),
        .cpu_req(cpu_req),.cpu_addr(cpu_addr),.cpu_rdata(cpu_rdata),
        .cpu_addr_ok(cpu_addr_ok),.cpu_data_ok(cpu_data_ok),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .arlock(arlock),.arcache(arcache),.arprot(arprot),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready)
    );

    // read-only behavioral memory (1MB). content = addr-based pattern.
    parameter MEM_WORDS = 262144;
    function [31:0] memval(input [31:0] byte_addr);
        memval = 32'hC0DE_0000 | (byte_addr[17:2]);
    endfunction

    integer ar_count;
    reg [31:0] ar_addr_l; reg [7:0] ar_beat; reg ar_active;
    reg r_arready, r_rvalid, r_rlast; reg [31:0] r_rdata; reg [3:0] r_rid;
    assign arready=r_arready; assign rvalid=r_rvalid; assign rlast=r_rlast;
    assign rdata=r_rdata; assign rresp=2'b00; assign rid=r_rid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_arready<=1; r_rvalid<=0; r_rlast<=0; ar_active<=0; ar_beat<=0;
            ar_count<=0; r_rid<=0; r_rdata<=0;
        end else begin
            if (arvalid && r_arready && !ar_active) begin
                ar_addr_l<=araddr; ar_active<=1; ar_beat<=0; r_arready<=0; ar_count<=ar_count+1;
            end
            if (ar_active && !r_rvalid) begin
                r_rvalid<=1; r_rid<=arid;
                r_rdata<=memval(((ar_addr_l & ~32'h1F) + (ar_beat<<2)));
                r_rlast<=(ar_beat==arlen);
            end
            if (r_rvalid && rready) begin
                if (r_rlast) begin ar_active<=0; r_rlast<=0; r_arready<=1; end
                else ar_beat<=ar_beat+1;
                r_rvalid<=0;
            end
        end
    end

    integer errs=0;
    reg [31:0] got;

    // I-fetch: hold cpu_req until cpu_data_ok (mirrors the pipeline)
    task ifetch(input [31:0] addr, output [31:0] data);
    begin
        @(negedge clk);
        cpu_req=1; cpu_addr=addr;
        @(posedge clk); while(!cpu_data_ok) @(posedge clk);
        data=cpu_rdata;
        @(negedge clk); cpu_req=0;
        @(negedge clk);
    end endtask

    task check(input [31:0] addr);
        reg [31:0] d;
    begin
        ifetch(addr, d);
        if (d !== memval(addr)) begin
            $display("FAIL data @%h got=%h exp=%h", addr, d, memval(addr)); errs=errs+1;
        end
    end endtask

    integer c_ar;
    localparam [31:0] WSTEP = 32'h0000_0800; // 2KB: same set, next tag

    initial begin
        cpu_req=0; cpu_addr=0;
        #23 rst_n=1; @(negedge clk);

        // T1: cold miss -> refill -> hit
        c_ar=ar_count;
        check(32'h0000_0040);
        if (ar_count!==c_ar+1) begin $display("FAIL T1 no refill"); errs=errs+1; end
        c_ar=ar_count; check(32'h0000_0040);   // hit, no AR
        if (ar_count!==c_ar) begin $display("FAIL T1 AR on hit"); errs=errs+1; end

        // T2: sequential fetch within same line -> hits, only the initial refill
        c_ar=ar_count;
        check(32'h0000_0100); // miss (new line) -> 1 AR
        check(32'h0000_0104);
        check(32'h0000_0108);
        check(32'h0000_010C);
        if (ar_count!==c_ar+1) begin $display("FAIL T2 extra AR intra-line (%0d)",ar_count-c_ar); errs=errs+1; end

        // T3: fill all 4 ways of one set (index from 0x2000), 4 distinct tags
        check(32'h0000_2000);
        check(32'h0000_2000+WSTEP);
        check(32'h0000_2000+2*WSTEP);
        check(32'h0000_2000+3*WSTEP);
        c_ar=ar_count;                         // all resident now
        check(32'h0000_2000);
        check(32'h0000_2000+WSTEP);
        check(32'h0000_2000+2*WSTEP);
        check(32'h0000_2000+3*WSTEP);
        if (ar_count!==c_ar) begin $display("FAIL T3 refetch after 4-way fill caused AR"); errs=errs+1; end

        // T4: PLRU order. Fresh set 0x4000. Access A,B,C,D then A (A=MRU).
        // Bring E -> evict PLRU victim (not A). A must still hit (no AR).
        check(32'h0000_4000);        // A
        check(32'h0000_4000+WSTEP);  // B
        check(32'h0000_4000+2*WSTEP);// C
        check(32'h0000_4000+3*WSTEP);// D
        check(32'h0000_4000);        // touch A -> MRU
        check(32'h0000_4000+4*WSTEP);// E -> eviction
        c_ar=ar_count; check(32'h0000_4000);   // A should still be resident
        if (ar_count!==c_ar) begin $display("FAIL T4 MRU way A evicted"); errs=errs+1; end

        #50;
        if (errs==0) $display("REGRESSION_TEST_SUCCESS icache");
        else         $display("REGRESSION_TEST_FAIL errs=%0d",errs);
        $finish;
    end
    initial begin #500000 $display("FAIL timeout"); $finish; end
endmodule
