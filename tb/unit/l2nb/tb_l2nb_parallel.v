// Focused opt-in test for l2_cache_nb's concurrent downstream refill slots.
// The memory accepts two read addresses before either burst is complete and
// alternates R beats by RID.  Dirty eviction is intentionally absent here;
// that path remains serialized and is covered by tb_l2nb.v.
`timescale 1ns/1ps

module tb_l2nb_parallel;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg [3:0] s_awid; reg [31:0] s_awaddr; reg [7:0] s_awlen;
    reg [2:0] s_awsize; reg [1:0] s_awburst; reg s_awvalid; wire s_awready;
    reg [31:0] s_wdata; reg [3:0] s_wstrb; reg s_wlast; reg s_wvalid; wire s_wready;
    wire [3:0] s_bid; wire [1:0] s_bresp; wire s_bvalid; reg s_bready;
    reg [3:0] s_arid; reg [31:0] s_araddr; reg [7:0] s_arlen;
    reg [2:0] s_arsize; reg [1:0] s_arburst; reg s_arvalid; wire s_arready;
    wire [3:0] s_rid; wire [31:0] s_rdata; wire [1:0] s_rresp;
    wire s_rlast, s_rvalid; reg s_rready;

    wire [3:0] m_awid; wire [31:0] m_awaddr; wire [7:0] m_awlen;
    wire [2:0] m_awsize; wire [1:0] m_awburst; wire m_awvalid; reg m_awready;
    wire [31:0] m_wdata; wire [3:0] m_wstrb; wire m_wlast; wire m_wvalid; reg m_wready;
    reg [3:0] m_bid; reg [1:0] m_bresp; reg m_bvalid; wire m_bready;
    wire [3:0] m_arid; wire [31:0] m_araddr; wire [7:0] m_arlen;
    wire [2:0] m_arsize; wire [1:0] m_arburst; wire m_arvalid; reg m_arready;
    reg [3:0] m_rid; reg [31:0] m_rdata; reg [1:0] m_rresp; reg m_rlast;
    reg m_rvalid; wire m_rready;
    reg [31:0] snoop_addr; reg snoop_valid; wire snoop_ack, snoop_hit;

    l2_cache_nb #(.N_MSHR(8), .ORD_DEPTH(8), .WB_DEPTH(4),
                  .DOWNSTREAM_SLOTS(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst), .s_awvalid(s_awvalid),
        .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_wlast(s_wlast), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata),
        .s_rresp(s_rresp), .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awvalid(m_awvalid),
        .m_awready(m_awready), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
        .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid),
        .m_arready(m_arready), .m_rid(m_rid), .m_rdata(m_rdata),
        .m_rresp(m_rresp), .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .snoop_addr(snoop_addr), .snoop_valid(snoop_valid),
        .snoop_ack(snoop_ack), .snoop_hit(snoop_hit));

    // Two-entry downstream read responder.
    reg [1:0] rd_active;
    reg [31:0] mem [0:1048575];
    integer mi;
    initial for (mi=0; mi<1048576; mi=mi+1)
        mem[mi] = 32'hA5A5_0000 | mi[15:0];
    reg [3:0] rd_id [0:1];
    reg [31:0] rd_addr [0:1];
    reg [7:0] rd_len [0:1];
    reg [7:0] rd_beat [0:1];
    reg rd_turn;
    reg inject_r_error;
    integer rd_sel;
    reg wr_active, wr_bvalid;
    reg [3:0] wr_id;
    reg [31:0] wr_addr;
    reg [7:0] wr_beat;
    always @(*) begin
        m_arready = (rd_active != 2'b11);
        m_awready = !wr_active; m_wready = wr_active;
        m_bvalid = wr_bvalid; m_bid = wr_id; m_bresp = 2'b00;
        m_rvalid = 1'b0; m_rid = 4'd0; m_rdata = 32'd0;
        m_rresp = 2'b00; m_rlast = 1'b0; rd_sel = 0;
        if (rd_turn == 1'b0) begin
            if (rd_active[0]) rd_sel = 0;
            else if (rd_active[1]) rd_sel = 1;
        end else begin
            if (rd_active[1]) rd_sel = 1;
            else if (rd_active[0]) rd_sel = 0;
        end
        if (rd_active != 2'b00) begin
            m_rvalid = 1'b1;
            m_rid = rd_id[rd_sel];
            m_rdata = mem[(rd_addr[rd_sel][21:2]) + rd_beat[rd_sel]];
            m_rresp = (inject_r_error && rd_addr[rd_sel] == 32'h0014_0040) ?
                      2'b10 : 2'b00;
            m_rlast = (rd_beat[rd_sel] == rd_len[rd_sel]);
        end
    end

    integer errs=0, peak_active=0, id_switches=0, last_id=-1, overlap_events=0;
    integer error_checked=0;
    integer outstanding=0, checked=0;
    reg [31:0] exp_addr [0:15]; reg [7:0] exp_beat [0:15];
    reg exp_valid [0:15]; reg exp_error [0:15];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_active<=0; rd_turn<=0; inject_r_error<=0;
            wr_active<=0; wr_bvalid<=0;
            wr_id<=0; wr_addr<=0; wr_beat<=0;
            for (i=0;i<2;i=i+1) begin rd_id[i]<=0; rd_addr[i]<=0; rd_len[i]<=0; rd_beat[i]<=0; end
        end else begin
            if (m_arvalid && m_arready) begin
                if (!rd_active[0]) begin
                    rd_active[0]<=1; rd_id[0]<=m_arid; rd_addr[0]<=m_araddr;
                    rd_len[0]<=m_arlen; rd_beat[0]<=0;
                end else begin
                    rd_active[1]<=1; rd_id[1]<=m_arid; rd_addr[1]<=m_araddr;
                    rd_len[1]<=m_arlen; rd_beat[1]<=0;
                end
            end
            if (m_rvalid && m_rready) begin
                rd_turn <= (rd_sel == 0) ? 1'b1 : 1'b0;
                if (m_rlast) rd_active[rd_sel]<=0;
                else rd_beat[rd_sel]<=rd_beat[rd_sel]+1'b1;
            end
            if (m_awvalid && m_awready) begin
                wr_active<=1'b1; wr_id<=m_awid; wr_addr<=m_awaddr; wr_beat<=0;
            end
            if (m_wvalid && m_wready) begin
                wr_beat<=wr_beat+1'b1;
                if (m_wstrb[0]) mem[(wr_addr[21:2])+wr_beat][7:0] <= m_wdata[7:0];
                if (m_wstrb[1]) mem[(wr_addr[21:2])+wr_beat][15:8] <= m_wdata[15:8];
                if (m_wstrb[2]) mem[(wr_addr[21:2])+wr_beat][23:16] <= m_wdata[23:16];
                if (m_wstrb[3]) mem[(wr_addr[21:2])+wr_beat][31:24] <= m_wdata[31:24];
                if (m_wlast) begin wr_active<=1'b0; wr_bvalid<=1'b1; end
            end
            if (m_bvalid && m_bready) begin
                wr_bvalid<=1'b0;
            end
            if (rd_active > peak_active) peak_active = rd_active;
            if (m_arvalid && m_arready &&
                (dut.me_state == 3'd1 || dut.me_state == 3'd2 || dut.me_state == 3'd3))
                overlap_events=overlap_events+1;
        end
    end

    always @(posedge clk) if (rst_n && s_rvalid && s_rready) begin
        if (!exp_valid[s_rid] ||
            (exp_error[s_rid] && s_rresp == 2'b00) ||
            (!exp_error[s_rid] && s_rresp != 2'b00) ||
            (!exp_error[s_rid] && s_rdata !== (32'hA5A5_0000 |
                         (((exp_addr[s_rid] >> 2) + exp_beat[s_rid]) & 16'hffff)))) begin
            $display("FAIL parallel read id=%0d beat=%0d data=%h resp=%b", s_rid,
                     exp_beat[s_rid], s_rdata, s_rresp); errs=errs+1;
        end else if (exp_error[s_rid]) error_checked=error_checked+1;
        else checked=checked+1;
        if (last_id >= 0 && last_id != s_rid) id_switches=id_switches+1;
        last_id=s_rid;
        if (s_rlast) begin exp_valid[s_rid]=0; exp_error[s_rid]=0; outstanding=outstanding-1; end
        else exp_beat[s_rid]=exp_beat[s_rid]+1;
    end

    task issue_read(input [3:0] id, input [31:0] addr, input [7:0] len);
    begin
        exp_addr[id]=addr; exp_beat[id]=0; exp_valid[id]=1; outstanding=outstanding+1;
        exp_error[id]=0;
        @(negedge clk); s_arid=id; s_araddr=addr; s_arlen=len; s_arsize=3'b010;
        s_arburst=2'b01; s_arvalid=1;
        @(posedge clk); while (!s_arready) @(posedge clk);
        @(negedge clk); s_arvalid=0;
    end
    endtask

    task issue_read_expect_error(input [3:0] id, input [31:0] addr, input [7:0] len);
    begin
        exp_addr[id]=addr; exp_beat[id]=0; exp_valid[id]=1; exp_error[id]=1;
        outstanding=outstanding+1;
        @(negedge clk); s_arid=id; s_araddr=addr; s_arlen=len; s_arsize=3'b010;
        s_arburst=2'b01; s_arvalid=1;
        @(posedge clk); while (!s_arready) @(posedge clk);
        @(negedge clk); s_arvalid=0;
    end
    endtask

    task issue_write_wait(input [3:0] id, input [31:0] addr, input [31:0] data);
    begin
        @(negedge clk); s_awid=id; s_awaddr=addr; s_awlen=8'd0; s_awsize=3'b010;
        s_awburst=2'b01; s_awvalid=1'b1;
        @(posedge clk); while (!s_awready) @(posedge clk);
        @(negedge clk); s_awvalid=0; s_wdata=data; s_wstrb=4'hf;
        s_wlast=1'b1; s_wvalid=1'b1;
        @(posedge clk); while (!s_wready) @(posedge clk);
        @(negedge clk); s_wvalid=0; s_wlast=0;
        while (!s_bvalid) @(posedge clk);
        @(posedge clk);
    end
    endtask

    initial begin
        s_awvalid=0; s_wvalid=0; s_arvalid=0; s_wlast=0; s_bready=1; s_rready=1;
        s_awid=0; s_awaddr=0; s_awlen=0; s_awsize=0; s_awburst=1;
        s_arid=0; s_araddr=0; s_arlen=0; s_arsize=0; s_arburst=1;
        s_wdata=0; s_wstrb=0; snoop_addr=0; snoop_valid=0;
        for (i=0;i<16;i=i+1) begin
            exp_valid[i]=0; exp_error[i]=0; exp_addr[i]=0; exp_beat[i]=0;
        end
        inject_r_error=0;
        #23 rst_n=1;
        // Fill and dirty one line, then force a dirty replacement while a
        // second clean miss is launched in parallel.
        begin : DIRTY_OVERLAP integer j;
            issue_read(4'd0, 32'h0000_0040, 8'd0);
            while (outstanding != 0) @(posedge clk);
            issue_write_wait(4'd8, 32'h0000_0040, 32'h6000_0000);
            issue_read(4'd5, 32'h0008_0040, 8'd0);
            issue_read(4'd6, 32'h000a_0040, 8'd0);
            while (outstanding != 0) @(posedge clk);
        end
        // One parallel refill returns SLVERR while a second RID completes;
        // the failed line must drain cleanly and succeed on retry.
        inject_r_error=1;
        issue_read_expect_error(4'd7, 32'h0014_0040, 8'd7);
        issue_read(4'd8, 32'h0015_0040, 8'd7);
        while (outstanding != 0) @(posedge clk);
        inject_r_error=0;
        issue_read(4'd7, 32'h0014_0040, 8'd0);
        while (outstanding != 0) @(posedge clk);
        // Drop reset while both downstream read slots are active. Any
        // abandoned upstream expectations are discarded with the reset, and
        // a post-reset request must establish a fresh refill transaction.
        issue_read(4'd9, 32'h0018_0040, 8'd7);
        issue_read(4'd10, 32'h0019_0040, 8'd7);
        while (!(dut.rd_valid[0] && dut.rd_valid[1])) @(posedge clk);
        @(negedge clk); rst_n=1'b0;
        repeat(2) @(posedge clk);
        for (i=0;i<16;i=i+1) begin exp_valid[i]=0; exp_error[i]=0; end
        outstanding=0;
        @(negedge clk); rst_n=1'b1;
        issue_read(4'd9, 32'h0018_0040, 8'd0);
        while (outstanding != 0) @(posedge clk);
        issue_read(4'd1,32'h0001_0000,8'd7);
        issue_read(4'd2,32'h0002_0000,8'd7);
        issue_read(4'd3,32'h0003_0000,8'd7);
        issue_read(4'd4,32'h0004_0000,8'd7);
        while (outstanding != 0) @(posedge clk);
        repeat(4) @(posedge clk);
        if (peak_active < 2) begin $display("FAIL no two downstream refills observed"); errs=errs+1; end
        if (id_switches < 1) begin $display("FAIL no cross-ID R interleave observed"); errs=errs+1; end
        if (overlap_events < 1) begin $display("FAIL no refill overlapped dirty writeback"); errs=errs+1; end
        if (error_checked < 8) begin $display("FAIL parallel error burst did not drain (%0d beats)", error_checked); errs=errs+1; end
        if (errs==0) $display("REGRESSION_TEST_SUCCESS l2nb_parallel (reads_checked=%0d errors_checked=%0d peak_downstream=%0d id_switches=%0d wb_refill_overlap=%0d)", checked, error_checked, peak_active, id_switches, overlap_events);
        else $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #500000 $display("FAIL timeout"); $finish; end
endmodule
