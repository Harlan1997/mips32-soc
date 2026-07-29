// =============================================================================
// tb_xbar_multi_ot.v — Phase B multi-outstanding depth test for axi_crossbar.
// S0 is a MULTI-outstanding slave (accepts up to Q ARs before responding).
//  T1: one master fires 4 back-to-back ARs; crossbar must accept all 4 (up to
//      N_OT) before the first response completes -> proves boundary depth.
//  T2: two masters to two DIFFERENT slaves overlap (both have AR accepted and
//      R in flight simultaneously) -> proves cross-slave concurrency.
// =============================================================================
`timescale 1ns/1ps
`include "soc_config.vh"

module tb_xbar_multi_ot;
    localparam N_M=3, N_S=2, N_OT=4, IDW=4, AW=32, DW=32, QW=4;
    reg clk=0, rst_n=0; always #5 clk=~clk;
    reg [N_M-1:0] m_enable;

    reg  [AW-1:0] araddr[0:N_M-1]; reg [IDW-1:0] arid[0:N_M-1];
    reg  [N_M-1:0] arvalid, rready;
    wire [N_M-1:0] arready, rvalid, rlast;

    wire [N_M*IDW-1:0] arid_f; wire [N_M*AW-1:0] araddr_f; wire [N_M*QW-1:0] arqos_f;
    wire [N_M*8-1:0] arlen_f; wire [N_M*3-1:0] arsize_f, arprot_f;
    wire [N_M*2-1:0] arburst_f, arlock_f; wire [N_M*4-1:0] arcache_f;
    genvar gi;
    generate for (gi=0;gi<N_M;gi=gi+1) begin: g_flat
        assign arid_f[gi*IDW+:IDW]=arid[gi]; assign araddr_f[gi*AW+:AW]=araddr[gi];
        assign arqos_f[gi*QW+:QW]=4'd0; assign arlen_f[gi*8+:8]=8'd0;
        assign arsize_f[gi*3+:3]=3'b010; assign arburst_f[gi*2+:2]=2'b01;
        assign arlock_f[gi*2+:2]=2'b0; assign arcache_f[gi*4+:4]=4'b0; assign arprot_f[gi*3+:3]=3'b0;
    end endgenerate
    wire [N_M*IDW-1:0] rid_f; wire [N_M*DW-1:0] rdata_f; wire [N_M*2-1:0] rresp_f;

    wire [N_S*IDW-1:0] s_arid, s_rid; wire [N_S*AW-1:0] s_araddr; wire [N_S*8-1:0] s_arlen;
    wire [N_S*3-1:0] s_arsize, s_arprot; wire [N_S*2-1:0] s_arburst, s_arlock, s_rresp;
    wire [N_S*4-1:0] s_arcache; wire [N_S*DW-1:0] s_rdata;
    wire [N_S-1:0] s_arvalid, s_arready, s_rlast, s_rvalid, s_rready;
    wire [N_S*IDW-1:0] s_awid, s_bid; wire [N_S*AW-1:0] s_awaddr; wire [N_S*8-1:0] s_awlen;
    wire [N_S*3-1:0] s_awsize, s_awprot; wire [N_S*2-1:0] s_awburst, s_awlock, s_bresp;
    wire [N_S*4-1:0] s_awcache, s_wstrb; wire [N_S*DW-1:0] s_wdata;
    wire [N_S-1:0] s_awvalid, s_wlast, s_wvalid;
    wire [N_S-1:0] s_awready={N_S{1'b1}}, s_wready={N_S{1'b1}}, s_bvalid={N_S{1'b0}}, s_bready;

    axi_crossbar #(.N_M(N_M),.N_S(N_S),.N_OT(N_OT)) dut (
        .clk(clk),.rst_n(rst_n),.m_enable(m_enable),
        .m_awid({N_M*IDW{1'b0}}),.m_awaddr({N_M*AW{1'b0}}),.m_awlen({N_M*8{1'b0}}),
        .m_awsize({N_M*3{1'b0}}),.m_awburst({N_M*2{1'b0}}),.m_awlock({N_M*2{1'b0}}),
        .m_awcache({N_M*4{1'b0}}),.m_awprot({N_M*3{1'b0}}),.m_awqos({N_M*QW{1'b0}}),
        .m_awvalid({N_M{1'b0}}),.m_awready(),
        .m_wdata({N_M*DW{1'b0}}),.m_wstrb({N_M*4{1'b0}}),.m_wlast({N_M{1'b0}}),
        .m_wvalid({N_M{1'b0}}),.m_wready(),.m_bid(),.m_bresp(),.m_bvalid(),.m_bready({N_M{1'b0}}),
        .m_arid(arid_f),.m_araddr(araddr_f),.m_arlen(arlen_f),.m_arsize(arsize_f),
        .m_arburst(arburst_f),.m_arlock(arlock_f),.m_arcache(arcache_f),.m_arprot(arprot_f),
        .m_arqos(arqos_f),.m_arvalid(arvalid),.m_arready(arready),
        .m_rid(rid_f),.m_rdata(rdata_f),.m_rresp(rresp_f),.m_rlast(rlast),
        .m_rvalid(rvalid),.m_rready(rready),
        .s_awid(s_awid),.s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),
        .s_awburst(s_awburst),.s_awlock(s_awlock),.s_awcache(s_awcache),.s_awprot(s_awprot),
        .s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bid(s_bid),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_arid(s_arid),.s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),
        .s_arburst(s_arburst),.s_arlock(s_arlock),.s_arcache(s_arcache),.s_arprot(s_arprot),
        .s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rid(s_rid),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),
        .s_rvalid(s_rvalid),.s_rready(s_rready)
    );

    // S0 = multi-outstanding (Q=4, LAT=6); S1 = also MO but distinct latency.
    genvar gs;
    generate for (gs=0; gs<N_S; gs=gs+1) begin: g_slv
        axi_mo_slave #(.Q(4),.LAT(gs==0?6:3)) u_slv (
            .clk(clk),.rst_n(rst_n),
            .arid(s_arid[gs*IDW+:IDW]),.araddr(s_araddr[gs*AW+:AW]),.arlen(s_arlen[gs*8+:8]),
            .arvalid(s_arvalid[gs]),.arready(s_arready[gs]),
            .rid(s_rid[gs*IDW+:IDW]),.rdata(s_rdata[gs*DW+:DW]),.rresp(s_rresp[gs*2+:2]),
            .rlast(s_rlast[gs]),.rvalid(s_rvalid[gs]),.rready(s_rready[gs])
        );
    end endgenerate
    // tie unused slave write outputs from xbar (ignore)
    assign s_bready = s_bready;

    integer errs=0, k;
    integer accepted, responses;

    initial begin
        for (k=0;k<N_M;k=k+1) begin arvalid[k]=0; rready[k]=0; araddr[k]=0; arid[k]=0; end
        m_enable={N_M{1'b1}};
        #23 rst_n=1; @(negedge clk);

        // ---- T1: single master, 4 back-to-back ARs to S0 (multi-outstanding) ----
        // Hold rready LOW so no responses drain; count how many ARs the crossbar
        // accepts. With N_OT=4 and a Q=4 slave, up to 4 must be accepted while
        // zero responses have completed -> proves boundary outstanding depth.
        accepted=0; rready[0]=0;
        arid[0]=4'h0; araddr[0]=32'h0000_0000; arvalid[0]=1;
        begin: acc_count
            integer nid; nid=0;
            repeat (40) begin
                @(posedge clk);
                if (arready[0] && arvalid[0]) begin
                    accepted=accepted+1; nid=nid+1;
                    arid[0]=nid[3:0]; araddr[0]=nid<<2;
                end
            end
        end
        @(negedge clk); arvalid[0]=0;
        // crossbar read FIFO for S0 must hold 4 outstanding (rready was low)
        if (accepted<4) begin $display("FAIL T1: only %0d ARs accepted (want 4)",accepted); errs=errs+1; end
        if (dut.rd_cnt[0]<4) begin $display("FAIL T1: rd_cnt[S0]=%0d (want 4 outstanding)",dut.rd_cnt[0]); errs=errs+1; end
        // now drain
        rready[0]=1;
        repeat (60) @(posedge clk);
        rready[0]=0;

        // ---- T2: cross-slave concurrency: m0->S0, m1->S1 simultaneously ----
        @(negedge clk);
        arid[0]=4'h0; araddr[0]=32'h0000_0000; arvalid[0]=1; rready[0]=1;
        arid[1]=4'h1; araddr[1]=32'h4000_0000; arvalid[1]=1; rready[1]=1;
        begin: conc
            integer both_inflight; both_inflight=0;
            repeat (40) begin
                @(posedge clk);
                if (arready[0]&&arvalid[0]) arvalid[0]=0;
                if (arready[1]&&arvalid[1]) arvalid[1]=0;
                // both slaves have an outstanding read at the same time?
                if (dut.rd_cnt[0]>0 && dut.rd_cnt[1]>0) both_inflight=1;
            end
            if (!both_inflight) begin $display("FAIL T2: no simultaneous cross-slave in-flight reads"); errs=errs+1; end
        end
        rready[0]=0; rready[1]=0;

        #50;
        if (errs==0) $display("REGRESSION_TEST_SUCCESS xbar_multi_ot");
        else         $display("REGRESSION_TEST_FAIL errs=%0d",errs);
        $finish;
    end
    initial begin #300000 $display("FAIL timeout"); $finish; end
endmodule
