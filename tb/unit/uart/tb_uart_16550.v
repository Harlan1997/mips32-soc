// Unit test: apb_uart_16550 — loopback echo test
// Drives TX via APB write, expects same byte to appear in RX FIFO via loopback.
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
    wire         irq;

    integer errs = 0;

    always #5 clk = ~clk;

    apb_uart_16550 #(.TX_FIFO_DEPTH(16), .RX_FIFO_DEPTH(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pstrb(pstrb), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .uart_tx(uart_tx), .uart_rx(1'b1),
        .uart_rts_n(), .uart_cts_n(1'b0),
        .uart_dtr_n(), .uart_dsr_n(1'b0),
        .uart_dcd_n(1'b0), .uart_ri_n(1'b1),
        .irq(irq));

    task apb_write(input [4:0] a, input [7:0] d);
    begin
        @(negedge clk);
        psel = 1; pwrite = 1; paddr = a; pwdata = {24'h0, d};
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        psel = 0; pwrite = 0; penable = 0;
    end
    endtask

    task apb_read(input [4:0] a, output [31:0] d);
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

    reg [31:0] rd_data;
    integer i;
    reg [7:0] test_data [0:3];

    initial begin
        test_data[0] = 8'h55;
        test_data[1] = 8'hAA;
        test_data[2] = 8'h5A;
        test_data[3] = 8'hA5;

        #12 rst_n = 1;
        @(negedge clk);

        // Program divisor = 4 (tiny for fast sim) via DLAB
        apb_write(5'h0C, 8'h83);          // LCR = DLAB=1, 8N1
        apb_write(5'h00, 8'd4);           // DLL = 4
        apb_write(5'h04, 8'd0);           // DLM = 0
        apb_write(5'h0C, 8'h03);          // LCR = DLAB=0, 8N1

        // Enable loopback
        apb_write(5'h10, 8'h10);          // MCR.LOOP = 1

        // Enable FIFO
        apb_write(5'h08, 8'h01);          // FCR.FIFO_EN

        // Write 4 test bytes to TX
        for (i = 0; i < 4; i = i + 1) begin
            apb_write(5'h00, test_data[i]);
        end

        // Wait for all 4 bytes to loopback into RX
        // At divisor=4, 16× oversample, ~10 bits per char = 640 clks per byte
        // 4 bytes = ~2560 clks
        #35000;

        // Read RX FIFO
        for (i = 0; i < 4; i = i + 1) begin
            apb_read(5'h00, rd_data);
            if (rd_data[7:0] !== test_data[i]) begin
                $display("FAIL byte %0d: got %h expected %h",
                         i, rd_data[7:0], test_data[i]);
                errs = errs + 1;
            end
        end

        if (errs == 0) $display("REGRESSION_TEST_SUCCESS uart_16550");
        else           $display("REGRESSION_TEST_FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #500000 $display("FAIL timeout"); $finish;
    end
endmodule
