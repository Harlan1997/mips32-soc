// =============================================================================
// File Name: axi_flash_image_model.v
// Design:    Verification-oriented loadable AXI flash image model
// =============================================================================

module axi_flash_image_model #(
    parameter MEM_BYTES = 1048576
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire [1:0]  s_arlock,
    input  wire [3:0]  s_arcache,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,

    output wire [3:0]  s_rid,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    output wire        s_rvalid,
    input  wire        s_rready,

    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire [1:0]  s_awlock,
    input  wire [3:0]  s_awcache,
    input  wire [2:0]  s_awprot,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [3:0]  s_bid,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    reg [7:0] mem [0:MEM_BYTES-1];
    string image_path;
    integer i;

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            mem[i] = 8'h00;
        end

        if ($value$plusargs("FLASH_IMAGE=%s", image_path)) begin
            $readmemh(image_path, mem);
            $display("[%t] AXI FLASH IMAGE MODEL: loaded %s", $time, image_path);
        end
    end

    reg        rd_busy;
    reg [3:0]  rd_id;
    reg [31:0] rd_addr;
    reg [7:0]  rd_len;
    reg [2:0]  rd_size;
    reg [1:0]  rd_burst;
    reg [7:0]  rd_beat;

    reg        wr_busy;
    reg        wr_bvalid;
    reg [3:0]  wr_id;

    function [31:0] read_word(input [31:0] addr);
        integer base;
        begin
            base = addr[23:0] % MEM_BYTES;
            read_word = {
                mem[(base + 3) % MEM_BYTES],
                mem[(base + 2) % MEM_BYTES],
                mem[(base + 1) % MEM_BYTES],
                mem[base]
            };
        end
    endfunction

    assign s_arready = !rd_busy;
    assign s_rvalid  = rd_busy;
    assign s_rid     = rd_id;
    assign s_rdata   = read_word(rd_addr);
    assign s_rresp   = 2'b00;
    assign s_rlast   = (rd_beat == rd_len);

    assign s_awready = !wr_busy && !wr_bvalid;
    assign s_wready  = wr_busy && !wr_bvalid;
    assign s_bid     = wr_id;
    assign s_bresp   = 2'b10;
    assign s_bvalid  = wr_bvalid;

    assign spi_sclk = 1'b0;
    assign spi_cs_n = 1'b1;
    assign spi_mosi = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy  <= 1'b0;
            rd_id    <= 4'd0;
            rd_addr  <= 32'd0;
            rd_len   <= 8'd0;
            rd_size  <= 3'd2;
            rd_burst <= 2'b01;
            rd_beat  <= 8'd0;
        end else begin
            if (!rd_busy && s_arvalid && s_arready) begin
                rd_busy  <= 1'b1;
                rd_id    <= s_arid;
                rd_addr  <= s_araddr;
                rd_len   <= s_arlen;
                rd_size  <= s_arsize;
                rd_burst <= s_arburst;
                rd_beat  <= 8'd0;
            end else if (rd_busy && s_rready) begin
                if (rd_beat == rd_len) begin
                    rd_busy <= 1'b0;
                end else begin
                    rd_beat <= rd_beat + 8'd1;
                    if (rd_burst == 2'b01) begin
                        rd_addr <= rd_addr + (32'd1 << rd_size);
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_busy   <= 1'b0;
            wr_bvalid <= 1'b0;
            wr_id     <= 4'd0;
        end else begin
            if (s_awvalid && s_awready) begin
                wr_busy <= 1'b1;
                wr_id   <= s_awid;
            end

            if (s_wvalid && s_wready && s_wlast) begin
                wr_busy   <= 1'b0;
                wr_bvalid <= 1'b1;
            end

            if (wr_bvalid && s_bready) begin
                wr_bvalid <= 1'b0;
            end
        end
    end

endmodule
