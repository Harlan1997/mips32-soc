// Unit test: apb_axi_dma_v2 — single-channel block copy via simple AXI slave model
module tb_dma_v2;
    reg          clk = 0;
    reg          rst_n = 0;
    // APB
    reg          psel = 0, penable = 0, pwrite = 0;
    reg  [11:0]  paddr = 0;
    reg  [31:0]  pwdata = 0;
    wire [31:0]  prdata;
    wire         pready, pslverr;
    // AXI wires
    wire [3:0]   m_awid, m_arid;
    wire [31:0]  m_awaddr, m_araddr;
    wire [7:0]   m_awlen, m_arlen;
    wire [2:0]   m_awsize, m_arsize;
    wire [1:0]   m_awburst, m_arburst;
    wire         m_awvalid, m_arvalid;
    reg          m_awready = 0, m_arready = 0;
    wire [31:0]  m_wdata;
    wire [3:0]   m_wstrb;
    wire         m_wlast, m_wvalid;
    reg          m_wready = 0;
    reg  [3:0]   m_bid = 0;
    reg  [1:0]   m_bresp = 0;
    reg          m_bvalid = 0;
    wire         m_bready;
    reg  [3:0]   m_rid = 0;
    reg  [31:0]  m_rdata = 0;
    reg  [1:0]   m_rresp = 0;
    reg          m_rlast = 0;
    reg          m_rvalid = 0;
    wire         m_rready;
    wire [3:0]   ch_int;

    integer errs = 0;

    always #5 clk = ~clk;

    apb_axi_dma_v2 #(.N_CHANNELS(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .ch_int(ch_int));

    // Simple AXI-slave model: memory-backed store, always-ready AR/AW/W,
    // 1-cycle-later response.
    reg [31:0] mem [0:255];
    integer mi;
    reg [31:0] latched_read_addr;
    reg        latched_read_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready <= 1;
            m_wready  <= 1;
            m_arready <= 1;
            m_bvalid  <= 0;
            m_rvalid  <= 0;
            m_bresp   <= 0;
            m_rresp   <= 0;
            m_rlast   <= 1;
            latched_read_valid <= 0;
        end else begin
            // Read pipeline
            if (m_rvalid && m_rready) m_rvalid <= 0;
            if (m_arvalid && m_arready) begin
                latched_read_addr  <= m_araddr;
                latched_read_valid <= 1;
            end
            if (latched_read_valid && !m_rvalid) begin
                m_rdata <= mem[latched_read_addr[9:2]];
                m_rvalid <= 1;
                latched_read_valid <= 0;
            end
            // Write pipeline: capture AW+W simultaneously (both ready always)
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_awvalid && m_awready && m_wvalid && m_wready) begin
                mem[m_awaddr[9:2]] <= m_wdata;
                m_bvalid <= 1;
            end
        end
    end

    task apb_write(input [11:0] a, input [31:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 1; paddr = a; pwdata = d;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        psel = 0; pwrite = 0; penable = 0;
    end
    endtask

    initial begin
        // Seed source memory
        for (mi = 0; mi < 8; mi = mi + 1)
            mem[mi] = 32'hDEAD_0000 + mi;
        // Zero destination region
        for (mi = 32; mi < 40; mi = mi + 1)
            mem[mi] = 32'h0;

        #12 rst_n = 1;
        @(negedge clk);

        // Program channel 0: copy 8 words (32B) from 0x0 → 0x80
        apb_write(12'h044, 32'h0);           // SRC (ch0 SRC at 0x40+0x4=0x44)
        apb_write(12'h048, 32'h80);          // DST
        apb_write(12'h04C, 32'd32);          // LEN = 32 bytes
        apb_write(12'h040, 32'h0000_0001);   // CTRL: EN, SG=0, INT_EN=0
        // Global enable
        apb_write(12'h000, 32'h0000_0001);

        // Wait for last word to appear
        begin: wait_done
            integer wait_cycles;
            wait_cycles = 0;
            while (mem[39] !== 32'hDEAD_0007 && wait_cycles < 5000) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        // Verify destination has source data
        for (mi = 0; mi < 8; mi = mi + 1) begin
            if (mem[32 + mi] !== 32'hDEAD_0000 + mi) begin
                $display("FAIL word %0d: mem[dst]=%h expected %h",
                         mi, mem[32 + mi], 32'hDEAD_0000 + mi);
                errs = errs + 1;
            end
        end

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS dma_v2");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #500000 $display("FAIL timeout"); $finish;
    end
endmodule
