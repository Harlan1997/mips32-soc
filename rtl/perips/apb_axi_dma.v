// =============================================================================
// File Name: apb_axi_dma.v
// Design:    APB Configured AXI4 DMA Controller
// Author:    Antigravity
// Description:
//   A basic block-transfer DMA engine.
//   Configuration via APB interface.
//   Data movement via AXI4 Master interface (single-beat word transfers).
//
// Registers (APB):
//   0x00: SRC_ADDR  (Word aligned)
//   0x04: DST_ADDR  (Word aligned)
//   0x08: LENGTH    (In bytes, multiple of 4)
//   0x0C: CTRL      [0]: START (Write 1 to start, self-clears when done)
//                   [1]: INT_EN (Interrupt Enable)
//                   [2]: DONE (Read 1 if complete, write 1 to clear)
// =============================================================================

module apb_axi_dma (
    input  wire        clk,
    input  wire        rst_n,

    // APB Slave Interface (for configuration)
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire        pready,
    output wire [31:0] prdata,
    output wire        pslverr,

    // AXI4 Master Interface (for data movement)
    output wire [3:0]  m_awid,
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire [2:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire [1:0]  m_awlock,
    output wire [3:0]  m_awcache,
    output wire [2:0]  m_awprot,
    output wire        m_awvalid,
    input  wire        m_awready,

    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,

    input  wire [3:0]  m_bid,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,

    output wire [3:0]  m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire [1:0]  m_arlock,
    output wire [3:0]  m_arcache,
    output wire [2:0]  m_arprot,
    output wire        m_arvalid,
    input  wire        m_arready,

    input  wire [3:0]  m_rid,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready,

    // Interrupt
    output wire        dma_int
);

    // =========================================================================
    // APB Register File
    // =========================================================================
    reg [31:0] reg_src_addr;
    reg [31:0] reg_dst_addr;
    reg [31:0] reg_length;
    reg        reg_int_en;
    reg        reg_done;
    
    wire apb_write = psel & penable & pwrite;
    
    // Internal Control Signals
    wire dma_start = apb_write & (paddr == 12'h00C) & pwdata[0];
    reg  dma_busy;
    wire dma_done_pulse;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_src_addr <= 32'd0;
            reg_dst_addr <= 32'd0;
            reg_length   <= 32'd0;
            reg_int_en   <= 1'b0;
            reg_done     <= 1'b0;
        end else begin
            if (apb_write) begin
                case (paddr)
                    12'h000: reg_src_addr <= pwdata;
                    12'h004: reg_dst_addr <= pwdata;
                    12'h008: reg_length   <= pwdata;
                    12'h00C: begin
                        reg_int_en <= pwdata[1];
                        if (pwdata[2]) reg_done <= 1'b0; // Clear on write 1
                    end
                endcase
            end
            
            // Set done when DMA finishes
            if (dma_busy && dma_done_pulse) begin
                reg_done <= 1'b1;
            end
        end
    end

    reg [31:0] prdata_reg;
    always @(*) begin
        case (paddr)
            12'h000: prdata_reg = reg_src_addr;
            12'h004: prdata_reg = reg_dst_addr;
            12'h008: prdata_reg = reg_length;
            12'h00C: prdata_reg = {29'd0, reg_done, reg_int_en, dma_busy};
            default: prdata_reg = 32'd0;
        endcase
    end
    
    assign prdata  = prdata_reg;
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    assign dma_int = reg_int_en & reg_done;

    // =========================================================================
    // DMA State Machine
    // =========================================================================
    localparam ST_IDLE       = 3'd0;
    localparam ST_AR         = 3'd1;
    localparam ST_R          = 3'd2;
    localparam ST_AW         = 3'd3;
    localparam ST_W          = 3'd4;
    localparam ST_B          = 3'd5;
    
    reg [2:0]  state, next_state;
    reg [31:0] cur_src;
    reg [31:0] cur_dst;
    reg [31:0] bytes_left;
    reg [31:0] data_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (dma_start) next_state = ST_AR;
            end
            ST_AR: begin
                if (m_arvalid && m_arready) next_state = ST_R;
            end
            ST_R: begin
                if (m_rvalid && m_rready) next_state = ST_AW;
            end
            ST_AW: begin
                if (m_awvalid && m_awready) next_state = ST_W;
            end
            ST_W: begin
                if (m_wvalid && m_wready) next_state = ST_B;
            end
            ST_B: begin
                if (m_bvalid && m_bready) begin
                    if (bytes_left <= 4) next_state = ST_IDLE; // Finished
                    else                 next_state = ST_AR;   // Next word
                end
            end
            default: next_state = ST_IDLE;
        endcase
    end

    assign dma_done_pulse = (state == ST_B) && (next_state == ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_src    <= 32'd0;
            cur_dst    <= 32'd0;
            bytes_left <= 32'd0;
            dma_busy   <= 1'b0;
            data_buf   <= 32'd0;
        end else begin
            if (state == ST_IDLE && dma_start) begin
                cur_src    <= reg_src_addr;
                cur_dst    <= reg_dst_addr;
                bytes_left <= reg_length;
                dma_busy   <= (reg_length > 0);
            end else if (state != ST_IDLE) begin
                if (state == ST_R && m_rvalid && m_rready) begin
                    data_buf <= m_rdata;
                end
                if (state == ST_B && m_bvalid && m_bready) begin
                    cur_src    <= cur_src + 4;
                    cur_dst    <= cur_dst + 4;
                    bytes_left <= bytes_left - 4;
                end
                if (dma_done_pulse) begin
                    dma_busy <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // AXI Master Signals
    // =========================================================================
    
    // Read Address Channel
    assign m_arid    = 4'd2; // DMA ID
    assign m_araddr  = cur_src;
    assign m_arlen   = 8'd0; // 1 beat per transaction
    assign m_arsize  = 3'b010; // 4 bytes
    assign m_arburst = 2'b01; // INCR
    assign m_arlock  = 2'd0;
    assign m_arcache = 4'd0;
    assign m_arprot  = 3'd0;
    assign m_arvalid = (state == ST_AR);

    // Read Data Channel
    assign m_rready  = (state == ST_R);

    // Write Address Channel
    assign m_awid    = 4'd2;
    assign m_awaddr  = cur_dst;
    assign m_awlen   = 8'd0;
    assign m_awsize  = 3'b010;
    assign m_awburst = 2'b01;
    assign m_awlock  = 2'd0;
    assign m_awcache = 4'd0;
    assign m_awprot  = 3'd0;
    assign m_awvalid = (state == ST_AW);

    // Write Data Channel
    assign m_wdata   = data_buf;
    assign m_wstrb   = 4'b1111; // Always write all 4 bytes
    assign m_wlast   = 1'b1;    // Since length is 0 (1 beat)
    assign m_wvalid  = (state == ST_W);

    // Write Response Channel
    assign m_bready  = (state == ST_B);

endmodule
