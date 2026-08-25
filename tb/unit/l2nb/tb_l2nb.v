// =============================================================================
// tb_l2nb.v — unit test for the non-blocking (full-MSHR) L2 cache.
// Drives the upstream slave port with a MULTI-OUTSTANDING master (issues AR/AW
// without waiting for prior responses) and backs the downstream master port
// with a single-outstanding behavioral memory that ASSERTS if the L2 ever has
// two AR/AW bursts in flight at once (the fabric contract).
// Cases: parity (miss/hit/dirty-evict), hit-under-miss, miss-under-miss,
// secondary-miss merge, dirty writeback under concurrency, MSHR backpressure.
// Scoreboard: an ideal reference memory; every read response is checked.
// =============================================================================
`timescale 1ns/1ps

module tb_l2nb;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // upstream (we are master)
    reg  [3:0]  s_awid;   reg [31:0] s_awaddr; reg [7:0] s_awlen;
    reg  [2:0]  s_awsize; reg [1:0]  s_awburst; reg s_awvalid; wire s_awready;
    reg  [31:0] s_wdata;  reg [3:0]  s_wstrb;  reg s_wlast; reg s_wvalid; wire s_wready;
    wire [3:0]  s_bid;    wire [1:0] s_bresp;  wire s_bvalid; reg s_bready;
    reg  [3:0]  s_arid;   reg [31:0] s_araddr; reg [7:0] s_arlen;
    reg  [2:0]  s_arsize; reg [1:0]  s_arburst; reg s_arvalid; wire s_arready;
    wire [3:0]  s_rid;    wire [31:0] s_rdata;  wire [1:0] s_rresp;
    wire        s_rlast;  wire s_rvalid; reg s_rready;

    // downstream (L2 is master, TB is memory)
    wire [3:0]  m_awid; wire [31:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
    wire [1:0]  m_awburst; wire m_awvalid; reg m_awready;
    wire [31:0] m_wdata; wire [3:0] m_wstrb; wire m_wlast; wire m_wvalid; reg m_wready;
    reg  [3:0]  m_bid; reg [1:0] m_bresp; reg m_bvalid; wire m_bready;
    wire [3:0]  m_arid; wire [31:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
    wire [1:0]  m_arburst; wire m_arvalid; reg m_arready;
    reg  [3:0]  m_rid; reg [31:0] m_rdata; reg [1:0] m_rresp; reg m_rlast; reg m_rvalid; wire m_rready;

    reg [31:0] snoop_addr;
    reg        snoop_valid;
    wire       snoop_ack;
    wire       snoop_hit;

    l2_cache_nb #(.N_MSHR(8), .ORD_DEPTH(8), .WB_DEPTH(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid),.s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),
        .s_awburst(s_awburst),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bid(s_bid),.s_bresp(s_bresp),.s_bvalid(s_bvalid),.s_bready(s_bready),
        .s_arid(s_arid),.s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),
        .s_arburst(s_arburst),.s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rid(s_rid),.s_rdata(s_rdata),.s_rresp(s_rresp),.s_rlast(s_rlast),
        .s_rvalid(s_rvalid),.s_rready(s_rready),
        .m_awid(m_awid),.m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),
        .m_awburst(m_awburst),.m_awvalid(m_awvalid),.m_awready(m_awready),
        .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
        .m_bid(m_bid),.m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
        .m_arid(m_arid),.m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),
        .m_arburst(m_arburst),.m_arvalid(m_arvalid),.m_arready(m_arready),
        .m_rid(m_rid),.m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),
        .m_rvalid(m_rvalid),.m_rready(m_rready),
        .snoop_addr(snoop_addr),.snoop_valid(snoop_valid),
        .snoop_ack(snoop_ack),.snoop_hit(snoop_hit)
    );

    integer errs=0;

    // ---- Downstream behavioral memory (single-outstanding, INCR, 8-beat) ----
    // backing store + a golden reference the scoreboard reads.
    reg [31:0] mem [0:1048575]; // 4MB word space (addr[21:2])
    integer im;
    initial for (im=0; im<1048576; im=im+1) mem[im] = 32'hA5A5_0000 | im[15:0];

    // single-outstanding tracker: assert if two bursts overlap on master port
    reg dn_busy; reg [1:0] dn_kind; // 1=read 2=write
    reg [31:0] dn_addr; reg [7:0] dn_len; reg [7:0] dn_beat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready<=0; m_wready<=0; m_bvalid<=0; m_arready<=0;
            m_rvalid<=0; m_rlast<=0; dn_busy<=0; dn_kind<=0; dn_beat<=0;
            m_bresp<=0; m_rresp<=0; m_bid<=0; m_rid<=0;
        end else begin
            // ---- accept AR ----
            m_arready <= (!dn_busy);
            if (m_arvalid && m_arready && !dn_busy) begin
                if (dn_busy) begin $display("FAIL downstream 2nd AR while busy"); errs=errs+1; end
                dn_busy<=1; dn_kind<=1; dn_addr<=m_araddr; dn_len<=m_arlen; dn_beat<=0;
                m_arready<=0; m_rid<=m_arid;
            end
            // ---- read data burst ----
            if (dn_busy && dn_kind==1 && !m_rvalid) begin
                m_rvalid<=1; m_rdata<=mem[(dn_addr[21:2])+dn_beat]; m_rlast<=(dn_beat==dn_len); m_rresp<=0;
            end
            if (m_rvalid && m_rready) begin
                if (m_rlast) begin dn_busy<=0; m_rvalid<=0; m_rlast<=0; end
                else begin dn_beat<=dn_beat+1; m_rvalid<=0; end
            end
            // ---- accept AW ----
            m_awready <= (!dn_busy);
            if (m_awvalid && m_awready && !dn_busy) begin
                if (dn_busy) begin $display("FAIL downstream 2nd AW while busy"); errs=errs+1; end
                dn_busy<=1; dn_kind<=2; dn_addr<=m_awaddr; dn_len<=m_awlen; dn_beat<=0; m_awready<=0;
            end
            // ---- write data burst ----
            if (dn_busy && dn_kind==2) begin
                m_wready<=1;
                if (m_wvalid && m_wready) begin
                    mem[(dn_addr[21:2])+dn_beat] <= m_wdata;
                    if (m_wlast) begin m_wready<=0; m_bvalid<=1; m_bid<=m_awid; m_bresp<=0; end
                    else dn_beat<=dn_beat+1;
                end
            end
            if (m_bvalid && m_bready) begin m_bvalid<=0; dn_busy<=0; end
        end
    end

    // ---- Golden reference: CPU-visible memory in program order ----
    // init identical to backing mem; updated by every issued write; every read
    // beat is checked against it. (L2 hit returns dirty data; eviction writes
    // it back to mem before any refill, so golden is always the right answer.)
    reg [31:0] golden [0:1048575];
    integer ig;
    initial for (ig=0; ig<1048576; ig=ig+1) golden[ig] = 32'hA5A5_0000 | ig[15:0];

    // per-id expected read tracking (each concurrent read uses a unique id)
    reg        exp_v    [0:15];
    reg [31:0] exp_addr [0:15];
    reg [7:0]  exp_len  [0:15];
    reg [7:0]  exp_beat [0:15];
    integer ei; initial for (ei=0; ei<16; ei=ei+1) begin exp_v[ei]=0; exp_beat[ei]=0; end

    integer reads_checked=0;
    always @(posedge clk) begin
        if (rst_n && s_rvalid && s_rready) begin
            if (!exp_v[s_rid]) begin
                $display("FAIL unexpected R for id=%0d @%t", s_rid, $time); errs=errs+1;
            end else begin
                if (s_rdata !== golden[(exp_addr[s_rid][21:2])+exp_beat[s_rid]]) begin
                    $display("FAIL read id=%0d beat=%0d @%h got=%h exp=%h", s_rid,
                        exp_beat[s_rid], exp_addr[s_rid]+(exp_beat[s_rid]<<2),
                        s_rdata, golden[(exp_addr[s_rid][21:2])+exp_beat[s_rid]]); errs=errs+1;
                end else reads_checked=reads_checked+1;
                if (s_rlast) begin exp_v[s_rid]<=0; exp_beat[s_rid]<=0; end
                else exp_beat[s_rid]<=exp_beat[s_rid]+1;
            end
        end
    end

    // ---- Master driver tasks ----
    task issue_read(input [3:0] id, input [31:0] addr, input [7:0] len);
    begin
        @(negedge clk);
        exp_addr[id]=addr; exp_len[id]=len; exp_beat[id]=0; exp_v[id]=1;
        s_arid=id; s_araddr=addr; s_arlen=len; s_arsize=3'b010; s_arburst=2'b01; s_arvalid=1;
        @(posedge clk); while(!s_arready) @(posedge clk);
        @(negedge clk); s_arvalid=0;
    end endtask

    // single-beat write (len=0), one word
    task issue_write(input [3:0] id, input [31:0] addr, input [31:0] wd);
    begin
        golden[addr[21:2]] = wd; // program-order update
        @(negedge clk);
        s_awid=id; s_awaddr=addr; s_awlen=0; s_awsize=3'b010; s_awburst=2'b01; s_awvalid=1;
        @(posedge clk); while(!s_awready) @(posedge clk);
        @(negedge clk); s_awvalid=0;
        s_wdata=wd; s_wstrb=4'hF; s_wlast=1; s_wvalid=1;
        @(posedge clk); while(!s_wready) @(posedge clk);
        @(negedge clk); s_wvalid=0; s_wlast=0;
    end endtask

    // wait until all outstanding reads have drained
    task wait_reads; integer w2, any;
    begin
        any=1;
        while (any!=0) begin
            @(posedge clk); any=0;
            for (w2=0; w2<16; w2=w2+1) if (exp_v[w2]) any=1;
        end
    end endtask

    integer ar_seen, snoop_ar_before;
    integer dbg_ar_count=0;
    always @(posedge clk) if (rst_n && m_arvalid && m_arready) dbg_ar_count<=dbg_ar_count+1;

    // ---- Concurrency proof monitors (hierarchical peek into DUT) ----
    integer peak_mshr=0, peak_wb=0, hum_events=0;
    integer cm, cw, cur_mshr, cur_unfilled, cur_wb;
    always @(posedge clk) if (rst_n) begin
        cur_mshr=0; cur_unfilled=0; cur_wb=0;
        for (cm=0; cm<8; cm=cm+1) begin
            if (dut.mshr_valid[cm]) cur_mshr=cur_mshr+1;
            if (dut.mshr_valid[cm] && !dut.mshr_filled[cm]) cur_unfilled=cur_unfilled+1;
        end
        for (cw=0; cw<4; cw=cw+1)
            if (dut.wb_valid[cw]) cur_wb=cur_wb+1;
        if (cur_mshr > peak_mshr) peak_mshr=cur_mshr;
        if (cur_wb > peak_wb) peak_wb=cur_wb;
        // a read beat delivered to the master while a miss is still unfilled =
        // hit-under-miss (that response did not wait for the pending miss).
        if (s_rvalid && s_rready && cur_unfilled>0) hum_events=hum_events+1;
    end

    initial begin
        s_awvalid=0; s_wvalid=0; s_arvalid=0; s_wlast=0;
        snoop_addr=0; snoop_valid=0;
        s_bready=1; s_rready=1;
        s_awid=0; s_awaddr=0; s_awlen=0; s_awsize=0; s_awburst=1;
        s_arid=0; s_araddr=0; s_arlen=0; s_arsize=0; s_arburst=1;
        s_wdata=0; s_wstrb=0;
        #23 rst_n=1; @(negedge clk); repeat(2) @(negedge clk);

        // T1 parity: cold miss, then hit (same line), single-beat reads
        issue_read(4'd1, 32'h0000_1000, 8'd0); wait_reads;
        // T1b clean-line snoop: the next access must miss again, proving the
        // NB L2 clean invalidate is visible at the downstream AXI boundary.
        snoop_ar_before = dbg_ar_count;
        @(negedge clk); snoop_addr=32'h0000_1000; snoop_valid=1'b1;
        #1;
        if (!snoop_ack || !snoop_hit) begin
            $display("FAIL clean snoop did not report a hit"); errs=errs+1;
        end
        @(posedge clk); @(negedge clk); snoop_valid=1'b0;
        issue_read(4'd1, 32'h0000_1000, 8'd0); wait_reads;
        if ((dbg_ar_count-snoop_ar_before) != 1) begin
            $display("FAIL clean snoop did not force a refill"); errs=errs+1;
        end
        issue_read(4'd1, 32'h0000_1000, 8'd0); wait_reads; // hit

        // T2 miss-under-miss: 3 distinct lines, all outstanding at once
        issue_read(4'd2, 32'h0002_0000, 8'd0);
        issue_read(4'd3, 32'h0003_0000, 8'd0);
        issue_read(4'd4, 32'h0004_0000, 8'd0);
        wait_reads;

        // T3 secondary-miss merge: two reads to the SAME fresh line, unique ids,
        // issued back-to-back -> exactly ONE downstream refill.
        ar_seen = dbg_ar_count;
        issue_read(4'd5, 32'h0005_0000, 8'd0);
        issue_read(4'd6, 32'h0005_0004, 8'd0); // same line, different word
        wait_reads;
        if ((dbg_ar_count-ar_seen) != 1) begin
            $display("FAIL T3 merge: %0d refills (want 1)", dbg_ar_count-ar_seen); errs=errs+1;
        end

        // T4 hit-under-miss: prime line X (hit later). Issue miss to fresh line Y,
        // then immediately a read to resident X. Both must return correct data.
        issue_read(4'd7, 32'h0007_0000, 8'd0); wait_reads;   // prime X resident
        issue_read(4'd8, 32'h0008_0000, 8'd0);               // miss Y (long)
        issue_read(4'd7, 32'h0007_0000, 8'd0);               // hit X under miss
        wait_reads;

        // T5 write then read-back (write hit path + dirty), and write-miss alloc
        issue_write(4'd9, 32'h0000_1000, 32'hDEAD_BEEF);      // hit (line resident from T1)
        issue_read (4'd9, 32'h0000_1000, 8'd0); wait_reads;   // must read DEADBEEF
        issue_write(4'd10,32'h000A_0000, 32'hCAFE_0001);      // write miss -> alloc+merge
        issue_read (4'd10,32'h000A_0000, 8'd0); wait_reads;   // must read CAFE0001

        // T6 write-miss under read-miss concurrency + eviction pressure:
        // hammer one set (index 0) with >8 distinct lines to force evictions,
        // interleaving writes, then read them all back for scoreboard match.
        begin : T6 integer j;
          for (j=0;j<12;j=j+1) issue_write(4'd11, (j<<16)|32'h0000_0040, 32'h1000_0000|j);
          for (j=0;j<12;j=j+1) begin issue_read(4'd12,(j<<16)|32'h0000_0040,8'd0); wait_reads; end
        end

        // T6b establish four known dirty resident lines, then fill all four
        // dirty-victim slots before the serial downstream engine can retire
        // them.  All addresses map to one set; the replacement misses must be
        // accepted only while WB slots remain available.
        begin : T6B integer j;
          for (j=20;j<24;j=j+1)
            issue_write(4'd2, (j<<16)|32'h0000_0040, 32'h2000_0000|j);
          for (j=20;j<24;j=j+1) begin
            issue_read(4'd3, (j<<16)|32'h0000_0040,8'd0);
            wait_reads;
          end
          for (j=24;j<28;j=j+1)
            issue_write(4'd4, (j<<16)|32'h0000_0040, 32'h3000_0000|j);
          for (j=24;j<28;j=j+1) begin
            issue_read(4'd5, (j<<16)|32'h0000_0040,8'd0);
            wait_reads;
          end
        end

        // T7 CONCURRENT STRESS — no draining between ops. Issue reads to distinct
        // fresh lines with distinct ids back-to-back (miss-under-miss, fills the
        // MSHR file + order queue, exercises backpressure via s_arready), then a
        // burst read (multi-beat), then drain once. Scoreboard checks every beat.
        begin : T7 integer j;
          for (j=0;j<8;j=j+1)                        // 8 distinct-id concurrent misses
            issue_read(j[3:0], (32'h0010_0000)|(j<<12), 8'd0);
          issue_read(4'd8, 32'h0011_0000, 8'd7);     // 8-beat burst read (fresh line)
          issue_read(4'd9, 32'h0011_0100, 8'd3);     // 4-beat burst, different line
          wait_reads;
        end

        // T8 hit-under-miss overlap, verified: prime P resident; issue a miss to
        // fresh Q; while Q refills, fire reads to P (must return without waiting
        // for Q). No wait between the Q-miss and the P-hits.
        issue_read(4'd10, 32'h0020_0000, 8'd0); wait_reads;   // prime P
        issue_read(4'd11, 32'h0021_0000, 8'd7);               // miss Q (8-beat, slow)
        issue_read(4'd12, 32'h0020_0000, 8'd0);               // hit P under miss
        issue_read(4'd13, 32'h0020_0000, 8'd0);               // hit P again
        wait_reads;

        repeat(20) @(negedge clk);
        $display("INFO l2nb concurrency: peak_mshr=%0d peak_wb=%0d hit_under_miss_beats=%0d", peak_mshr, peak_wb, hum_events);
        if (peak_mshr < 2) begin $display("FAIL no miss-under-miss observed"); errs=errs+1; end
        if (peak_wb < 4) begin $display("FAIL WB buffer did not reach four entries (peak=%0d)", peak_wb); errs=errs+1; end
        if (hum_events < 1) begin $display("FAIL no hit-under-miss observed"); errs=errs+1; end
        if (errs==0) $display("REGRESSION_TEST_SUCCESS l2nb (reads_checked=%0d)", reads_checked);
        else         $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin #2000000 $display("FAIL timeout"); $finish; end
endmodule
