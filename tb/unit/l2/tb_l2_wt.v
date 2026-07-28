// Focused unit test for l2_cache_wt: multi-beat write-through must land every
// beat in downstream SRAM, and reads must return it. Reproduces the SoC
// cross_sweep failure (4-beat len=3 write read-back == 0).
`timescale 1ns/1ps
module tb_l2_wt;
    localparam AW=32, DW=32, IDW=4;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // Slave (upstream) side
    reg  [IDW-1:0] s_awid=0; reg [AW-1:0] s_awaddr=0; reg [7:0] s_awlen=0;
    reg  [2:0] s_awsize=3'b010; reg [1:0] s_awburst=2'b01; reg s_awvalid=0; wire s_awready;
    reg  [DW-1:0] s_wdata=0; reg [3:0] s_wstrb=4'hF; reg s_wlast=0; reg s_wvalid=0; wire s_wready;
    wire [IDW-1:0] s_bid; wire [1:0] s_bresp; wire s_bvalid; reg s_bready=0;
    reg  [IDW-1:0] s_arid=0; reg [AW-1:0] s_araddr=0; reg [7:0] s_arlen=0;
    reg  [2:0] s_arsize=3'b010; reg [1:0] s_arburst=2'b01; reg s_arvalid=0; wire s_arready;
    wire [IDW-1:0] s_rid; wire [DW-1:0] s_rdata; wire [1:0] s_rresp; wire s_rlast; wire s_rvalid; reg s_rready=0;

    // Master (downstream) side
    wire [IDW-1:0] m_awid; wire [AW-1:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
    wire [1:0] m_awburst; wire m_awvalid; reg m_awready=1;
    wire [DW-1:0] m_wdata; wire [3:0] m_wstrb; wire m_wlast; wire m_wvalid; reg m_wready=1;
    reg [IDW-1:0] m_bid=0; reg [1:0] m_bresp=0; reg m_bvalid=0; wire m_bready;
    wire [IDW-1:0] m_arid; wire [AW-1:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
    wire [1:0] m_arburst; wire m_arvalid; reg m_arready=1;
    reg [IDW-1:0] m_rid=0; reg [DW-1:0] m_rdata=0; reg [1:0] m_rresp=0; reg m_rlast=0; reg m_rvalid=0; wire m_rready;

    l2_cache_wt #(.SIZE_BYTES(32768)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(s_awsize),
        .s_awburst(s_awburst), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arsize(s_arsize),
        .s_arburst(s_arburst), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rlast(s_rlast),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .snoop_addr(32'b0), .snoop_valid(1'b0), .snoop_ack(), .snoop_hit()
    );

    // Downstream backing memory + AXI slave model
    localparam MW=20000;
    reg [DW-1:0] mem [0:MW-1];
    integer mi, errs=0;
    reg aw_act=0, w_act=0; reg [AW-1:0] aw_lat=0; reg [7:0] aw_len=0, aw_bc=0;
    wire [31:0] aw_widx = (aw_lat>>2) + aw_bc;
    reg ar_act=0; reg [AW-1:0] ar_lat=0; reg [7:0] ar_len=0, ar_bc=0;
    wire [31:0] ar_widx = (ar_lat>>2) + ar_bc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_act<=0; w_act<=0; aw_bc<=0; m_bvalid<=0;
            ar_act<=0; ar_bc<=0; m_rvalid<=0; m_rlast<=0;
        end else begin
            // Write channel
            if (m_awvalid && m_awready && !aw_act) begin
                aw_lat<=m_awaddr; aw_len<=m_awlen; aw_act<=1; aw_bc<=0; w_act<=1;
            end
            if (w_act && m_wvalid && m_wready) begin
                if (m_wstrb[0]) mem[aw_widx][7:0]  <= m_wdata[7:0];
                if (m_wstrb[1]) mem[aw_widx][15:8] <= m_wdata[15:8];
                if (m_wstrb[2]) mem[aw_widx][23:16]<= m_wdata[23:16];
                if (m_wstrb[3]) mem[aw_widx][31:24]<= m_wdata[31:24];
                if (m_wlast) begin w_act<=0; m_bvalid<=1; m_bid<=m_awid; m_bresp<=0; end
                else aw_bc<=aw_bc+1;
            end
            if (m_bvalid && m_bready) begin m_bvalid<=0; aw_act<=0; end
            // Read channel
            if (m_arvalid && m_arready && !ar_act) begin
                ar_lat<=m_araddr; ar_len<=m_arlen; ar_act<=1; ar_bc<=0; m_rvalid<=1;
                m_rid<=m_arid; m_rresp<=0;
            end
            if (ar_act && m_rvalid && m_rready) begin
                if (ar_bc==ar_len) begin m_rvalid<=0; m_rlast<=0; ar_act<=0; end
                else ar_bc<=ar_bc+1;
            end
        end
    end
    always @(*) begin
        m_rdata = mem[ar_widx];
        m_rlast = ar_act && (ar_bc==ar_len);
    end

    // 4-beat INCR write
    task wr4(input [31:0] base, input [31:0] d0);
    begin
        @(posedge clk); s_awid<=1; s_awaddr<=base; s_awlen<=8'd3; s_awsize<=3'b010;
        s_awburst<=2'b01; s_awvalid<=1;
        @(posedge clk); while(!s_awready) @(posedge clk); s_awvalid<=0;
        // beat 0..3
        wbeat(d0+0, 1'b0); wbeat(d0+1, 1'b0); wbeat(d0+2, 1'b0); wbeat(d0+3, 1'b1);
        s_bready<=1; @(posedge clk); while(!s_bvalid) @(posedge clk); s_bready<=0;
    end endtask
    task wbeat(input [31:0] d, input last);
    begin
        s_wdata<=d; s_wstrb<=4'hF; s_wlast<=last; s_wvalid<=1;
        @(posedge clk); while(!s_wready) @(posedge clk); s_wvalid<=0;
    end endtask
    // single-beat read
    task rd1(input [31:0] addr, output [31:0] data);
    begin
        s_arid<=2; s_araddr<=addr; s_arlen<=0; s_arsize<=3'b010; s_arburst<=2'b01; s_arvalid<=1;
        @(posedge clk); while(!s_arready) @(posedge clk); s_arvalid<=0;
        s_rready<=1; @(posedge clk); while(!s_rvalid) @(posedge clk); data=s_rdata; s_rready<=0;
    end endtask

    // multi-beat read burst; captures each beat into rburst[]
    reg [31:0] rburst [0:15];
    task rdN(input [31:0] addr, input [7:0] len);
        integer k; reg done;
    begin
        s_arid<=2; s_araddr<=addr; s_arlen<=len; s_arsize<=3'b010; s_arburst<=2'b01; s_arvalid<=1;
        @(posedge clk); while(!s_arready) @(posedge clk); s_arvalid<=0;
        s_rready<=1; k=0; done=0;
        while (!done) begin
            @(posedge clk);
            if (s_rvalid) begin rburst[k]=s_rdata; if (s_rlast) done=1; k=k+1; end
        end
        s_rready<=0;
    end endtask

    // single-beat write
    task cache_wr1(input [31:0] addr, input [31:0] d, output [1:0] resp);
    begin
        s_awid<=1; s_awaddr<=addr; s_awlen<=0; s_awsize<=3'b010; s_awburst<=2'b01; s_awvalid<=1;
        @(posedge clk); while(!s_awready) @(posedge clk); s_awvalid<=0;
        s_wdata<=d; s_wstrb<=4'hF; s_wlast<=1; s_wvalid<=1;
        @(posedge clk); while(!s_wready) @(posedge clk); s_wvalid<=0;
        s_bready<=1; @(posedge clk); while(!s_bvalid) @(posedge clk); resp=s_bresp; s_bready<=0;
    end endtask

    reg [31:0] rv;
    initial begin
        for (mi=0;mi<MW;mi=mi+1) mem[mi]=32'h0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        // 4-beat write to 0xC240 region (word idx 0xC240>>2)
        wr4(32'h0000_C240, 32'hAABB_0000);
        repeat(3) @(posedge clk);
        rd1(32'h0000_C240, rv); if (rv!==32'hAABB_0000) begin $display("FAIL w0 rd=%h exp=AABB0000",rv); errs=errs+1; end
        rd1(32'h0000_C244, rv); if (rv!==32'hAABB_0001) begin $display("FAIL w1 rd=%h exp=AABB0001",rv); errs=errs+1; end
        rd1(32'h0000_C248, rv); if (rv!==32'hAABB_0002) begin $display("FAIL w2 rd=%h exp=AABB0002",rv); errs=errs+1; end
        rd1(32'h0000_C24C, rv); if (rv!==32'hAABB_0003) begin $display("FAIL w3 rd=%h exp=AABB0003",rv); errs=errs+1; end
        $display("downstream mem[0x3090..0x3093]=%h %h %h %h",
                 mem[32'h0000_C240>>2], mem[(32'h0000_C240>>2)+1], mem[(32'h0000_C240>>2)+2], mem[(32'h0000_C240>>2)+3]);

        // Case 2: write HIT updates the cached line (line now valid from above).
        // Overwrite word 2 via a single-beat write, then read it back (hit path).
        begin : c2
            reg [1:0] wr;
            cache_wr1(32'h0000_C248, 32'hDEAD_BEEF, wr);
            repeat(2) @(posedge clk);
            rd1(32'h0000_C248, rv);
            if (rv!==32'hDEAD_BEEF) begin $display("FAIL c2: write-hit update rd=%h exp=DEADBEEF",rv); errs=errs+1; end
            if (mem[32'h0000_C248>>2]!==32'hDEAD_BEEF) begin $display("FAIL c2: SRAM not updated=%h",mem[32'h0000_C248>>2]); errs=errs+1; end
        end

        // Case 3: fresh line, single write miss (no-allocate) lands in SRAM,
        // then a read miss full-line-refills and returns it.
        begin : c3
            reg [1:0] wr;
            cache_wr1(32'h0000_D100, 32'h1234_5678, wr);
            repeat(2) @(posedge clk);
            rd1(32'h0000_D100, rv);
            if (rv!==32'h1234_5678) begin $display("FAIL c3: miss-write readback rd=%h exp=12345678",rv); errs=errs+1; end
            rd1(32'h0000_D104, rv); // adjacent word in same line: refilled from SRAM (0)
            if (rv!==32'h0) begin $display("FAIL c3: adjacent word rd=%h exp=0",rv); errs=errs+1; end
        end

        // Case 4: LINE-CROSSING read burst (the real SoC failure). Line size is
        // 32B = 8 words. Write two adjacent lines via write-through to SRAM, then
        // read an 8-beat burst starting mid-line so beats spill into the next
        // (un-cached) line. Every beat must return its written value.
        begin : c4
            reg [1:0] wr; integer b; reg [31:0] exp;
            // line A base 0xE000 (words E000..E01C), line B base 0xE020
            for (b=0;b<8;b=b+1) cache_wr1(32'h0000_E000 + b*4, 32'hC0DE_0000 + b, wr);
            for (b=0;b<8;b=b+1) cache_wr1(32'h0000_E020 + b*4, 32'hC0DE_0020 + b, wr);
            repeat(3) @(posedge clk);
            // burst of 8 beats starting at word 4 of line A -> crosses into line B
            rdN(32'h0000_E010, 8'd7);
            for (b=0;b<8;b=b+1) begin
                exp = (b<4) ? (32'hC0DE_0000 + (4+b)) : (32'hC0DE_0020 + (b-4));
                if (rburst[b]!==exp) begin $display("FAIL c4: cross beat %0d rd=%h exp=%h",b,rburst[b],exp); errs=errs+1; end
            end
        end

        if (errs==0) $display("WT_TEST_SUCCESS"); else $display("WT_TEST_FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #200000 $display("WT_TEST_TIMEOUT"); $finish; end
endmodule
