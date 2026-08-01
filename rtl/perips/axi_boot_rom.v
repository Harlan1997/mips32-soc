// =============================================================================
// File Name: axi_boot_rom.v
// Design:    Read-only AXI Boot ROM slave
// =============================================================================
// The product reset path fetches this ROM through the 0x1FC0_0000 physical
// aperture (0xBFC0_0000 through kseg1). ROM contents are supplied by the ASIC
// mask-ROM flow; ROM_INIT_FILE/BOOT_ROM_HEX are simulation hooks only.

`include "soc_config.vh"

module axi_boot_rom #(
    parameter integer ROM_BYTES = `SOC_BOOT_ROM_SIZE,
    parameter         ROM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst_n,

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
    input  wire        s_rready
);

    localparam integer ROM_WORDS = ROM_BYTES / 4;
    localparam [1:0] AXI_OKAY   = `SOC_AXI_RESP_OKAY;
    localparam [1:0] AXI_SLVERR = `SOC_AXI_RESP_SLVERR;
    localparam [1:0] AXI_DECERR = `SOC_AXI_RESP_DECERR;

    reg [31:0] rom [0:ROM_WORDS-1];
    integer i;
    // Long aggregate build paths are valid simulation inputs; do not truncate
    // the Boot ROM image plusarg at the legacy 128-character buffer limit.
    reg [4095:0] image_hex;

    initial begin
        for (i = 0; i < ROM_WORDS; i = i + 1) begin
            rom[i] = 32'd0;
        end
        image_hex = "";
        if (ROM_INIT_FILE != "") begin
            $readmemh(ROM_INIT_FILE, rom);
        end else if ($value$plusargs("BOOT_ROM_HEX=%s", image_hex)) begin
            $display("axi_boot_rom: loading image from %0s", image_hex);
            $readmemh(image_hex, rom);
        end
    end

    function addr_in_range;
        input [31:0] addr;
        begin
            addr_in_range = (addr >= `SOC_BOOT_ROM_BASE) &&
                            (addr <= (`SOC_BOOT_ROM_BASE + ROM_BYTES - 4));
        end
    endfunction

    function [31:0] rom_read_word;
        input [31:0] addr;
        integer word_index;
        begin
            if (addr_in_range(addr)) begin
                word_index = (addr - `SOC_BOOT_ROM_BASE) >> 2;
                rom_read_word = rom[word_index];
            end else begin
                rom_read_word = 32'd0;
            end
        end
    endfunction

    reg        rd_busy;
    reg [3:0]  rd_id;
    reg [31:0] rd_addr;
    reg [7:0]  rd_len;
    reg [7:0]  rd_beat;
    reg [2:0]  rd_size;
    reg [1:0]  rd_burst;

    wire rd_error = !addr_in_range(rd_addr) || (rd_size > 3'd2);

    assign s_arready = !rd_busy;
    assign s_rid     = rd_id;
    assign s_rdata   = rom_read_word(rd_addr);
    assign s_rresp   = rd_error ? AXI_DECERR : AXI_OKAY;
    assign s_rlast   = rd_busy && (rd_beat == rd_len);
    assign s_rvalid  = rd_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy  <= 1'b0;
            rd_id    <= 4'd0;
            rd_addr  <= 32'd0;
            rd_len   <= 8'd0;
            rd_beat  <= 8'd0;
            rd_size  <= 3'd0;
            rd_burst <= 2'b01;
        end else if (!rd_busy) begin
            if (s_arvalid && s_arready) begin
                rd_busy  <= 1'b1;
                rd_id    <= s_arid;
                rd_addr  <= s_araddr;
                rd_len   <= s_arlen;
                rd_beat  <= 8'd0;
                rd_size  <= s_arsize;
                rd_burst <= s_arburst;
            end
        end else if (s_rvalid && s_rready) begin
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

    reg       wr_busy;
    reg       wr_resp_valid;
    reg [3:0] wr_id;
    reg [7:0] wr_len;
    reg [7:0] wr_beat;

    assign s_awready = !wr_busy && !wr_resp_valid;
    assign s_wready  = wr_busy && !wr_resp_valid;
    assign s_bid     = wr_id;
    assign s_bresp   = AXI_SLVERR;
    assign s_bvalid  = wr_resp_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_busy       <= 1'b0;
            wr_resp_valid <= 1'b0;
            wr_id         <= 4'd0;
            wr_len        <= 8'd0;
            wr_beat       <= 8'd0;
        end else begin
            if (!wr_busy && !wr_resp_valid && s_awvalid && s_awready) begin
                wr_busy <= 1'b1;
                wr_id   <= s_awid;
                wr_len  <= s_awlen;
                wr_beat <= 8'd0;
            end

            if (wr_busy && s_wvalid && s_wready) begin
                if (s_wlast || (wr_beat == wr_len)) begin
                    wr_busy       <= 1'b0;
                    wr_resp_valid <= 1'b1;
                end else begin
                    wr_beat <= wr_beat + 8'd1;
                end
            end

            if (wr_resp_valid && s_bready) begin
                wr_resp_valid <= 1'b0;
            end
        end
    end

endmodule
