// =============================================================================
// File Name: axi_spi_flash.v
// Design:    AXI4 SPI Flash Controller (XIP - Execute In Place)
// Author:    Antigravity
// Description:
//   A simple read-only SPI Flash controller that translates AXI read requests
//   into SPI Standard Read (0x03) transactions.
//   Supports 24-bit addressing.
// =============================================================================

module axi_spi_flash (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Slave Interface
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
    
    // Write channels ignored (Read Only)
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

    // SPI Interface
    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    reg        wr_busy;
    reg        wr_bvalid;
    reg [3:0]  wr_id;

    assign s_awready = !wr_busy && !wr_bvalid;
    assign s_wready  = wr_busy && !wr_bvalid;
    assign s_bid     = wr_id;
    assign s_bresp   = 2'b10; // SLVERR: flash is read-only in this model
    assign s_bvalid  = wr_bvalid;

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

    // State Machine
    localparam IDLE    = 4'd0;
    localparam CMD     = 4'd1;
    localparam ADDR    = 4'd2;
    localparam READ    = 4'd3;
    localparam RESP    = 4'd4;
    
    reg [3:0]  state, next_state;
    reg [3:0]  ar_id;
    reg [23:0] flash_addr;
    reg [31:0] read_data;
    reg [7:0]  bit_cnt;
    reg [7:0]  burst_len;
    reg [7:0]  burst_beat;
    
    // Simple SCLK generation (clk / 2)
    reg spi_clk_en;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) spi_clk_en <= 1'b0;
        else        spi_clk_en <= ~spi_clk_en;
    end
    
    assign spi_sclk = (state != IDLE && state != RESP) ? ~spi_clk_en : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            state <= IDLE;
            // VCS coverage on
        end
        else if (spi_clk_en || state == IDLE || state == RESP) state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (s_arvalid) next_state = CMD;
            CMD:  if (bit_cnt == 7) next_state = ADDR;
            ADDR: if (bit_cnt == 23) next_state = READ;
            READ: if (bit_cnt == 31) next_state = RESP;
            RESP: begin
                if (s_rvalid && s_rready) begin
                    next_state = (burst_beat == burst_len) ? IDLE : READ;
                end
            end
            // VCS coverage off
            default: next_state = IDLE;
            // VCS coverage on
        endcase
    end

    reg [7:0] cmd_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_id      <= 4'd0;
            flash_addr <= 24'd0;
            bit_cnt    <= 8'd0;
            read_data  <= 32'd0;
            cmd_reg    <= 8'h03; // Read command
            burst_len  <= 8'd0;
            burst_beat <= 8'd0;
        end else begin
            if (state == IDLE && s_arvalid) begin
                ar_id      <= s_arid;
                flash_addr <= s_araddr[23:0];
                bit_cnt    <= 8'd0;
                read_data  <= 32'd0;
                cmd_reg    <= 8'h03;
                burst_len  <= s_arlen;
                burst_beat <= 8'd0;
            end else if (spi_clk_en) begin
                if (state == CMD) begin
                    bit_cnt <= (bit_cnt == 8'd7) ? 8'd0 : (bit_cnt + 8'd1);
                    cmd_reg <= {cmd_reg[6:0], 1'b0};
                end else if (state == ADDR) begin
                    bit_cnt <= (bit_cnt == 8'd23) ? 8'd0 : (bit_cnt + 8'd1);
                    flash_addr <= {flash_addr[22:0], 1'b0};
                end else if (state == READ) begin
                    bit_cnt <= (bit_cnt == 8'd31) ? 8'd0 : (bit_cnt + 8'd1);
                end
            end

            if (state == RESP && s_rvalid && s_rready && (burst_beat != burst_len)) begin
                burst_beat <= burst_beat + 8'd1;
                bit_cnt    <= 8'd0;
                read_data  <= 32'd0;
            end
            
            // Sample on rising edge (which corresponds to !spi_clk_en because sclk is ~spi_clk_en)
            if (!spi_clk_en && state == READ) begin
                read_data <= {read_data[30:0], spi_miso};
            end
        end
    end

    assign spi_cs_n = (state == IDLE);
    assign spi_mosi = (state == CMD)  ? cmd_reg[7] :
                      (state == ADDR) ? flash_addr[23] : 1'b0;

    assign s_arready = (state == IDLE);
    
    // Change byte order if CPU expects Little Endian (MIPS can be both, we assume LE here)
    wire [31:0] endian_swapped = {read_data[7:0], read_data[15:8], read_data[23:16], read_data[31:24]};

    assign s_rvalid = (state == RESP);
    assign s_rid    = ar_id;
    assign s_rdata  = endian_swapped;
    assign s_rresp  = 2'b00;
    assign s_rlast  = (burst_beat == burst_len);

endmodule
