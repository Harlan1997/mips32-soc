// UART external RX waveform gate.
// Drives an asynchronous 8N1 pin-level stream into the 16550 RX synchronizer
// and checks data, line status, interrupt split, and framing-error visibility.

module tb_uart_external_rx;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         psel = 1'b0;
    reg         penable = 1'b0;
    reg         pwrite = 1'b0;
    reg  [4:0]  paddr = 5'h0;
    reg  [3:0]  pstrb = 4'hf;
    reg  [31:0] pwdata = 32'h0;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        uart_tx;
    reg         uart_rx = 1'b1;
    wire        uart_rts_n;
    wire        uart_dtr_n;
    wire        irq;
    wire        rx_irq;
    wire        tx_irq;
    integer     errs = 0;
    reg [31:0]  rd_data;

    always #5 clk = ~clk;

    apb_uart_16550 #(.TX_FIFO_DEPTH(16), .RX_FIFO_DEPTH(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .uart_rts_n(uart_rts_n), .uart_cts_n(1'b0),
        .uart_dtr_n(uart_dtr_n), .uart_dsr_n(1'b0),
        .uart_dcd_n(1'b0), .uart_ri_n(1'b1),
        .irq(irq), .rx_irq(rx_irq), .tx_irq(tx_irq));

    task automatic apb_write(input [4:0] a, input [7:0] d);
    begin
        @(negedge clk);
        psel = 1'b1; pwrite = 1'b1; paddr = a; pwdata = {24'h0, d}; pstrb = 4'h1;
        @(negedge clk);
        penable = 1'b1;
        @(negedge clk);
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0; paddr = 5'h0;
    end
    endtask

    task automatic apb_read(input [4:0] a, output [31:0] d);
    begin
        @(negedge clk);
        psel = 1'b1; pwrite = 1'b0; paddr = a; pstrb = 4'hf;
        @(negedge clk);
        penable = 1'b1;
        #1 d = prdata;
        if (pready !== 1'b1 || pslverr !== 1'b0) begin
            $display("FAIL APB read handshake addr=%h pready=%b pslverr=%b", a, pready, pslverr);
            errs = errs + 1;
        end
        @(negedge clk);
        psel = 1'b0; penable = 1'b0;
    end
    endtask

    // The DUT divisor is one in this gate: one UART bit is 16 SoC clocks.
    task automatic uart_bit(input bit value);
    begin
        uart_rx = value;
        repeat (16) @(posedge clk);
    end
    endtask

    task automatic uart_frame(input [7:0] value, input bit valid_stop);
        integer b;
    begin
        uart_bit(1'b0);              // start
        for (b = 0; b < 8; b = b + 1)
            uart_bit(value[b]);
        uart_bit(valid_stop);        // stop, deliberately low for error case
        uart_bit(1'b1);              // idle guard
    end
    endtask

    initial begin
        #12 rst_n = 1'b1;
        @(negedge clk);

        // Explicitly select 8N1, FIFO trigger 1, and RX line/data interrupts.
        apb_write(5'h0c, 8'h03);
        apb_write(5'h08, 8'h01);
        apb_write(5'h04, 8'h05);

        $display("--- External RX valid 8N1 frame ---");
        uart_frame(8'hA5, 1'b1);
        #20;
        if (!rx_irq || !irq || tx_irq) begin
            $display("FAIL valid frame IRQ split rx=%b tx=%b irq=%b", rx_irq, tx_irq, irq);
            errs = errs + 1;
        end
        apb_read(5'h14, rd_data);
        if (rd_data[0] !== 1'b1 || rd_data[3] !== 1'b0 || rd_data[7] !== 1'b0) begin
            $display("FAIL valid frame LSR=%h expected DR=1 FE/RFE=0", rd_data[7:0]);
            errs = errs + 1;
        end
        apb_read(5'h00, rd_data);
        if (rd_data[7:0] !== 8'hA5) begin
            $display("FAIL valid frame data=%h expected A5", rd_data[7:0]);
            errs = errs + 1;
        end
        #20;
        if (rx_irq || tx_irq || irq) begin
            $display("FAIL RX interrupt did not clear after RBR pop rx=%b tx=%b irq=%b", rx_irq, tx_irq, irq);
            errs = errs + 1;
        end

        $display("--- External RX framing-error frame ---");
        uart_frame(8'h3C, 1'b0);
        #20;
        apb_read(5'h14, rd_data);
        if (rd_data[0] !== 1'b1 || rd_data[3] !== 1'b1 || rd_data[7] !== 1'b1) begin
            $display("FAIL framing error LSR=%h expected DR=1 FE=1 RFE=1", rd_data[7:0]);
            errs = errs + 1;
        end
        if (!rx_irq || tx_irq) begin
            $display("FAIL framing error IRQ split rx=%b tx=%b", rx_irq, tx_irq);
            errs = errs + 1;
        end
        apb_read(5'h00, rd_data);
        if (rd_data[7:0] !== 8'h3C) begin
            $display("FAIL framing error data=%h expected 3C", rd_data[7:0]);
            errs = errs + 1;
        end
        #20;
        if (rx_irq || tx_irq || irq) begin
            $display("FAIL framing-error IRQ did not clear after RBR pop");
            errs = errs + 1;
        end

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS uart_external_rx");
        else            $display("REGRESSION_TEST_FAIL uart_external_rx errs=%0d", errs);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL timeout uart_external_rx");
        $finish;
    end
endmodule
