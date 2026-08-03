// Unit test: apb_uart_16550 — Phase 4E Commercial Hardening Unit Gate
// Comprehensive 15-case unit verification for PC16550D UART contract.

module tb_uart_16550;
    reg          clk = 0;
    reg          rst_n = 0;
    reg          psel = 0, penable = 0, pwrite = 0;
    reg  [4:0]   paddr = 0;
    reg  [3:0]   pstrb = 4'hF;
    reg  [31:0]  pwdata = 0;
    wire [31:0]  prdata;
    wire         pready, pslverr;
    wire         uart_tx;
    wire         uart_rts_n;
    reg          cts_n = 1'b0;
    wire         irq;
    wire         rx_irq;
    wire         tx_irq;

    integer errs = 0;

    always #5 clk = ~clk;

    apb_uart_16550 #(.TX_FIFO_DEPTH(16), .RX_FIFO_DEPTH(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .uart_tx(uart_tx), .uart_rx(1'b1),
        .uart_rts_n(uart_rts_n), .uart_cts_n(cts_n),
        .uart_dtr_n(), .uart_dsr_n(1'b0),
        .uart_dcd_n(1'b0), .uart_ri_n(1'b1),
        .irq(irq), .rx_irq(rx_irq), .tx_irq(tx_irq));

    task apb_write_strb(input [4:0] a, input [31:0] d, input [3:0] s);
    begin
        @(negedge clk);
        psel = 1; pwrite = 1; paddr = a; pwdata = d; pstrb = s;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        psel = 0; pwrite = 0; penable = 0; pstrb = 4'hF;
    end
    endtask

    task apb_write(input [4:0] a, input [7:0] d);
        apb_write_strb(a, {24'h0, d}, 4'h1);
    endtask

    task apb_read(input [4:0] a, output [31:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 0; paddr = a;
        @(negedge clk);
        penable = 1;
        #1;
        d = prdata;
        if (pready !== 1'b1 || pslverr !== 1'b0) begin
            $display("FAIL APB handshake at addr %h: pready=%b pslverr=%b", a, pready, pslverr);
            errs = errs + 1;
        end
        @(negedge clk);
        psel = 0; penable = 0;
    end
    endtask

    reg [31:0] rd_data;
    integer i;
    reg [7:0] test_data [0:15];

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            test_data[i] = 8'h10 + i;
        end

        #12 rst_n = 1;
        @(negedge clk);

        // =====================================================================
        // Case 1: Reset Defaults
        // =====================================================================
        $display("--- Case 1: Reset Defaults ---");
        apb_read(5'h0C, rd_data); // LCR
        if (rd_data[7:0] !== 8'h03) begin
            $display("FAIL Case 1 reset LCR: got %h expected 03", rd_data[7:0]); errs = errs + 1;
        end
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[6:5] !== 2'b11 || rd_data[0] !== 1'b0) begin
            $display("FAIL Case 1 reset LSR: got %h expected THRE/TEMT set, DR clear", rd_data[7:0]); errs = errs + 1;
        end
        apb_read(5'h08, rd_data); // IIR
        if (rd_data[0] !== 1'b1) begin
            $display("FAIL Case 1 reset IIR: got %h expected bit0=1 (no pending int)", rd_data[7:0]); errs = errs + 1;
        end
        if (irq !== 1'b0) begin
            $display("FAIL Case 1 reset IRQ asserted"); errs = errs + 1;
        end

        // =====================================================================
        // Case 2: DLAB DLL/DLM vs RBR/THR/IER Access Separation
        // =====================================================================
        $display("--- Case 2: DLAB Access Separation ---");
        apb_write(5'h0C, 8'h83); // DLAB = 1
        apb_write(5'h00, 8'd12); // DLL = 12
        apb_write(5'h04, 8'd0);  // DLM = 0
        apb_read(5'h00, rd_data);
        if (rd_data[7:0] !== 8'd12) begin
            $display("FAIL Case 2 DLL readback: got %h expected 12", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h0C, 8'h03); // DLAB = 0
        apb_write(5'h04, 8'h0F); // IER = 0x0F
        apb_read(5'h04, rd_data);
        if (rd_data[7:0] !== 8'h0F) begin
            $display("FAIL Case 2 IER readback (DLAB=0): got %h expected 0F", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h0C, 8'h83); // DLAB = 1
        apb_read(5'h04, rd_data); // DLM
        if (rd_data[7:0] !== 8'd0) begin
            $display("FAIL Case 2 DLM readback unaffected by IER: got %h expected 0", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h00, 8'd1);  // Restore DLL = 1
        apb_write(5'h0C, 8'h03); // DLAB = 0
        apb_write(5'h04, 8'h00); // Clear IER

        // =====================================================================
        // Case 3: SCR Read/Write
        // =====================================================================
        $display("--- Case 3: SCR Read/Write ---");
        apb_write(5'h1C, 8'hC5);
        apb_read(5'h1C, rd_data);
        if (rd_data[7:0] !== 8'hC5) begin
            $display("FAIL Case 3 SCR readback 1: got %h expected C5", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h1C, 8'h5A);
        apb_read(5'h1C, rd_data);
        if (rd_data[7:0] !== 8'h5A) begin
            $display("FAIL Case 3 SCR readback 2: got %h expected 5A", rd_data[7:0]); errs = errs + 1;
        end

        // =====================================================================
        // Case 4: Byte Strobe Contract
        // =====================================================================
        $display("--- Case 4: Byte Strobe Contract ---");
        // Low-byte write pstrb=4'h1
        apb_write_strb(5'h1C, 32'h000000A5, 4'h1);
        apb_read(5'h1C, rd_data);
        if (rd_data[7:0] !== 8'hA5) begin
            $display("FAIL Case 4 pstrb[0]: got %h expected A5", rd_data[7:0]); errs = errs + 1;
        end
        // Non-low-byte write pstrb=4'h4 (byte 2: 0x37)
        apb_write_strb(5'h1C, 32'h00370000, 4'h4);
        apb_read(5'h1C, rd_data);
        if (rd_data[7:0] !== 8'h37) begin
            $display("FAIL Case 4 pstrb[2]: got %h expected 37", rd_data[7:0]); errs = errs + 1;
        end
        // Non-low-byte write pstrb=4'h8 (byte 3: 0xB8)
        apb_write_strb(5'h1C, 32'hB8000000, 4'h8);
        apb_read(5'h1C, rd_data);
        if (rd_data[7:0] !== 8'hB8) begin
            $display("FAIL Case 4 pstrb[3]: got %h expected B8", rd_data[7:0]); errs = errs + 1;
        end

        // =====================================================================
        // Case 5: FIFO Enable / Disable Behavior & IIR Prefix
        // =====================================================================
        $display("--- Case 5: FIFO Enable / Disable Behavior ---");
        apb_write(5'h08, 8'h01); // FCR: FIFO_EN=1
        apb_read(5'h08, rd_data); // Read IIR
        if (rd_data[7:6] !== 2'b11) begin
            $display("FAIL Case 5 FIFO enabled IIR prefix: got %h expected C0", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h08, 8'h00); // FCR: FIFO_EN=0
        apb_read(5'h08, rd_data); // Read IIR
        if (rd_data[7:6] !== 2'b00) begin
            $display("FAIL Case 5 FIFO disabled IIR prefix: got %h expected 00", rd_data[7:0]); errs = errs + 1;
        end

        // =====================================================================
        // Case 6: FCR RX/TX Reset & Self-Clearing Reset Bits
        // =====================================================================
        $display("--- Case 6: FCR RX/TX Reset Behavior ---");
        apb_write(5'h10, 8'h10); // MCR.LOOP = 1
        apb_write(5'h08, 8'h01); // FCR: FIFO_EN=1
        apb_write(5'h00, 8'hA1); // Send 1 byte to RX FIFO
        #20000;
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[0] !== 1'b1) begin
            $display("FAIL Case 6 RX byte not received before reset"); errs = errs + 1;
        end
        // Issue RCVR_RESET (FCR bit 1)
        apb_write(5'h08, 8'h03); // FIFO_EN=1, RCVR_RESET=1
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[0] !== 1'b0) begin
            $display("FAIL Case 6 RCVR_RESET did not clear RX FIFO"); errs = errs + 1;
        end
        // Issue XFR_RESET (FCR bit 2)
        apb_write(5'h08, 8'h05); // FIFO_EN=1, XFR_RESET=1
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[6:5] !== 2'b11) begin
            $display("FAIL Case 6 XFR_RESET did not reset TX FIFO state"); errs = errs + 1;
        end

        // =====================================================================
        // Case 7: FIFO Trigger Levels (1, 4, 8, 14) and RX Data Interrupt
        // =====================================================================
        $display("--- Case 7: FIFO Trigger Levels ---");
        apb_write(5'h04, 8'h01); // IER: ERBFI enabled

        // Trigger Level 00 (1 byte)
        apb_write(5'h08, 8'h01); // FCR: FIFO_EN=1, trig=1
        apb_write(5'h00, 8'hD1);
        #20000;
        if (!irq) begin $display("FAIL Case 7 trig 1 IRQ missing"); errs = errs + 1; end
        apb_read(5'h00, rd_data); // Clear byte

        // Trigger Level 01 (4 bytes)
        apb_write(5'h08, 8'h41); // FCR: trig=4
        for (i = 0; i < 3; i = i + 1) apb_write(5'h00, test_data[i]);
        #500; // Small delay (before timeout)
        if (irq) begin $display("FAIL Case 7 trig 4 premature IRQ for 3 bytes"); errs = errs + 1; end
        apb_write(5'h00, test_data[3]); // 4th byte
        #20000;
        if (!irq) begin $display("FAIL Case 7 trig 4 IRQ missing for 4 bytes"); errs = errs + 1; end
        apb_write(5'h08, 8'h43); // Clear RX FIFO via RCVR_RESET

        // Trigger Level 10 (8 bytes)
        apb_write(5'h08, 8'h81); // FCR: trig=8
        for (i = 0; i < 7; i = i + 1) apb_write(5'h00, test_data[i]);
        #500;
        if (irq) begin $display("FAIL Case 7 trig 8 premature IRQ for 7 bytes"); errs = errs + 1; end
        apb_write(5'h00, test_data[7]); // 8th byte
        #20000;
        if (!irq) begin $display("FAIL Case 7 trig 8 IRQ missing for 8 bytes"); errs = errs + 1; end
        apb_write(5'h08, 8'h83); // Clear RX FIFO

        // Trigger Level 11 (14 bytes)
        apb_write(5'h08, 8'hC1); // FCR: trig=14
        for (i = 0; i < 13; i = i + 1) apb_write(5'h00, test_data[i]);
        #500;
        if (irq) begin $display("FAIL Case 7 trig 14 premature IRQ for 13 bytes"); errs = errs + 1; end
        apb_write(5'h00, test_data[13]); // 14th byte
        #40000; // Delay for all 14 bytes to be received in loopback
        if (!irq) begin $display("FAIL Case 7 trig 14 IRQ missing for 14 bytes"); errs = errs + 1; end
        apb_write(5'h08, 8'hC3); // Clear RX FIFO
        apb_write(5'h04, 8'h00); // Disable IER

        // =====================================================================
        // Case 8: RX Timeout Interrupt (CTI) & Clear Semantics
        // =====================================================================
        $display("--- Case 8: RX Timeout Interrupt & Clear ---");
        apb_write(5'h08, 8'h41); // FCR: trig=4
        apb_write(5'h04, 8'h01); // IER: ERBFI enabled
        apb_write(5'h00, 8'hE1);
        apb_write(5'h00, 8'hE2); // 2 bytes (below threshold 4)
        #50000; // Wait for character timeout
        if (!irq) begin $display("FAIL Case 8 CTI did not assert"); errs = errs + 1; end
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b1100) begin
            $display("FAIL Case 8 CTI IIR code: got %h expected xC", rd_data[7:0]); errs = errs + 1;
        end
        // Clear on RBR read
        apb_read(5'h00, rd_data); // Read 1 byte
        #100;
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] == 4'b1100) begin
            $display("FAIL Case 8 CTI not cleared immediately after RBR read"); errs = errs + 1;
        end
        // Test clear on RCVR_RESET
        #50000; // Let timeout fire again on remaining 1 byte
        if (!irq) begin $display("FAIL Case 8 CTI re-assert missing"); errs = errs + 1; end
        apb_write(5'h08, 8'h43); // RCVR_RESET
        #100;
        if (irq) begin $display("FAIL Case 8 CTI not cleared by RCVR_RESET"); errs = errs + 1; end
        apb_write(5'h04, 8'h00);

        // =====================================================================
        // Case 9: IIR Priority Order (LSI > RDA/CTI > THRE > Modem)
        // =====================================================================
        $display("--- Case 9: IIR Priority Order ---");
        apb_write(5'h08, 8'h00); // FIFO_EN=0 (single-byte mode)
        apb_write(5'h10, 8'h11); // LOOP=1, DTR=1 (trigger Modem delta)
        apb_write(5'h00, 8'hF1);
        apb_write(5'h00, 8'hF2); // Trigger OE (LSI)
        #20000;
        apb_write(5'h04, 8'h0F); // Enable all 4 interrupt sources

        // Priority 1: LSI
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0110) begin
            $display("FAIL Case 9 Prio 1 LSI expected 06, got %h", rd_data[7:0]); errs = errs + 1;
        end
        apb_read(5'h14, rd_data); // Read LSR -> clears LSI (OE)

        // Priority 2: RDA
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0100) begin
            $display("FAIL Case 9 Prio 2 RDA expected 04, got %h", rd_data[7:0]); errs = errs + 1;
        end
        apb_read(5'h00, rd_data); // Read RBR -> clears RDA

        // Priority 3: THRE
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0010) begin
            $display("FAIL Case 9 Prio 3 THRE expected 02, got %h", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h04, 8'h0D); // Disable ETBEI -> clears THRE pending

        // Priority 4: Modem
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0000) begin
            $display("FAIL Case 9 Prio 4 Modem expected 00, got %h", rd_data[7:0]); errs = errs + 1;
        end
        apb_read(5'h18, rd_data); // Read MSR -> clears Modem delta

        // Priority None: 01
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0001) begin
            $display("FAIL Case 9 No-pending expected 01, got %h", rd_data[7:0]); errs = errs + 1;
        end

        // =====================================================================
        // Case 10: TX Empty Interrupt (THRE) Enable and Clear
        // =====================================================================
        $display("--- Case 10: TX Empty Interrupt (THRE) Enable & Clear ---");
        apb_write(5'h04, 8'h02); // Enable ETBEI (IER[1])
        #100;
        if (!irq) begin $display("FAIL Case 10 THRE IRQ missing when TX empty"); errs = errs + 1; end
        if (!tx_irq || rx_irq) begin $display("FAIL Case 10 IRQ split: tx=%b rx=%b", tx_irq, rx_irq); errs = errs + 1; end
        apb_read(5'h08, rd_data);
        if (rd_data[3:0] !== 4'b0010) begin
            $display("FAIL Case 10 THRE IIR code expected 02, got %h", rd_data[7:0]); errs = errs + 1;
        end
        // Clear by disabling ETBEI
        apb_write(5'h04, 8'h00);
        #100;
        if (irq) begin $display("FAIL Case 10 THRE IRQ did not clear after IER write"); errs = errs + 1; end

        // =====================================================================
        // Case 11: Loopback TX->RX Data Path (8N1 FIFO Mode)
        // =====================================================================
        $display("--- Case 11: Loopback TX->RX Data Path ---");
        apb_write(5'h08, 8'h01); // FIFO_EN=1
        apb_write(5'h10, 8'h10); // LOOP=1
        apb_write(5'h04, 8'h01); // Enable RDA for the RX-specific source
        for (i = 0; i < 8; i = i + 1) begin
            apb_write(5'h00, test_data[i]);
        end
        #50000;
        if (!rx_irq || tx_irq) begin $display("FAIL Case 11 IRQ split: tx=%b rx=%b", tx_irq, rx_irq); errs = errs + 1; end
        for (i = 0; i < 8; i = i + 1) begin
            apb_read(5'h00, rd_data);
            if (rd_data[7:0] !== test_data[i]) begin
                $display("FAIL Case 11 loopback byte %0d: got %h expected %h", i, rd_data[7:0], test_data[i]);
                errs = errs + 1;
            end
        end
        #100;
        if (rx_irq) begin $display("FAIL Case 11 RX IRQ did not clear after FIFO drain"); errs = errs + 1; end

        // =====================================================================
        // Case 12: Single-Byte Mode (FIFO_EN=0) & RX Overrun
        // =====================================================================
        $display("--- Case 12: Single-Byte Mode & RX Overrun ---");
        apb_write(5'h08, 8'h00); // FIFO_EN=0
        apb_write(5'h00, 8'h11);
        apb_write(5'h00, 8'h22); // 2nd byte sent while 1st unread -> overrun
        #20000;
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[1] !== 1'b1) begin
            $display("FAIL Case 12 LSR OE bit not set on single-byte overrun"); errs = errs + 1;
        end
        apb_read(5'h14, rd_data); // Reading LSR clears OE
        if (rd_data[1] !== 1'b0) begin
            $display("FAIL Case 12 LSR OE bit not cleared by LSR read"); errs = errs + 1;
        end
        apb_read(5'h00, rd_data); // Clear single byte

        // =====================================================================
        // Case 13: LSR Error Visibility and Pop/Read-Clear Behavior
        // =====================================================================
        $display("--- Case 13: LSR Error Visibility & Read-Clear/Pop ---");
        // Clear RX FIFO first so error character is at head
        apb_write(5'h08, 8'h03); // FIFO_EN=1, RCVR_RESET=1
        apb_write(5'h10, 8'h10); // LOOP=1
        apb_write(5'h0C, 8'h43); // LCR[6]=1 (Break send)
        #40000; // Allow full frame for break character to be received into RX FIFO
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[3] !== 1'b1 || rd_data[4] !== 1'b1 || rd_data[7] !== 1'b1) begin
            $display("FAIL Case 13 Framing/Break/RFE error bits missing in LSR: got %h", rd_data[7:0]);
            errs = errs + 1;
        end
        apb_write(5'h0C, 8'h03); // Restore LCR break send = 0
        apb_write(5'h08, 8'h03); // Reset RX FIFO (clear remaining break chars)
        #100;
        apb_read(5'h14, rd_data); // Verify error cleared after RX FIFO reset
        if (rd_data[7] !== 1'b0) begin
            $display("FAIL Case 13 RFE not cleared after resetting RX FIFO"); errs = errs + 1;
        end

        // Test Parity Error injection via mismatched LCR parity in loopback
        apb_write(5'h08, 8'h03); // Reset RX FIFO
        apb_write(5'h0C, 8'h0B); // LCR: 8 bits, 1 stop bit, PEN=1, Odd Parity
        apb_write(5'h00, 8'h00); // 0x00 has 0 ones -> odd parity bit = 1
        #500;
        apb_write(5'h0C, 8'h1B); // Switch LCR to Even Parity before RX samples parity bit
        #20000;
        apb_read(5'h14, rd_data); // LSR
        if (rd_data[2] !== 1'b1 || rd_data[7] !== 1'b1) begin
            $display("FAIL Case 13 Parity Error / RFE missing in LSR: got %h", rd_data[7:0]);
            errs = errs + 1;
        end
        apb_read(5'h00, rd_data); // Pop character
        apb_write(5'h0C, 8'h03); // Restore 8N1

        // =====================================================================
        // Case 14: Modem Loopback and MSR Delta Bits
        // =====================================================================
        $display("--- Case 14: Modem Loopback & MSR Delta Bits ---");
        apb_write(5'h04, 8'h08); // IER: Modem status int enable (IER[3])
        apb_write(5'h10, 8'h11); // MCR: LOOP=1, DTR=1 -> DSR active
        #100;
        if (!irq) begin
            $display("FAIL Case 14 Modem interrupt did not assert on DTR/DSR delta"); errs = errs + 1;
        end
        apb_read(5'h18, rd_data); // MSR
        if (rd_data[1] !== 1'b1 || rd_data[5] !== 1'b1) begin // Delta DSR (bit 1) & DSR state (bit 5)
            $display("FAIL Case 14 MSR DSR state/delta: got %h", rd_data[7:0]); errs = errs + 1;
        end
        #100;
        if (irq) begin
            $display("FAIL Case 14 Modem interrupt did not clear after MSR read"); errs = errs + 1;
        end
        apb_write(5'h04, 8'h00);

        // =====================================================================
        // Case 16: Hardware CTS flow control
        // =====================================================================
        $display("--- Case 16: Hardware CTS Flow Control ---");
        rst_n = 1'b0; #20; rst_n = 1'b1;
        apb_write(5'h0C, 8'h03); // 8N1
        apb_write(5'h08, 8'h01); // FIFO enabled
        cts_n = 1'b1;             // inactive CTS pauses a new frame
        apb_write(5'h10, 8'h22); // RTS + auto flow-control enable
        apb_write(5'h00, 8'h5A);
        #200;
        if (uart_tx !== 1'b1) begin
            $display("FAIL Case 16 TX started while CTS inactive"); errs = errs + 1;
        end
        cts_n = 1'b0;             // release CTS; queued byte may now start
        @(posedge clk); #1;
        if (uart_tx !== 1'b0) begin
            $display("FAIL Case 16 TX did not start after CTS release"); errs = errs + 1;
        end
        apb_write(5'h10, 8'h00);

        // =====================================================================
        // Case 17: Auto-RTS RX FIFO water mark
        // =====================================================================
        $display("--- Case 17: Auto-RTS RX FIFO Watermark ---");
        rst_n = 1'b0; #20; rst_n = 1'b1;
        apb_write(5'h0C, 8'h03); // 8N1
        apb_write(5'h08, 8'h41); // FIFO enabled, RX trigger level 4
        apb_write(5'h10, 8'h32); // LOOP + RTS + auto-RTS enable
        #100;
        if (uart_rts_n !== 1'b0) begin
            $display("FAIL Case 17 RTS not asserted before RX watermark: %b", uart_rts_n);
            errs = errs + 1;
        end
        for (i = 0; i < 4; i = i + 1)
            apb_write(5'h00, 8'h80 + i);
        #30000;
        if (uart_rts_n !== 1'b1) begin
            $display("FAIL Case 17 RTS not deasserted at RX watermark: %b", uart_rts_n);
            errs = errs + 1;
        end
        for (i = 0; i < 4; i = i + 1)
            apb_read(5'h00, rd_data);
        #100;
        if (uart_rts_n !== 1'b0) begin
            $display("FAIL Case 17 RTS did not reassert after RX FIFO drain: %b", uart_rts_n);
            errs = errs + 1;
        end
        apb_write(5'h10, 8'h00);

        // Case 18: APB pready=1, pslverr=0 & Reserved Read Behavior
        // =====================================================================
        $display("--- Case 18: APB Contract & Reserved Read Behavior ---");
        // Verify reserved bits in IER read back as 0 (bits 7:4)
        apb_write(5'h04, 8'hFF);
        apb_read(5'h04, rd_data);
        if (rd_data[7:4] !== 4'h0) begin
            $display("FAIL Case 15 IER reserved bits: got %h expected upper nibble 0", rd_data[7:0]); errs = errs + 1;
        end
        apb_write(5'h04, 8'h00);

        // Verify reserved bits in IIR read back as 0 (bits 5:4)
        apb_read(5'h08, rd_data);
        if (rd_data[5:4] !== 2'b00) begin
            $display("FAIL Case 15 IIR reserved bits 5:4 non-zero: got %h", rd_data[7:0]); errs = errs + 1;
        end

        // =====================================================================
        // Final Summary
        // =====================================================================
        if (errs == 0) $display("REGRESSION_TEST_SUCCESS uart_16550");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #500000 $display("FAIL timeout"); $finish;
    end
endmodule
