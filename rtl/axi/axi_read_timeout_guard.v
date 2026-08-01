// =============================================================================
// File Name: axi_read_timeout_guard.v
// Design:    Single-outstanding AXI read timeout guard
// =============================================================================
// Bounds the time spent waiting for a slave to accept a read request or to
// produce the next read beat. A timeout is returned upstream as SLVERR. This
// guard deliberately does not time out legal R-channel backpressure: once the
// slave asserts RVALID, AXI permits the master to defer RREADY indefinitely.

`include "soc_config.vh"

module axi_read_timeout_guard #(
    parameter integer TIMEOUT_CYCLES = 512
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

    output reg         timeout_sticky
);

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_AR    = 3'd1;
    localparam [2:0] ST_R     = 3'd2;
    localparam [2:0] ST_ERROR = 3'd3;
    localparam [2:0] ST_DRAIN = 3'd4;

    reg [2:0]  state;
    reg [3:0]  req_id;
    reg [31:0] req_addr;
    reg [7:0]  req_len;
    reg [2:0]  req_size;
    reg [1:0]  req_burst;
    reg [1:0]  req_lock;
    reg [3:0]  req_cache;
    reg [2:0]  req_prot;
    reg [7:0]  completed_beats;
    reg [7:0]  error_beat;
    reg [31:0] wait_count;
    reg        downstream_active;

    wire timeout_enabled = (TIMEOUT_CYCLES > 0);
    wire timeout_expired = timeout_enabled &&
                           (wait_count >= (TIMEOUT_CYCLES - 1));

    assign s_arready = (state == ST_IDLE);

    assign m_arid    = req_id;
    assign m_araddr  = req_addr;
    assign m_arlen   = req_len;
    assign m_arsize  = req_size;
    assign m_arburst = req_burst;
    assign m_arlock  = req_lock;
    assign m_arcache = req_cache;
    assign m_arprot  = req_prot;
    assign m_arvalid = (state == ST_AR);

    assign s_rid    = (state == ST_R) ? m_rid : req_id;
    assign s_rdata  = (state == ST_R) ? m_rdata : 32'd0;
    assign s_rresp  = (state == ST_R) ? m_rresp : `SOC_AXI_RESP_SLVERR;
    assign s_rlast  = (state == ST_R) ? m_rlast : (error_beat == req_len);
    assign s_rvalid = (state == ST_R) ? m_rvalid : (state == ST_ERROR);

    // A timed-out downstream transaction cannot be cancelled by AXI. Drain its
    // late response before accepting another request so IDs cannot be mixed.
    assign m_rready = (state == ST_R) ? s_rready : (state == ST_DRAIN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            req_id             <= 4'd0;
            req_addr           <= 32'd0;
            req_len            <= 8'd0;
            req_size           <= 3'd0;
            req_burst          <= 2'd0;
            req_lock           <= 2'd0;
            req_cache          <= 4'd0;
            req_prot           <= 3'd0;
            completed_beats    <= 8'd0;
            error_beat         <= 8'd0;
            wait_count         <= 32'd0;
            downstream_active  <= 1'b0;
            timeout_sticky     <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    wait_count <= 32'd0;
                    if (s_arvalid && s_arready) begin
                        req_id            <= s_arid;
                        req_addr          <= s_araddr;
                        req_len           <= s_arlen;
                        req_size          <= s_arsize;
                        req_burst         <= s_arburst;
                        req_lock          <= s_arlock;
                        req_cache         <= s_arcache;
                        req_prot          <= s_arprot;
                        completed_beats   <= 8'd0;
                        error_beat        <= 8'd0;
                        downstream_active <= 1'b0;
                        state             <= ST_AR;
                    end
                end

                ST_AR: begin
                    if (m_arvalid && m_arready) begin
                        wait_count        <= 32'd0;
                        downstream_active <= 1'b1;
                        state             <= ST_R;
                    end else if (timeout_expired) begin
                        wait_count     <= 32'd0;
                        error_beat    <= 8'd0;
                        timeout_sticky <= 1'b1;
                        state          <= ST_ERROR;
                    end else begin
                        wait_count <= wait_count + 32'd1;
                    end
                end

                ST_R: begin
                    if (m_rvalid) begin
                        wait_count <= 32'd0;
                        if (m_rready && m_rlast) begin
                            downstream_active <= 1'b0;
                            state             <= ST_IDLE;
                        end else if (m_rready) begin
                            completed_beats <= completed_beats + 8'd1;
                        end
                    end else if (timeout_expired) begin
                        wait_count      <= 32'd0;
                        error_beat      <= completed_beats;
                        timeout_sticky  <= 1'b1;
                        state           <= ST_ERROR;
                    end else begin
                        wait_count <= wait_count + 32'd1;
                    end
                end

                ST_ERROR: begin
                    if (s_rvalid && s_rready) begin
                        if (error_beat == req_len) begin
                            state <= downstream_active ? ST_DRAIN : ST_IDLE;
                        end else begin
                            error_beat <= error_beat + 8'd1;
                        end
                    end
                end

                ST_DRAIN: begin
                    if (m_rvalid && m_rready && m_rlast) begin
                        downstream_active <= 1'b0;
                        state             <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
