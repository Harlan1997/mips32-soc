// =============================================================================
// File Name: axi_ddr_behavioral.v
// Design:    AXI4 DDR Capacity Placeholder (behavioral, Phase C.4)
// Description:
//   A plain AXI4 slave backing the new 128MB DDR physical window
//   (`SOC_DDR_BASE`, rtl/include/soc_config.vh). Provides a large-capacity
//   memory model so kseg0/1 direct-mapping has a real physical target once
//   SOC_MMU_ENABLE is later activated. This is a capacity/addressing
//   placeholder only:
//     - no DDR3 timing (tRCD/tRP/tRAS/tFAW/...), no refresh, no mode
//       registers, no PHY/DFI interface
//     - no injected backpressure/refresh-stall/mid-burst-drop stress (that
//       behavior belongs to rtl/perips/axi_ddr_model.v, which stays
//       dedicated to AXI protocol stress testing and is unrelated to this
//       module)
//   The real synthesizable DDR3 controller is specified in
//   docs/block_specs/ddr3_spec.md and is deferred to a later phase pending
//   procured PHY IP.
//
//   Backing store is sized well below the declared 128MB architectural
//   window (MEM_DEPTH_WORDS default 16MB) to keep simulation memory/runtime
//   cost reasonable. Addresses within the 128MB window wrap (mod backing
//   depth) rather than going out of bounds.
// =============================================================================

`include "soc_config.vh"

module axi_ddr_behavioral #(
    parameter MEM_DEPTH_WORDS = 4194304 // 16MB default
) (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Slave Interface
    // AW Channel
    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire        s_awvalid,
    output reg         s_awready,
    // W Channel
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output reg         s_wready,
    // B Channel
    output reg  [3:0]  s_bid,
    output reg  [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,
    // AR Channel
    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire        s_arvalid,
    output reg         s_arready,
    // R Channel
    output reg  [3:0]  s_rid,
    output reg  [31:0] s_rdata,
    output reg  [1:0]  s_rresp,
    output reg         s_rlast,
    output reg         s_rvalid,
    input  wire        s_rready
);

    // Memory array
    reg [31:0] ram [0:MEM_DEPTH_WORDS-1];

    // Word-index helper: relative to the DDR window base, wrapped to the
    // backing depth (backing store is smaller than the declared 128MB
    // architectural window).
    function [31:0] word_index;
        input [31:0] addr;
        begin
            word_index = ((addr - `SOC_DDR_BASE) >> 2) % MEM_DEPTH_WORDS;
        end
    endfunction

    // Initialize with 0
    integer i;
    reg [4095:0] image_hex;
    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1) begin
            ram[i] = 32'd0;
        end
        image_hex = "";
        if ($value$plusargs("DDR_HEX=%s", image_hex)) begin
            $display("axi_ddr_behavioral: loading image from %0s", image_hex);
            load_hex(image_hex);
        end
    end

    // synopsys translate_off
    task load_hex;
        input [4095:0] hex_path;
        begin
            $readmemh(hex_path, ram);
        end
    endtask
    // synopsys translate_on

    // =========================================================================
    // Read Logic
    // =========================================================================
    localparam R_IDLE  = 2'd0;
    localparam R_BURST = 2'd1;

    reg [1:0]  r_state;
    reg [31:0] r_addr;
    reg [7:0]  r_len;
    reg [3:0]  r_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state   <= R_IDLE;
            r_addr    <= 32'd0;
            r_len     <= 8'd0;
            r_id      <= 4'd0;
            s_arready <= 1'b0;
            s_rvalid  <= 1'b0;
            s_rlast   <= 1'b0;
            s_rdata   <= 32'd0;
            s_rid     <= 4'd0;
            s_rresp   <= 2'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_arready <= 1'b1;
                    if (s_arvalid && s_arready) begin
                        s_arready <= 1'b0;
                        r_addr    <= s_araddr;
                        r_len     <= s_arlen;
                        r_id      <= s_arid;
                        r_state   <= R_BURST;

                        s_rvalid  <= 1'b1;
                        s_rlast   <= (s_arlen == 8'd0);
                        s_rid     <= s_arid;
                        s_rresp   <= 2'b00; // OKAY
                        s_rdata   <= ram[word_index(s_araddr)];
                    end
                end
                R_BURST: begin
                    if (s_rvalid && s_rready) begin
                        if (r_len == 8'd0) begin
                            s_rvalid  <= 1'b0;
                            s_rlast   <= 1'b0;
                            r_state   <= R_IDLE;
                            s_arready <= 1'b1;
                        end else begin
                            r_addr    <= r_addr + 32'd4;
                            r_len     <= r_len - 1'b1;

                            s_rlast   <= (r_len == 8'd1);
                            s_rdata   <= ram[word_index(r_addr + 32'd4)];
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // Write Logic
    // =========================================================================
    localparam W_IDLE  = 2'd0;
    localparam W_DATA  = 2'd1;
    localparam W_RESP  = 2'd2;

    reg [1:0]  w_state;
    reg [31:0] w_addr;
    reg [7:0]  w_len;
    reg [3:0]  w_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state   <= W_IDLE;
            w_addr    <= 32'd0;
            w_len     <= 8'd0;
            w_id      <= 4'd0;
            s_awready <= 1'b0;
            s_wready  <= 1'b0;
            s_bvalid  <= 1'b0;
            s_bresp   <= 2'd0;
            s_bid     <= 4'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_awready <= 1'b1;
                    s_wready  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        s_awready <= 1'b0;
                        w_addr    <= s_awaddr;
                        w_len     <= s_awlen;
                        w_id      <= s_awid;
                        w_state   <= W_DATA;
                        s_wready  <= 1'b1;
                    end
                end

                W_DATA: begin
                    if (s_wvalid && s_wready) begin
                        if (s_wstrb[0]) ram[word_index(w_addr)][7:0]   <= s_wdata[7:0];
                        if (s_wstrb[1]) ram[word_index(w_addr)][15:8]  <= s_wdata[15:8];
                        if (s_wstrb[2]) ram[word_index(w_addr)][23:16] <= s_wdata[23:16];
                        if (s_wstrb[3]) ram[word_index(w_addr)][31:24] <= s_wdata[31:24];

                        if (s_wlast) begin
                            s_wready <= 1'b0;
                            s_bvalid <= 1'b1;
                            s_bresp  <= 2'b00; // OKAY
                            s_bid    <= w_id;
                            w_state  <= W_RESP;
                        end else begin
                            w_addr <= w_addr + 32'd4;
                            w_len  <= w_len - 1'b1;
                        end
                    end
                end

                W_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid  <= 1'b0;
                        w_state   <= W_IDLE;
                        s_awready <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
