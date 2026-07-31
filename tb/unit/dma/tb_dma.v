// Unit test: apb_axi_dma — Phase 4C DUT commercial readiness unit test
module tb_dma;
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

    apb_axi_dma #(
        .N_CHANNELS(4),
        .MAX_DESCRIPTORS(16)
    ) dut (
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

    // AXI-slave model
    reg [31:0] mem [0:511];
    integer mi;
    reg [31:0] latched_read_addr;
    reg        latched_read_valid;

    reg inject_rerr = 0;
    reg inject_werr = 0;
    reg stall_ar    = 0;

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
            m_arready <= ~stall_ar;
            // Read pipeline
            if (m_rvalid && m_rready) m_rvalid <= 0;
            if (m_arvalid && m_arready) begin
                latched_read_addr  <= m_araddr;
                latched_read_valid <= 1;
            end
            if (latched_read_valid && !m_rvalid) begin
                m_rdata  <= mem[latched_read_addr[10:2]];
                m_rresp  <= inject_rerr ? 2'b10 : 2'b00;
                m_rvalid <= 1;
                latched_read_valid <= 0;
            end
            // Write pipeline
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_awvalid && m_awready && m_wvalid && m_wready) begin
                mem[m_awaddr[10:2]] <= m_wdata;
                m_bresp  <= inject_werr ? 2'b10 : 2'b00;
                m_bvalid <= 1;
            end
        end
    end

    // AR channel stability checker: once ARVALID asserts without ARREADY,
    // it must stay asserted with an unchanged payload until accepted.
    reg        ar_hold_q = 0;
    reg [31:0] ar_addr_q = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_hold_q <= 0;
            ar_addr_q <= 0;
        end else begin
            if (ar_hold_q) begin
                if (!m_arvalid) begin
                    $display("FAIL ARVALID deasserted before ARREADY");
                    errs = errs + 1;
                end else if (m_araddr !== ar_addr_q) begin
                    $display("FAIL AR payload changed while ARVALID waited for ARREADY: %h -> %h",
                              ar_addr_q, m_araddr);
                    errs = errs + 1;
                end
            end
            ar_hold_q <= m_arvalid && !m_arready;
            ar_addr_q <= m_araddr;
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

    task apb_read(input [11:0] a, output [31:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 0; paddr = a;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        d = prdata;
        psel = 0; penable = 0;
    end
    endtask

    reg [31:0] rd_val;

    initial begin
        for (mi = 0; mi < 16; mi = mi + 1)
            mem[mi] = 32'hDEAD_0000 + mi;
        for (mi = 32; mi < 48; mi = mi + 1)
            mem[mi] = 32'h0;

        #12 rst_n = 1;
        @(negedge clk);

        // Global enable
        apb_write(12'h100, 32'h1);

        // ---- Test 1: Direct Copy ----
        apb_write(12'h044, 32'h0);           // SRC (ch0)
        apb_write(12'h048, 32'h80);          // DST
        apb_write(12'h04C, 32'd32);          // LEN = 32 bytes
        apb_write(12'h040, 32'h0000_0001);   // CTRL: EN=1

        begin: wait_direct_done
            integer wait_cycles;
            wait_cycles = 0;
            rd_val = 0;
            while ((rd_val[1] == 1'b0) && (wait_cycles < 5000)) begin
                apb_read(12'h054, rd_val); // read ch0 STATUS
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        if ((rd_val & 32'h3F) !== 32'h02) begin // DONE=1, BUSY=0, ERR=0, ERR_CODE=0
            $display("FAIL direct copy STATUS got %h expected 0x02", rd_val);
            errs = errs + 1;
        end

        for (mi = 0; mi < 8; mi = mi + 1) begin
            if (mem[32 + mi] !== 32'hDEAD_0000 + mi) begin
                $display("FAIL direct copy word %0d: mem[dst]=%h expected %h",
                         mi, mem[32 + mi], 32'hDEAD_0000 + mi);
                errs = errs + 1;
            end
        end

        // W1C DONE
        apb_write(12'h040, 32'h0000_0008); // CTRL bit 3 W1C DONE
        apb_read(12'h054, rd_val);
        if (rd_val[1] !== 1'b0) begin
            $display("FAIL direct copy W1C DONE failed, STATUS=%h", rd_val);
            errs = errs + 1;
        end

        // ---- Test 2: Scatter-Gather (SG) ----
        mem[64] = 32'h0;    // SRC
        mem[65] = 32'h180;  // DST
        mem[66] = 32'd16;   // LEN
        mem[67] = 32'h110;  // NEXT
        mem[68] = 32'h10;   // SRC
        mem[69] = 32'h190;  // DST
        mem[70] = 32'd16;   // LEN
        mem[71] = 32'h0;    // NEXT

        for (mi = 96; mi < 104; mi = mi + 1) mem[mi] = 32'h0;

        apb_write(12'h090, 32'h100);         // ch1 DESC_HEAD
        apb_write(12'h080, 32'h0000_0003);   // CTRL: EN=1, SG=1

        begin: wait_sg_done
            integer wait_cycles;
            wait_cycles = 0;
            rd_val = 0;
            while ((rd_val[1] == 1'b0) && (wait_cycles < 5000)) begin
                apb_read(12'h094, rd_val); // ch1 STATUS
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        if ((rd_val & 32'h3F) !== 32'h02) begin
            $display("FAIL SG copy STATUS got %h expected 0x02", rd_val);
            errs = errs + 1;
        end

        for (mi = 0; mi < 8; mi = mi + 1) begin
            if (mem[96 + mi] !== 32'hDEAD_0000 + mi) begin
                $display("FAIL SG copy word %0d: mem[dst]=%h expected %h",
                         mi, mem[96 + mi], 32'hDEAD_0000 + mi);
                errs = errs + 1;
            end
        end
        apb_write(12'h080, 32'h0000_0008); // W1C DONE

        // ---- Test 3: AXI Read Error Handling (ERR_AXI_READ = 2) ----
        inject_rerr = 1;
        apb_write(12'h0C4, 32'h0);           // ch2 SRC
        apb_write(12'h0C8, 32'h200);         // DST
        apb_write(12'h0CC, 32'd16);          // LEN
        apb_write(12'h0C0, 32'h0000_0005);   // CTRL: EN=1, INT_EN=1

        repeat (20) @(negedge clk);
        apb_read(12'h0D4, rd_val);           // ch2 STATUS
        if (rd_val[2] !== 1'b1 || ((rd_val >> 3) & 3'h7) !== 3'd2) begin
            $display("FAIL AXI read error: expected ERR=1, ERR_CODE=2, got STATUS=%h", rd_val);
            errs = errs + 1;
        end
        if (ch_int[2] !== 1'b1) begin
            $display("FAIL AXI read error: ch_int[2] expected 1");
            errs = errs + 1;
        end
        inject_rerr = 0;
        apb_write(12'h0C0, 32'h0000_0018);   // W1C DONE and ERR (bits 3, 4)
        apb_read(12'h0D4, rd_val);
        if ((rd_val & 32'h3F) !== 32'h0) begin
            $display("FAIL W1C ERR/DONE failed for AXI read error, STATUS=%h", rd_val);
            errs = errs + 1;
        end

        // ---- Test 4: AXI Write Error Handling (ERR_AXI_WRITE = 3) ----
        inject_werr = 1;
        apb_write(12'h0C4, 32'h0);           // ch2 SRC
        apb_write(12'h0C8, 32'h200);         // DST
        apb_write(12'h0CC, 32'd16);          // LEN
        apb_write(12'h0C0, 32'h0000_0001);   // CTRL: EN=1

        repeat (20) @(negedge clk);
        apb_read(12'h0D4, rd_val);           // ch2 STATUS
        if (rd_val[2] !== 1'b1 || ((rd_val >> 3) & 3'h7) !== 3'd3) begin
            $display("FAIL AXI write error: expected ERR=1, ERR_CODE=3, got STATUS=%h", rd_val);
            errs = errs + 1;
        end
        inject_werr = 0;
        apb_write(12'h0C0, 32'h0000_0018);   // W1C DONE and ERR

        // ---- Test 5: Unaligned Direct-Mode Configuration (ERR_ALIGN = 1) ----
        apb_write(12'h044, 32'h2);           // ch0 SRC unaligned (0x2)
        apb_write(12'h048, 32'h80);          // DST
        apb_write(12'h04C, 32'd16);          // LEN
        apb_write(12'h040, 32'h0000_0001);   // CTRL: EN=1

        repeat (5) @(negedge clk);
        apb_read(12'h054, rd_val);           // ch0 STATUS
        if (rd_val[2] !== 1'b1 || ((rd_val >> 3) & 3'h7) !== 3'd1) begin
            $display("FAIL Unaligned direct mode: expected ERR=1, ERR_CODE=1, got STATUS=%h", rd_val);
            errs = errs + 1;
        end
        apb_write(12'h040, 32'h0000_0018);   // W1C DONE and ERR

        // ---- Test 6: Malformed SG Descriptor (ERR_DESC = 4) ----
        mem[64] = 32'h0;    // SRC
        mem[65] = 32'h180;  // DST
        mem[66] = 32'd15;   // LEN unaligned (15)
        mem[67] = 32'h0;    // NEXT

        apb_write(12'h090, 32'h100);         // ch1 DESC_HEAD
        apb_write(12'h080, 32'h0000_0003);   // CTRL: EN=1, SG=1

        repeat (30) @(negedge clk);
        apb_read(12'h094, rd_val);           // ch1 STATUS
        if (rd_val[2] !== 1'b1 || ((rd_val >> 3) & 3'h7) !== 3'd4) begin
            $display("FAIL Malformed SG desc: expected ERR=1, ERR_CODE=4, got STATUS=%h", rd_val);
            errs = errs + 1;
        end
        apb_write(12'h080, 32'h0000_0018);   // W1C DONE and ERR

        // ---- Test 7: Descriptor Limit / Cycle (ERR_DESC_LIMIT = 5) ----
        // Create cyclic descriptor chain: 0x100 -> 0x100
        mem[64] = 32'h0;    // SRC
        mem[65] = 32'h180;  // DST
        mem[66] = 32'd16;   // LEN
        mem[67] = 32'h100;  // NEXT points back to self!

        apb_write(12'h090, 32'h100);         // ch1 DESC_HEAD
        apb_write(12'h080, 32'h0000_0003);   // CTRL: EN=1, SG=1

        begin: wait_limit_done
            integer wait_cycles;
            wait_cycles = 0;
            rd_val = 0;
            while ((rd_val[1] == 1'b0) && (wait_cycles < 5000)) begin
                apb_read(12'h094, rd_val); // ch1 STATUS
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        if (rd_val[2] !== 1'b1 || ((rd_val >> 3) & 3'h7) !== 3'd5) begin
            $display("FAIL SG descriptor limit: expected ERR=1, ERR_CODE=5, got STATUS=%h", rd_val);
            errs = errs + 1;
        end
        apb_write(12'h080, 32'h0000_0018);   // W1C DONE and ERR

        // ---- Test 8: Busy Reprogramming Protection ----
        // Seed source
        for (mi = 0; mi < 32; mi = mi + 1)
            mem[mi] = 32'hBABE_0000 + mi;
        for (mi = 128; mi < 160; mi = mi + 1)
            mem[mi] = 32'h0;

        apb_write(12'h044, 32'h0);           // ch0 SRC = 0x0
        apb_write(12'h048, 32'h200);         // ch0 DST = 0x200 (mem[128])
        apb_write(12'h04C, 32'd128);         // ch0 LEN = 128 bytes (32 words)
        apb_write(12'h040, 32'h0000_0001);   // CTRL: EN=1

        // While busy, attempt to overwrite registers
        repeat (3) @(negedge clk);
        apb_write(12'h044, 32'h100);         // attempt change SRC
        apb_write(12'h048, 32'h300);         // attempt change DST
        apb_write(12'h04C, 32'd16);          // attempt change LEN

        begin: wait_busy_done
            integer wait_cycles;
            wait_cycles = 0;
            rd_val = 0;
            while ((rd_val[1] == 1'b0) && (wait_cycles < 5000)) begin
                apb_read(12'h054, rd_val); // ch0 STATUS
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        // Verify full 32 words transferred to original DST 0x200
        for (mi = 0; mi < 32; mi = mi + 1) begin
            if (mem[128 + mi] !== 32'hBABE_0000 + mi) begin
                $display("FAIL busy reprogram word %0d: mem[dst]=%h expected %h",
                         mi, mem[128 + mi], 32'hBABE_0000 + mi);
                errs = errs + 1;
            end
        end
        apb_write(12'h040, 32'h0000_0008);   // W1C DONE

        // ---- Test 9: IRQ Pending & W1C behavior ----
        apb_write(12'h044, 32'h0);           // ch0 SRC
        apb_write(12'h048, 32'h80);          // ch0 DST
        apb_write(12'h04C, 32'd16);          // ch0 LEN
        apb_write(12'h040, 32'h0000_0005);   // CTRL: EN=1, INT_EN=1

        repeat (25) @(negedge clk);
        if (ch_int[0] !== 1'b1) begin
            $display("FAIL ch_int[0] expected 1 when DONE set");
            errs = errs + 1;
        end
        apb_read(12'h104, rd_val);           // IRQ_STATUS global
        if (rd_val[0] !== 1'b1) begin
            $display("FAIL IRQ_STATUS bit 0 expected 1, got %h", rd_val);
            errs = errs + 1;
        end

        apb_write(12'h040, 32'h0000_0008);   // W1C DONE
        if (ch_int[0] !== 1'b0) begin
            $display("FAIL ch_int[0] expected 0 after W1C DONE");
            errs = errs + 1;
        end

        // ---- Test 10: Arbiter lock vs lower-channel busy while higher
        //      channel has an outstanding, unaccepted AR (act_ch must not
        //      flip mid-transaction; the AR stability checker above will
        //      flag any violation) ----
        mem[200] = 32'hAAAA_0000; mem[201] = 32'hAAAA_0001;
        mem[202] = 32'hAAAA_0002; mem[203] = 32'hAAAA_0003;
        mem[210] = 32'h0; mem[211] = 32'h0; mem[212] = 32'h0; mem[213] = 32'h0;
        mem[220] = 32'hBBBB_0000; mem[221] = 32'hBBBB_0001;
        mem[222] = 32'hBBBB_0002; mem[223] = 32'hBBBB_0003;
        mem[230] = 32'h0; mem[231] = 32'h0; mem[232] = 32'h0; mem[233] = 32'h0;

        stall_ar = 1;

        // Higher-numbered channel (ch2) starts first and becomes sole busy
        // channel; it will assert ARVALID and stall waiting for ARREADY.
        apb_write(12'h0C4, 32'h320);         // ch2 SRC = mem[200]
        apb_write(12'h0C8, 32'h348);         // ch2 DST = mem[210]
        apb_write(12'h0CC, 32'd16);          // ch2 LEN
        apb_write(12'h0C0, 32'h0000_0001);   // CTRL: EN=1

        repeat (4) @(negedge clk);           // let ch2 reach ST_EXEC_R w/ AR stalled

        // Lower-numbered channel (ch0) becomes busy while ch2's AR is
        // still outstanding-but-unaccepted. Pre-fix, the combinational
        // "lowest busy" arbiter would flip act_ch to ch0 immediately.
        apb_write(12'h044, 32'h370);         // ch0 SRC = mem[220]
        apb_write(12'h048, 32'h398);         // ch0 DST = mem[230]
        apb_write(12'h04C, 32'd16);          // ch0 LEN
        apb_write(12'h040, 32'h0000_0001);   // CTRL: EN=1

        repeat (10) @(negedge clk);          // hold the stall well past ch0 going busy

        stall_ar = 0;

        begin: wait_arb_lock_done
            integer wait_cycles;
            reg [31:0] st0, st2;
            wait_cycles = 0;
            st0 = 0; st2 = 0;
            while (((st0[1] == 1'b0) || (st2[1] == 1'b0)) && (wait_cycles < 5000)) begin
                apb_read(12'h054, st0); // ch0 STATUS
                apb_read(12'h0D4, st2); // ch2 STATUS
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end
        end

        for (mi = 0; mi < 4; mi = mi + 1) begin
            if (mem[210 + mi] !== mem[200 + mi]) begin
                $display("FAIL arb lock ch2 word %0d: mem[dst]=%h expected %h",
                         mi, mem[210 + mi], mem[200 + mi]);
                errs = errs + 1;
            end
            if (mem[230 + mi] !== mem[220 + mi]) begin
                $display("FAIL arb lock ch0 word %0d: mem[dst]=%h expected %h",
                         mi, mem[230 + mi], mem[220 + mi]);
                errs = errs + 1;
            end
        end
        apb_write(12'h040, 32'h0000_0008);   // ch0 W1C DONE
        apb_write(12'h0C0, 32'h0000_0008);   // ch2 W1C DONE

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS dma");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #500000 $display("FAIL timeout"); $finish;
    end
endmodule
