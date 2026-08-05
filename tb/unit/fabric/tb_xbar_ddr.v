// =============================================================================
// tb_xbar_ddr.v — Phase C.4 DDR window fabric test
// Checks the new S3 DDR mapped slave (SOC_DDR_BASE=0x0800_0000, 128MB) end to
// end through axi_crossbar into the protocol-level DDR4 controller:
//   - read-after-write data integrity at the DDR base address
//   - burst read-after-write integrity at an offset within the window
//   - the DDR/FLASH boundary is respected: DDR ends at 0x0FFF_FFFF, FLASH
//     starts at 0x1000_0000 — the two windows must not overlap or alias
//   - an otherwise-unmapped address still returns DECERR
//   - existing SRAM window (S0) traffic is unaffected by the new slave
// Uses N_M=2, N_S=4 (SRAM@0x0, APB@0x40000000, FLASH@0x10000000,
// DDR@0x08000000) + DECERR. S0-S2 are backed by the generic axi_mem_slave TB
// model; S3 is backed by rtl/perips/axi_ddr4_controller.v.
// =============================================================================
`timescale 1ns/1ps
`include "soc_config.vh"

module tb_xbar_ddr;
    localparam N_M=2, N_S=4, N_OT=4, IDW=4, AW=32, DW=32, QW=4;

    reg clk=0, rst_n=0;
    always #5 clk = ~clk;

    reg  [N_M-1:0] m_enable;

    reg  [IDW-1:0] awid[0:N_M-1]; reg [AW-1:0] awaddr[0:N_M-1]; reg [7:0] awlen[0:N_M-1];
    reg  [QW-1:0]  awqos[0:N_M-1]; reg [N_M-1:0] awvalid;
    reg  [DW-1:0]  wdata[0:N_M-1]; reg [N_M-1:0] wlast, wvalid;
    reg  [N_M-1:0] bready;
    reg  [IDW-1:0] arid[0:N_M-1]; reg [AW-1:0] araddr[0:N_M-1]; reg [7:0] arlen[0:N_M-1];
    reg  [QW-1:0]  arqos[0:N_M-1]; reg [N_M-1:0] arvalid, rready;

    wire [N_M-1:0] awready, wready, bvalid, arready, rvalid, rlast;
    wire [N_M*IDW-1:0] bid_f, rid_f;
    wire [N_M*2-1:0]   bresp_f, rresp_f;
    wire [N_M*DW-1:0]  rdata_f;

    wire [N_M*IDW-1:0] awid_f, arid_f; wire [N_M*AW-1:0] awaddr_f, araddr_f;
    wire [N_M*8-1:0] awlen_f, arlen_f; wire [N_M*QW-1:0] awqos_f, arqos_f;
    wire [N_M*DW-1:0] wdata_f; wire [N_M*3-1:0] awsize_f, arsize_f, awprot_f, arprot_f;
    wire [N_M*2-1:0] awburst_f, arburst_f, awlock_f, arlock_f;
    wire [N_M*4-1:0] awcache_f, arcache_f, wstrb_f;
    genvar gi;
    generate for (gi=0; gi<N_M; gi=gi+1) begin: g_flat
        assign awid_f[gi*IDW+:IDW]=awid[gi]; assign awaddr_f[gi*AW+:AW]=awaddr[gi];
        assign awlen_f[gi*8+:8]=awlen[gi]; assign awqos_f[gi*QW+:QW]=awqos[gi];
        assign awsize_f[gi*3+:3]=3'b010; assign awburst_f[gi*2+:2]=2'b01;
        assign awlock_f[gi*2+:2]=2'b0; assign awcache_f[gi*4+:4]=4'b0; assign awprot_f[gi*3+:3]=3'b0;
        assign wdata_f[gi*DW+:DW]=wdata[gi]; assign wstrb_f[gi*4+:4]=4'hF;
        assign arid_f[gi*IDW+:IDW]=arid[gi]; assign araddr_f[gi*AW+:AW]=araddr[gi];
        assign arlen_f[gi*8+:8]=arlen[gi]; assign arqos_f[gi*QW+:QW]=arqos[gi];
        assign arsize_f[gi*3+:3]=3'b010; assign arburst_f[gi*2+:2]=2'b01;
        assign arlock_f[gi*2+:2]=2'b0; assign arcache_f[gi*4+:4]=4'b0; assign arprot_f[gi*3+:3]=3'b0;
    end endgenerate

    // slave-side wires
    wire [N_S*IDW-1:0] s_awid, s_arid, s_bid, s_rid;
    wire [N_S*AW-1:0]  s_awaddr, s_araddr;
    wire [N_S*8-1:0]   s_awlen, s_arlen;
    wire [N_S*3-1:0]   s_awsize, s_arsize, s_awprot, s_arprot;
    wire [N_S*2-1:0]   s_awburst, s_arburst, s_awlock, s_arlock, s_bresp, s_rresp;
    wire [N_S*4-1:0]   s_awcache, s_arcache, s_wstrb;
    wire [N_S*DW-1:0]  s_wdata, s_rdata;
    wire [N_S-1:0]     s_awvalid, s_awready, s_wlast, s_wvalid, s_wready;
    wire [N_S-1:0]     s_bvalid, s_bready, s_arvalid, s_arready, s_rlast, s_rvalid, s_rready;

    axi_crossbar #(.N_M(N_M),.N_S(N_S),.N_OT(N_OT)) dut (
        .clk(clk),.rst_n(rst_n),.m_enable(m_enable),
        .m_awid(awid_f),.m_awaddr(awaddr_f),.m_awlen(awlen_f),.m_awsize(awsize_f),
        .m_awburst(awburst_f),.m_awlock(awlock_f),.m_awcache(awcache_f),.m_awprot(awprot_f),
        .m_awqos(awqos_f),.m_awvalid(awvalid),.m_awready(awready),
        .m_wdata(wdata_f),.m_wstrb(wstrb_f),.m_wlast(wlast),.m_wvalid(wvalid),.m_wready(wready),
        .m_bid(bid_f),.m_bresp(bresp_f),.m_bvalid(bvalid),.m_bready(bready),
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

    // S0=SRAM, S1=APB, S2=FLASH: generic in-order TB memory slaves.
    genvar gsv;
    generate for (gsv=0; gsv<3; gsv=gsv+1) begin: g_slv
        axi_mem_slave #(.IDW(IDW),.AW(AW),.DW(DW),.RD_DELAY(1)) u_slv (
            .clk(clk),.rst_n(rst_n),
            .awid(s_awid[gsv*IDW+:IDW]),.awaddr(s_awaddr[gsv*AW+:AW]),.awlen(s_awlen[gsv*8+:8]),
            .awvalid(s_awvalid[gsv]),.awready(s_awready[gsv]),
            .wdata(s_wdata[gsv*DW+:DW]),.wstrb(s_wstrb[gsv*4+:4]),.wlast(s_wlast[gsv]),
            .wvalid(s_wvalid[gsv]),.wready(s_wready[gsv]),
            .bid(s_bid[gsv*IDW+:IDW]),.bresp(s_bresp[gsv*2+:2]),.bvalid(s_bvalid[gsv]),.bready(s_bready[gsv]),
            .arid(s_arid[gsv*IDW+:IDW]),.araddr(s_araddr[gsv*AW+:AW]),.arlen(s_arlen[gsv*8+:8]),
            .arvalid(s_arvalid[gsv]),.arready(s_arready[gsv]),
            .rid(s_rid[gsv*IDW+:IDW]),.rdata(s_rdata[gsv*DW+:DW]),.rresp(s_rresp[gsv*2+:2]),
            .rlast(s_rlast[gsv]),.rvalid(s_rvalid[gsv]),.rready(s_rready[gsv])
        );
    end endgenerate

    // S3=DDR: real behavioral placeholder module under test.
    axi_ddr4_controller #(.MEM_DEPTH_WORDS(4096), .REFRESH_INTERVAL_CYCLES(0)) u_ddr (
        .clk(clk),.rst_n(rst_n),
        .s_awid(s_awid[3*IDW+:IDW]),.s_awaddr(s_awaddr[3*AW+:AW]),.s_awlen(s_awlen[3*8+:8]),
        .s_awsize(s_awsize[3*3+:3]),.s_awburst(s_awburst[3*2+:2]),
        .s_awvalid(s_awvalid[3]),.s_awready(s_awready[3]),
        .s_wdata(s_wdata[3*DW+:DW]),.s_wstrb(s_wstrb[3*4+:4]),.s_wlast(s_wlast[3]),
        .s_wvalid(s_wvalid[3]),.s_wready(s_wready[3]),
        .s_bid(s_bid[3*IDW+:IDW]),.s_bresp(s_bresp[3*2+:2]),.s_bvalid(s_bvalid[3]),.s_bready(s_bready[3]),
        .s_arid(s_arid[3*IDW+:IDW]),.s_araddr(s_araddr[3*AW+:AW]),.s_arlen(s_arlen[3*8+:8]),
        .s_arsize(s_arsize[3*3+:3]),.s_arburst(s_arburst[3*2+:2]),
        .s_arvalid(s_arvalid[3]),.s_arready(s_arready[3]),
        .s_rid(s_rid[3*IDW+:IDW]),.s_rdata(s_rdata[3*DW+:DW]),.s_rresp(s_rresp[3*2+:2]),
        .s_rlast(s_rlast[3]),.s_rvalid(s_rvalid[3]),.s_rready(s_rready[3]),
        .refresh_req(1'b0), .controller_present(), .init_done(),
        .training_done(), .refresh_busy(), .fatal_error(), .error_code()
    );

    integer errs=0;
    task do_write(input integer m, input [IDW-1:0] id, input [AW-1:0] a, input [DW-1:0] d,
                  input [1:0] exp);
    begin
        @(negedge clk); awid[m]=id; awaddr[m]=a; awlen[m]=0; awqos[m]=0; awvalid[m]=1;
        @(posedge clk); while (!awready[m]) @(posedge clk);
        @(negedge clk); awvalid[m]=0;
        wdata[m]=d; wlast[m]=1; wvalid[m]=1; bready[m]=1;
        @(posedge clk); while (!wready[m]) @(posedge clk);
        @(negedge clk); wvalid[m]=0; wlast[m]=0;
        @(posedge clk); while (!bvalid[m]) @(posedge clk);
        if (bresp_f[m*2+:2]!==exp) begin $display("FAIL W m%0d a=%h bresp=%b exp=%b",m,a,bresp_f[m*2+:2],exp); errs=errs+1; end
        @(negedge clk); bready[m]=0;
    end endtask

    task do_read(input integer m, input [IDW-1:0] id, input [AW-1:0] a, input [7:0] len,
                 input [1:0] exp, output [DW-1:0] first);
        integer bc; reg done;
    begin
        @(negedge clk); arid[m]=id; araddr[m]=a; arlen[m]=len; arqos[m]=0;
        arvalid[m]=1; rready[m]=1; bc=0; first=0; done=0;
        @(posedge clk); while (!arready[m]) @(posedge clk);
        @(negedge clk); arvalid[m]=0;
        while (!done) begin
            @(posedge clk);
            if (rvalid[m] && rready[m]) begin
                if (bc==0) first=rdata_f[m*DW+:DW];
                if (rresp_f[m*2+:2]!==exp) begin $display("FAIL R m%0d a=%h beat%0d rresp=%b exp=%b",m,a,bc,rresp_f[m*2+:2],exp); errs=errs+1; end
                bc=bc+1;
                if (rlast[m]) begin @(negedge clk); rready[m]=0; done=1; end
            end
        end
        if (bc!==len+1) begin $display("FAIL R m%0d beats=%0d exp=%0d",m,bc,len+1); errs=errs+1; end
    end endtask

    reg [DW-1:0] rd;
    integer k;
    initial begin
        for (k=0;k<N_M;k=k+1) begin
            awvalid[k]=0; wvalid[k]=0; wlast[k]=0; bready[k]=0;
            arvalid[k]=0; rready[k]=0; awid[k]=0; arid[k]=0;
            awaddr[k]=0; araddr[k]=0; awlen[k]=0; arlen[k]=0; awqos[k]=0; arqos[k]=0;
            wdata[k]=0;
        end
        m_enable = {N_M{1'b1}};
        #23 rst_n=1;
        @(negedge clk);

        // T1: read-after-write at DDR base (0x0800_0000)
        do_write(0, 4'h1, `SOC_DDR_BASE, 32'hD00D_0001, `SOC_AXI_RESP_OKAY);
        do_read (0, 4'h1, `SOC_DDR_BASE, 8'd0, `SOC_AXI_RESP_OKAY, rd);
        if (rd!==32'hD00D_0001) begin $display("FAIL T1 DDR base readback=%h",rd); errs=errs+1; end

        // T2: burst read-after-write at an offset within the window
        do_write(0, 4'h2, `SOC_DDR_BASE+32'h100, 32'hD00D_0002, `SOC_AXI_RESP_OKAY);
        do_read (0, 4'h2, `SOC_DDR_BASE+32'h100, 8'd3, `SOC_AXI_RESP_OKAY, rd);
        if (rd!==32'hD00D_0002) begin $display("FAIL T2 DDR burst readback=%h",rd); errs=errs+1; end

        // T3: existing SRAM window (S0) still works unaffected
        do_write(0, 4'h3, 32'h0000_0040, 32'hCAFE_0003, `SOC_AXI_RESP_OKAY);
        do_read (0, 4'h3, 32'h0000_0040, 8'd0, `SOC_AXI_RESP_OKAY, rd);
        if (rd!==32'hCAFE_0003) begin $display("FAIL T3 SRAM readback=%h",rd); errs=errs+1; end

        // T4: last word of the DDR window (0x0FFF_FFFC) still decodes to DDR,
        // not DECERR and not FLASH.
        do_write(0, 4'h4, 32'h0FFF_FFFC, 32'hD00D_0004, `SOC_AXI_RESP_OKAY);
        do_read (0, 4'h4, 32'h0FFF_FFFC, 8'd0, `SOC_AXI_RESP_OKAY, rd);
        if (rd!==32'hD00D_0004) begin $display("FAIL T4 DDR last-word readback=%h",rd); errs=errs+1; end

        // T5: first word of FLASH (0x1000_0000) must NOT alias to DDR's
        // backing store — reading it back must not equal what T4 wrote.
        do_read (0, 4'h5, 32'h1000_0000, 8'd0, `SOC_AXI_RESP_OKAY, rd);
        if (rd===32'hD00D_0004) begin $display("FAIL T5 FLASH aliases DDR backing store, rd=%h",rd); errs=errs+1; end

        // T6: address outside all mapped windows (0xF000_0000) is unmapped -> DECERR
        do_read (1, 4'h6, 32'hF000_0000, 8'd0, `SOC_AXI_RESP_DECERR, rd);
        do_write(1, 4'h7, 32'hF000_0000, 32'hDEAD_0004, `SOC_AXI_RESP_DECERR);

        #50;
        if (errs==0) $display("REGRESSION_TEST_SUCCESS xbar_ddr");
        else         $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin #200000 $display("FAIL timeout"); $finish; end
endmodule
