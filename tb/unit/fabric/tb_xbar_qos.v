// =============================================================================
// tb_xbar_qos.v — Phase C QoS arbitration test for axi_crossbar.
// Two masters contend for the SAME slave in the SAME cycle:
//  - Different QoS: higher-QoS master must be granted (accepted) first.
//  - Equal QoS: round-robin — grants must alternate between the two.
// Slave S0 is slow (RD_DELAY) so contention is visible; we observe which
// master's AR is accepted first via arready.
// =============================================================================
`timescale 1ns/1ps
`include "soc_config.vh"

module tb_xbar_qos;
    localparam N_M=3, N_S=2, N_OT=4, IDW=4, AW=32, DW=32, QW=4;

    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [N_M-1:0] m_enable;

    reg  [AW-1:0] araddr[0:N_M-1]; reg [QW-1:0] arqos[0:N_M-1];
    reg  [IDW-1:0] arid[0:N_M-1]; reg [N_M-1:0] arvalid, rready;
    wire [N_M-1:0] arready, rvalid, rlast;

    // flatten (writes unused here; tie AW/W off)
    wire [N_M*IDW-1:0] arid_f; wire [N_M*AW-1:0] araddr_f; wire [N_M*QW-1:0] arqos_f;
    wire [N_M*8-1:0] arlen_f; wire [N_M*3-1:0] arsize_f, arprot_f;
    wire [N_M*2-1:0] arburst_f, arlock_f; wire [N_M*4-1:0] arcache_f;
    genvar gi;
    generate for (gi=0;gi<N_M;gi=gi+1) begin: g_flat
        assign arid_f[gi*IDW+:IDW]=arid[gi]; assign araddr_f[gi*AW+:AW]=araddr[gi];
        assign arqos_f[gi*QW+:QW]=arqos[gi]; assign arlen_f[gi*8+:8]=8'd0;
        assign arsize_f[gi*3+:3]=3'b010; assign arburst_f[gi*2+:2]=2'b01;
        assign arlock_f[gi*2+:2]=2'b0; assign arcache_f[gi*4+:4]=4'b0; assign arprot_f[gi*3+:3]=3'b0;
    end endgenerate

    wire [N_M*IDW-1:0] rid_f; wire [N_M*DW-1:0] rdata_f; wire [N_M*2-1:0] rresp_f;

    // slave side
    wire [N_S*IDW-1:0] s_arid, s_rid; wire [N_S*AW-1:0] s_araddr; wire [N_S*8-1:0] s_arlen;
    wire [N_S*3-1:0] s_arsize; wire [N_S*2-1:0] s_arburst, s_arlock, s_rresp; wire [N_S*4-1:0] s_arcache;
    wire [N_S*3-1:0] s_arprot; wire [N_S*DW-1:0] s_rdata;
    wire [N_S-1:0] s_arvalid, s_arready, s_rlast, s_rvalid, s_rready;
    // write side (unused, tie off slave inputs)
    wire [N_S*IDW-1:0] s_awid, s_bid; wire [N_S*AW-1:0] s_awaddr; wire [N_S*8-1:0] s_awlen;
    wire [N_S*3-1:0] s_awsize, s_awprot; wire [N_S*2-1:0] s_awburst, s_awlock, s_bresp;
    wire [N_S*4-1:0] s_awcache, s_wstrb; wire [N_S*DW-1:0] s_wdata;
    wire [N_S-1:0] s_awvalid, s_wlast, s_wvalid, s_bvalid;
    wire [N_S-1:0] s_awready = {N_S{1'b1}}, s_wready = {N_S{1'b1}}, s_bready;

    axi_crossbar #(.N_M(N_M),.N_S(N_S),.N_OT(N_OT)) dut (
        .clk(clk),.rst_n(rst_n),.m_enable(m_enable),
        .m_awid({N_M*IDW{1'b0}}),.m_awaddr({N_M*AW{1'b0}}),.m_awlen({N_M*8{1'b0}}),
        .m_awsize({N_M*3{1'b0}}),.m_awburst({N_M*2{1'b0}}),.m_awlock({N_M*2{1'b0}}),
        .m_awcache({N_M*4{1'b0}}),.m_awprot({N_M*3{1'b0}}),.m_awqos({N_M*QW{1'b0}}),
        .m_awvalid({N_M{1'b0}}),.m_awready(),
        .m_wdata({N_M*DW{1'b0}}),.m_wstrb({N_M*4{1'b0}}),.m_wlast({N_M{1'b0}}),
        .m_wvalid({N_M{1'b0}}),.m_wready(),
        .m_bid(),.m_bresp(),.m_bvalid(),.m_bready({N_M{1'b0}}),
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

    // Behavioral slaves (both single-outstanding). Tie bvalid off (no writes).
    assign s_bvalid = {N_S{1'b0}};
    genvar gsv;
    generate for (gsv=0; gsv<N_S; gsv=gsv+1) begin: g_slv
        axi_mem_slave #(.RD_DELAY(3)) u_slv (
            .clk(clk),.rst_n(rst_n),
            .awid(4'd0),.awaddr(32'd0),.awlen(8'd0),.awvalid(1'b0),.awready(),
            .wdata(32'd0),.wstrb(4'd0),.wlast(1'b0),.wvalid(1'b0),.wready(),
            .bid(),.bresp(),.bvalid(),.bready(1'b0),
            .arid(s_arid[gsv*IDW+:IDW]),.araddr(s_araddr[gsv*AW+:AW]),.arlen(s_arlen[gsv*8+:8]),
            .arvalid(s_arvalid[gsv]),.arready(s_arready[gsv]),
            .rid(s_rid[gsv*IDW+:IDW]),.rdata(s_rdata[gsv*DW+:DW]),.rresp(s_rresp[gsv*2+:2]),
            .rlast(s_rlast[gsv]),.rvalid(s_rvalid[gsv]),.rready(s_rready[gsv])
        );
    end endgenerate

    integer errs=0, k;
    integer first_grant;   // which master got arready first

    // Track grant order among masters 0,1 for a contention episode.
    task run_contention(input [QW-1:0] q0, input [QW-1:0] q1, output integer winner);
        integer done;
    begin
        // both target S0 (addr 0x0), same cycle
        @(negedge clk);
        araddr[0]=32'h0000_0000; arqos[0]=q0; arid[0]=4'h0; arvalid[0]=1;
        araddr[1]=32'h0000_0004; arqos[1]=q1; arid[1]=4'h1; arvalid[1]=1;
        rready[0]=1; rready[1]=1; winner=-1; done=0;
        while (!done) begin
            @(posedge clk);
            if (arready[0] && arvalid[0]) begin winner=0; done=1; end
            else if (arready[1] && arvalid[1]) begin winner=1; done=1; end
        end
        // Drop BOTH immediately so only the winner's AR was accepted; the RR
        // pointer advances by exactly one grant. This isolates the RR decision.
        @(negedge clk); arvalid[0]=0; arvalid[1]=0;
        // let the winner's read drain fully before the next episode
        repeat (12) @(posedge clk);
    end endtask

    integer w1,w2,w3,w4;
    initial begin
        for (k=0;k<N_M;k=k+1) begin arvalid[k]=0; rready[k]=0; araddr[k]=0; arqos[k]=0; arid[k]=0; end
        m_enable={N_M{1'b1}};
        #23 rst_n=1; @(negedge clk);

        // T1: master1 higher QoS than master0 -> winner must be 1
        run_contention(4'd2, 4'd8, w1);
        if (w1!==1) begin $display("FAIL QoS T1: higher-qos m1 lost (winner=%0d)",w1); errs=errs+1; end

        // T2: master0 higher QoS -> winner must be 0
        run_contention(4'd9, 4'd3, w2);
        if (w2!==0) begin $display("FAIL QoS T2: higher-qos m0 lost (winner=%0d)",w2); errs=errs+1; end

        // T3/T4: equal QoS -> round-robin, winners must alternate
        run_contention(4'd5, 4'd5, w3);
        run_contention(4'd5, 4'd5, w4);
        if (w3===w4) begin $display("FAIL QoS T3/T4: equal-qos not round-robin (w3=%0d w4=%0d)",w3,w4); errs=errs+1; end

        #50;
        if (errs==0) $display("REGRESSION_TEST_SUCCESS xbar_qos");
        else         $display("REGRESSION_TEST_FAIL errs=%0d",errs);
        $finish;
    end
    initial begin #200000 $display("FAIL timeout"); $finish; end
endmodule
