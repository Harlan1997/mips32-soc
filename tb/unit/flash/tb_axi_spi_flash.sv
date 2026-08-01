`timescale 1ns/1ps

// Pin-level contract for the product SPI XIP controller. The flash responder
// presents two little-endian words as a continuous serial-read stream after
// receiving the controller's standard-read command and 24-bit address.
module tb_axi_spi_flash;
    localparam [31:0] WORD0 = 32'hA1B2_C3D4;
    localparam [31:0] WORD1 = 32'h1122_3344;
    localparam [63:0] SERIAL_STREAM = {32'hD4C3_B2A1, 32'h4433_2211};

    reg clk;
    reg rst_n;
    reg [3:0] arid;
    reg [31:0] araddr;
    reg [7:0] arlen;
    reg [2:0] arsize;
    reg [1:0] arburst;
    reg [1:0] arlock;
    reg [3:0] arcache;
    reg [2:0] arprot;
    reg arvalid;
    wire arready;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    reg rready;

    reg [3:0] awid;
    reg [31:0] awaddr;
    reg [7:0] awlen;
    reg [2:0] awsize;
    reg [1:0] awburst;
    reg [1:0] awlock;
    reg [3:0] awcache;
    reg [2:0] awprot;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wlast;
    reg wvalid;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire spi_miso;

    integer cycles;
    integer response_count;
    integer spi_bit_count;
    reg [31:0] spi_capture;
    reg command_address_seen;
    reg write_started;
    reg write_response_seen;

    // The DUT samples MISO when READ is active with spi_clk_en low. Its
    // bit_cnt and burst_beat identify the next bit in the serial flash stream.
    wire [7:0] stream_bit = ({3'd0, dut.burst_beat} << 5) + dut.bit_cnt;
    assign spi_miso = (dut.state == 4'd3) ? SERIAL_STREAM[63 - stream_bit] : 1'b0;

    axi_spi_flash dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .s_arid    (arid),
        .s_araddr  (araddr),
        .s_arlen   (arlen),
        .s_arsize  (arsize),
        .s_arburst (arburst),
        .s_arlock  (arlock),
        .s_arcache (arcache),
        .s_arprot  (arprot),
        .s_arvalid (arvalid),
        .s_arready (arready),
        .s_rid     (rid),
        .s_rdata   (rdata),
        .s_rresp   (rresp),
        .s_rlast   (rlast),
        .s_rvalid  (rvalid),
        .s_rready  (rready),
        .s_awid    (awid),
        .s_awaddr  (awaddr),
        .s_awlen   (awlen),
        .s_awsize  (awsize),
        .s_awburst (awburst),
        .s_awlock  (awlock),
        .s_awcache (awcache),
        .s_awprot  (awprot),
        .s_awvalid (awvalid),
        .s_awready (awready),
        .s_wdata   (wdata),
        .s_wstrb   (wstrb),
        .s_wlast   (wlast),
        .s_wvalid  (wvalid),
        .s_wready  (wready),
        .s_bid     (bid),
        .s_bresp   (bresp),
        .s_bvalid  (bvalid),
        .s_bready  (bready),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)
    );

    always #5 clk = ~clk;

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED axi_spi_flash");
            $finish;
        end
    endtask

    always @(negedge spi_cs_n) begin
        spi_bit_count = 0;
        spi_capture = 32'd0;
    end

    always @(posedge spi_sclk) begin
        if (!spi_cs_n && spi_bit_count < 32) begin
            spi_capture = {spi_capture[30:0], spi_mosi};
            if (spi_bit_count == 31) begin
                if (spi_capture !== 32'h0300_0000) begin
                    $display("DEBUG: captured SPI command/address=%h", spi_capture);
                    fail("SPI command/address was not 03_000000");
                end
                command_address_seen = 1'b1;
            end
            spi_bit_count = spi_bit_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            response_count = 0;
            command_address_seen = 1'b0;
            write_started = 1'b0;
            write_response_seen = 1'b0;
            awvalid = 1'b0;
            wvalid = 1'b0;
        end else begin
            cycles = cycles + 1;
            if (rvalid && rready) begin
                if (rid !== 4'hA)
                    fail("read response ID changed");
                if (rresp !== 2'b00)
                    fail("read response was not OKAY");
                if (response_count == 0) begin
                    if (rdata !== WORD0)
                        fail("first SPI XIP word mismatch");
                    if (rlast)
                        fail("first burst beat asserted RLAST");
                end else if (response_count == 1) begin
                    if (rdata !== WORD1)
                        fail("second SPI XIP word mismatch");
                    if (!rlast)
                        fail("final burst beat omitted RLAST");
                end else begin
                    fail("controller returned extra burst data");
                end
                response_count = response_count + 1;
            end

            if (response_count == 2 && !write_started) begin
                awvalid <= 1'b1;
                write_started <= 1'b1;
            end

            if (awvalid && awready) begin
                awvalid <= 1'b0;
                wvalid <= 1'b1;
            end

            if (wvalid && wready)
                wvalid <= 1'b0;

            if (bvalid && bready) begin
                if (bid !== 4'h5)
                    fail("write response ID changed");
                if (bresp !== 2'b10)
                    fail("flash write did not return SLVERR");
                write_response_seen <= 1'b1;
            end

            if (response_count == 2 && command_address_seen && write_response_seen) begin
                $display("REGRESSION_TEST_SUCCESS axi_spi_flash");
                $finish;
            end

            if (cycles > 500) begin
                $display("DEBUG: responses=%0d command=%b write_started=%b write_done=%b aw=%b/%b w=%b/%b b=%b/%b state=%0d",
                         response_count, command_address_seen, write_started, write_response_seen,
                         awvalid, awready, wvalid, wready, bvalid, bready, dut.state);
                fail("SPI XIP read did not complete");
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        arid = 4'hA;
        araddr = 32'h1000_0000;
        arlen = 8'd1;
        arsize = 3'd2;
        arburst = 2'b01;
        arlock = 2'b00;
        arcache = 4'd0;
        arprot = 3'd0;
        arvalid = 1'b0;
        rready = 1'b1;
        awid = 4'h5;
        awaddr = 32'h1000_0000;
        awlen = 8'd0;
        awsize = 3'd2;
        awburst = 2'b01;
        awlock = 2'b00;
        awcache = 4'd0;
        awprot = 3'd0;
        awvalid = 1'b0;
        wdata = 32'hDEAD_BEEF;
        wstrb = 4'hF;
        wlast = 1'b1;
        wvalid = 1'b0;
        bready = 1'b1;
        cycles = 0;
        response_count = 0;
        spi_bit_count = 0;
        spi_capture = 32'd0;
        command_address_seen = 1'b0;
        write_started = 1'b0;
        write_response_seen = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        arvalid = 1'b1;
        do @(posedge clk); while (!arready);
        @(negedge clk);
        arvalid = 1'b0;
    end
endmodule
