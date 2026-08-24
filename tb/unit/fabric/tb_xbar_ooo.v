// Bounded AXI response reordering test.
// A single multi-outstanding slave returns four different IDs in reverse order.
`timescale 1ns/1ps
`include "soc_config.vh"

module tb_xbar_ooo;
    localparam N_M=1, N_S=1, N_OT=4, IDW=4, AW=32, DW=32, QW=4;
    reg clk=0, rst_n=0; always #5 clk=~clk;
    reg [N_M-1:0] m_enable=1'b1;

    reg [IDW-1:0] arid=0; reg [AW-1:0] araddr=0;
    reg arvalid=0, rready=1;
    wire arready, rvalid, rlast;
    wire [IDW-1:0] rid; wire [DW-1:0] rdata; wire [1:0] rresp;
    reg [IDW-1:0] awid_m=0; reg [AW-1:0] awaddr_m=0; reg awvalid_m=0;
    wire awready_m; reg [DW-1:0] wdata_m=0; reg [3:0] wstrb_m=4'hf;
    reg wlast_m=0, wvalid_m=0, bready_m=1; wire wready_m, bvalid_m;
    wire [IDW-1:0] bid_m; wire [1:0] bresp_m;

    wire [IDW-1:0] s_arid; wire [AW-1:0] s_araddr; wire [7:0] s_arlen;
    wire [2:0] s_arsize, s_arprot; wire [1:0] s_arburst, s_arlock;
    wire [3:0] s_arcache; wire s_arvalid; reg s_arready=1;
    wire [IDW-1:0] s_rid; wire [DW-1:0] s_rdata; wire [1:0] s_rresp;
    wire s_rlast, s_rvalid; wire s_rready;

    wire [IDW-1:0] s_awid; wire [AW-1:0] s_awaddr; wire [7:0] s_awlen;
    wire [2:0] s_awsize, s_awprot; wire [1:0] s_awburst, s_awlock;
    wire [3:0] s_awcache; wire s_awvalid; reg s_awready=1;
    wire [DW-1:0] s_wdata; wire [3:0] s_wstrb; wire s_wlast, s_wvalid;
    reg s_wready=1; reg [IDW-1:0] s_bid; reg [1:0] s_bresp;
    reg s_bvalid; wire s_bready;

    axi_crossbar #(.N_M(N_M),.N_S(N_S),.N_OT(N_OT)) dut (
        .clk(clk),.rst_n(rst_n),.m_enable(m_enable),
        .m_awid(awid_m),.m_awaddr(awaddr_m),.m_awlen(0),.m_awsize(0),.m_awburst(0),
        .m_awlock(0),.m_awcache(0),.m_awprot(0),.m_awqos(0),.m_awvalid(awvalid_m),.m_awready(awready_m),
        .m_wdata(wdata_m),.m_wstrb(wstrb_m),.m_wlast(wlast_m),.m_wvalid(wvalid_m),.m_wready(wready_m),.m_bid(bid_m),.m_bresp(bresp_m),.m_bvalid(bvalid_m),.m_bready(bready_m),
        .m_arid(arid),.m_araddr(araddr),.m_arlen(0),.m_arsize(3'b010),.m_arburst(2'b01),
        .m_arlock(0),.m_arcache(0),.m_arprot(0),.m_arqos(0),.m_arvalid(arvalid),.m_arready(arready),
        .m_rid(rid),.m_rdata(rdata),.m_rresp(rresp),.m_rlast(rlast),.m_rvalid(rvalid),.m_rready(rready),
        .s_awid(s_awid),.s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),
        .s_awlock(s_awlock),.s_awcache(s_awcache),.s_awprot(s_awprot),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bid(s_bid),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_arid(s_arid),.s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),
        .s_arlock(s_arlock),.s_arcache(s_arcache),.s_arprot(s_arprot),.s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rid(s_rid),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready)
    );

    reg [IDW-1:0] q_id[0:3]; reg [AW-1:0] q_addr[0:3];
    integer q_tail=0, q_count=0, resp_pos=0;
    integer issued=0, received=0, errs=0;
    integer resp_order[0:3];
    reg [IDW-1:0] bq_id[0:3];
    integer bq_tail=0, bq_count=0, b_sent=0;
    integer b_order[0:3], b_pos=0;
    reg b_responding=0;
    reg responding=0;
    assign s_rid = responding ? q_id[resp_order[resp_pos]] : 0;
    assign s_rdata = responding ? q_addr[resp_order[resp_pos]] : 0;
    assign s_rresp = 0;
    assign s_rlast = responding;
    assign s_rvalid = responding;
    always @(*) begin
        if (b_responding) begin s_bvalid = 1'b1; s_bid = bq_id[b_order[b_pos]]; s_bresp = 2'b00; end
        else begin s_bvalid = 1'b0; s_bid = 0; s_bresp = 0; end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_tail<=0; q_count<=0; responding<=0; resp_pos<=0;
            bq_tail<=0; bq_count<=0; b_responding<=0; b_pos<=0;
        end else begin
            if (s_arvalid && s_arready) begin
                q_id[q_tail] <= s_arid; q_addr[q_tail] <= s_araddr;
                q_tail <= (q_tail+1)%4; q_count <= q_count+1;
                if (q_count==3) begin responding<=1; resp_pos<=0; end
            end
            if (s_rvalid && s_rready) begin
                if (resp_pos==3) responding<=0;
                else resp_pos<=resp_pos+1;
            end
            if (s_awvalid && s_awready) begin
                bq_id[bq_tail] <= s_awid; bq_tail <= (bq_tail+1)%4; bq_count <= bq_count+1;
            end
            if (s_wvalid && s_wready && s_wlast) begin
                b_sent <= b_sent+1;
                if (b_sent==3) begin b_responding<=1; b_pos<=0; end
            end
            if (s_bvalid && s_bready) begin
                if (b_pos==3) b_responding<=0;
                else b_pos<=b_pos+1;
            end
        end
    end

    initial begin
        resp_order[0]=3; resp_order[1]=2; resp_order[2]=1; resp_order[3]=0;
        b_order[0]=3; b_order[1]=2; b_order[2]=1; b_order[3]=0;
        #23 rst_n=1; @(negedge clk);
        rready=0;
        arid=1; araddr=32'h10; arvalid=1;
        for (issued=0; issued<4; issued=issued+1) begin
            @(posedge clk);
            while (!arready) @(posedge clk);
            @(negedge clk);
            if (issued<3) begin arid=arid+1; araddr=araddr+4; end
            else arvalid=0;
        end
        rready=1;
        repeat (80) begin
            @(posedge clk);
            if (rvalid && rready) begin
                received=received+1;
                if (rid !== (5-received)) begin
                    $display("FAIL: response %0d RID=%h expected=%h",received,rid,5-received); errs=errs+1;
                end
                if (rdata !== (32'h10 + ((4-received)*4))) begin
                    $display("FAIL: response %0d data=%h",received,rdata); errs=errs+1;
                end
            end
        end
        if (issued!=4 || received!=4) begin
            $display("FAIL: issued=%0d received=%0d",issued,received); errs=errs+1;
        end
        // Same-ID ordering: ID 3 completes before ID 2, but each ID's two
        // responses must retain issue order.
        rst_n=0; repeat (2) @(posedge clk); rst_n=1;
        resp_order[0]=2; resp_order[1]=3; resp_order[2]=0; resp_order[3]=1;
        @(negedge clk); arid=2; araddr=32'h20; arvalid=1; rready=0;
        for (issued=0; issued<4; issued=issued+1) begin
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk);
            if (issued==0) begin arid=2; araddr=32'h24; end
            else if (issued==1) begin arid=3; araddr=32'h28; end
            else if (issued==2) begin arid=3; araddr=32'h2c; end
            else arvalid=0;
        end
        rready=1; received=0;
        repeat (80) begin
            @(posedge clk);
            if (rvalid && rready) begin
                received=received+1;
                if (received==1 && (rid!==3 || rdata!==32'h28)) errs=errs+1;
                if (received==2 && (rid!==3 || rdata!==32'h2c)) errs=errs+1;
                if (received==3 && (rid!==2 || rdata!==32'h20)) errs=errs+1;
                if (received==4 && (rid!==2 || rdata!==32'h24)) errs=errs+1;
            end
        end
        if (received!=4) begin $display("FAIL: same-ID responses=%0d",received); errs=errs+1; end

        rst_n=0; repeat (2) @(posedge clk); rst_n=1;
        b_order[0]=3; b_order[1]=2; b_order[2]=1; b_order[3]=0;
        @(negedge clk); awid_m=1; awaddr_m=32'h100; awvalid_m=1;
        for (issued=0; issued<4; issued=issued+1) begin
            @(posedge clk); while (!awready_m) @(posedge clk);
            @(negedge clk);
            if (issued<3) begin awid_m=awid_m+1; awaddr_m=awaddr_m+4; end
            else awvalid_m=0;
        end
        @(negedge clk); wdata_m=32'h100; wlast_m=1; wvalid_m=1; bready_m=0;
        for (received=0; received<4; received=received+1) begin
            @(posedge clk); while (!wready_m) @(posedge clk);
            @(negedge clk);
            if (received<3) begin wdata_m=wdata_m+4; end
            else begin wvalid_m=0; wlast_m=0; end
        end
        bready_m=1;
        received=0;
        repeat (80) begin
            @(posedge clk);
            if (bvalid_m && bready_m) begin
                received=received+1;
                if (bid_m !== (5-received)) begin
                    $display("FAIL: B response %0d BID=%h expected=%h",received,bid_m,5-received); errs=errs+1;
                end
            end
        end
        if (received!=4) begin $display("FAIL: B responses=%0d",received); errs=errs+1; end
        if (errs==0) $display("REGRESSION_TEST_SUCCESS xbar_ooo");
        else $display("REGRESSION_TEST_FAIL errs=%0d",errs);
        $finish;
    end
    initial begin #300000 $display("FAIL timeout"); $finish; end
endmodule
