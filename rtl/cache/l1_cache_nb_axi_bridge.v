// L1 nonblocking line-port to AXI4 burst bridge.
//
// The line cache owns up to two MSHRs.  This bridge therefore keeps two
// independent read transactions in flight and routes R responses by AXI ID.
// Writeback remains single-entry and is drained before a refill, preserving
// the line-cache ordering contract.
module l1_cache_nb_axi_bridge #(
    parameter READ_SLOTS = 2
) (
    input wire clk, input wire rst_n,
    input wire line_req_valid, input wire line_req_we,
    input wire [31:0] line_req_addr, input wire [255:0] line_req_wdata,
    output wire line_req_ready,
    output reg line_rsp_valid, output reg [31:0] line_rsp_addr,
    output reg [255:0] line_rsp_data, output reg line_rsp_error,
    output wire [3:0] awid, output wire [31:0] awaddr,
    output wire [7:0] awlen, output wire [2:0] awsize,
    output wire [1:0] awburst, output wire [1:0] awlock,
    output wire [3:0] awcache, output wire [2:0] awprot,
    output wire awvalid, input wire awready, output wire [31:0] wdata,
    output wire [3:0] wstrb, output wire wlast, output wire wvalid,
    input wire wready, input wire [3:0] bid, input wire [1:0] bresp,
    input wire bvalid, output wire bready, output wire [3:0] arid,
    output wire [31:0] araddr, output wire [7:0] arlen,
    output wire [2:0] arsize, output wire [1:0] arburst,
    output wire [1:0] arlock, output wire [3:0] arcache,
    output wire [2:0] arprot, output wire arvalid, input wire arready,
    input wire [3:0] rid, input wire [31:0] rdata, input wire [1:0] rresp,
    input wire rlast, input wire rvalid, output wire rready
);
    localparam ST_IDLE = 3'd0, ST_AW = 3'd1, ST_W = 3'd2, ST_B = 3'd3;
    reg [2:0] wr_state;
    reg wr_active;
    reg [31:0] wr_addr_q;
    reg [255:0] wr_data_q;
    reg [2:0] wr_beat_q;
    // Compatibility observation aliases used by the SoC timeout diagnostics.
    wire [2:0] state = wr_state;
    wire [31:0] addr_q = wr_addr_q;

    reg rd_active [0:READ_SLOTS-1];
    reg rd_issued [0:READ_SLOTS-1];
    reg [31:0] rd_addr_q [0:READ_SLOTS-1];
    reg [255:0] rd_data_q [0:READ_SLOTS-1];
    reg [2:0] rd_beat_q [0:READ_SLOTS-1];
    reg rd_error_q [0:READ_SLOTS-1];
    integer i;
    integer ar_sel;
    integer r_sel;
    integer free_rd;

    always @(*) begin
        free_rd = -1;
        for (i = 0; i < READ_SLOTS; i = i + 1)
            if (!rd_active[i] && free_rd < 0) free_rd = i;
    end

    assign line_req_ready = line_req_we ?
        (!wr_active && (free_rd == 0 || free_rd == 1) &&
         !rd_active[0] && !rd_active[1]) :
        (!wr_active && (free_rd >= 0));

    always @(*) begin
        ar_sel = -1;
        for (i = 0; i < READ_SLOTS; i = i + 1)
            if (rd_active[i] && !rd_issued[i] && ar_sel < 0) ar_sel = i;
        r_sel = -1;
        for (i = 0; i < READ_SLOTS; i = i + 1)
            if (rd_active[i] && rd_issued[i] && (rid == i[3:0]) && r_sel < 0)
                r_sel = i;
    end

    assign arid = (ar_sel < 0) ? 4'd0 : ar_sel[3:0];
    assign araddr = (ar_sel < 0) ? 32'd0 : rd_addr_q[ar_sel];
    assign arlen = 8'd7;
    assign arsize = 3'b010;
    assign arburst = 2'b01;
    assign arlock = 2'b00;
    assign arcache = 4'b0011;
    assign arprot = 3'b000;
    assign arvalid = (ar_sel >= 0);
    assign rready = (r_sel >= 0);

    assign awid = 4'd0;
    assign awaddr = wr_addr_q;
    assign awlen = 8'd7;
    assign awsize = 3'b010;
    assign awburst = 2'b01;
    assign awlock = 2'b00;
    assign awcache = 4'b0011;
    assign awprot = 3'b000;
    assign awvalid = (wr_state == ST_AW);
    assign wdata = wr_data_q[wr_beat_q*32 +: 32];
    assign wstrb = 4'hf;
    assign wlast = (wr_beat_q == 3'd7);
    assign wvalid = (wr_state == ST_W);
    assign bready = (wr_state == ST_B);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= ST_IDLE; wr_active <= 1'b0; wr_addr_q <= 0;
            wr_data_q <= 0; wr_beat_q <= 0;
            line_rsp_valid <= 1'b0; line_rsp_addr <= 0;
            line_rsp_data <= 0; line_rsp_error <= 1'b0;
            for (i = 0; i < READ_SLOTS; i = i + 1) begin
                rd_active[i] <= 1'b0; rd_issued[i] <= 1'b0;
                rd_addr_q[i] <= 0; rd_data_q[i] <= 0;
                rd_beat_q[i] <= 0; rd_error_q[i] <= 1'b0;
            end
        end else begin
            line_rsp_valid <= 1'b0;

            if (line_req_valid && line_req_ready) begin
                if (line_req_we) begin
                    wr_active <= 1'b1; wr_state <= ST_AW;
                    wr_addr_q <= {line_req_addr[31:5], 5'b0};
                    wr_data_q <= line_req_wdata; wr_beat_q <= 0;
                end else begin
                    rd_active[free_rd] <= 1'b1;
                    rd_issued[free_rd] <= 1'b0;
                    rd_addr_q[free_rd] <= {line_req_addr[31:5], 5'b0};
                    rd_data_q[free_rd] <= 0; rd_beat_q[free_rd] <= 0;
                    rd_error_q[free_rd] <= 1'b0;
                end
            end

            if (arvalid && arready)
                rd_issued[ar_sel] <= 1'b1;

            if (rvalid && rready) begin
                rd_data_q[r_sel][rd_beat_q[r_sel]*32 +: 32] <= rdata;
                rd_error_q[r_sel] <= rd_error_q[r_sel] || (rresp != 2'b00);
                if (rlast || rd_beat_q[r_sel] == 3'd7) begin
                    line_rsp_valid <= 1'b1;
                    line_rsp_addr <= rd_addr_q[r_sel];
                    line_rsp_data <= rd_data_q[r_sel];
                    line_rsp_data[rd_beat_q[r_sel]*32 +: 32] <= rdata;
                    line_rsp_error <= rd_error_q[r_sel] || (rresp != 2'b00);
                    rd_active[r_sel] <= 1'b0;
                    rd_issued[r_sel] <= 1'b0;
                end else begin
                    rd_beat_q[r_sel] <= rd_beat_q[r_sel] + 1'b1;
                end
            end

            case (wr_state)
                ST_AW: if (awvalid && awready) begin wr_state <= ST_W; wr_beat_q <= 0; end
                ST_W: if (wvalid && wready) begin
                    if (wr_beat_q == 3'd7) wr_state <= ST_B;
                    else wr_beat_q <= wr_beat_q + 1'b1;
                end
                ST_B: if (bvalid && bready) begin wr_state <= ST_IDLE; wr_active <= 1'b0; end
                default: ;
            endcase
        end
    end
endmodule
