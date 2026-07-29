// =============================================================================
// axi_mem_slave.v — simple single-outstanding in-order AXI4 memory slave (TB).
// Word-addressed, INCR bursts, configurable read latency (RD_DELAY cycles).
// Used only by tb/unit/fabric tests to back the crossbar's mapped slave ports.
// =============================================================================
`timescale 1ns/1ps

module axi_mem_slave #(
    parameter IDW = 4, parameter AW = 32, parameter DW = 32,
    parameter RD_DELAY = 1, parameter DEPTH = 4096
) (
    input  wire clk, input wire rst_n,
    input  wire [IDW-1:0] awid, input wire [AW-1:0] awaddr, input wire [7:0] awlen,
    input  wire awvalid, output reg awready,
    input  wire [DW-1:0] wdata, input wire [3:0] wstrb, input wire wlast,
    input  wire wvalid, output reg wready,
    output reg  [IDW-1:0] bid, output reg [1:0] bresp, output reg bvalid, input wire bready,
    input  wire [IDW-1:0] arid, input wire [AW-1:0] araddr, input wire [7:0] arlen,
    input  wire arvalid, output reg arready,
    output reg  [IDW-1:0] rid, output reg [DW-1:0] rdata, output reg [1:0] rresp,
    output reg  rlast, output reg rvalid, input wire rready
);
    reg [DW-1:0] mem [0:DEPTH-1];

    // Write FSM
    localparam W_IDLE=0, W_DATA=2, W_RESP=3;
    reg [1:0] wst; reg [AW-1:0] waddr; reg [IDW-1:0] wid_l;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wst<=W_IDLE; awready<=1; wready<=0; bvalid<=0; bresp<=2'b00; bid<=0; waddr<=0; wid_l<=0;
        end else begin
            case (wst)
                W_IDLE: begin
                    awready<=1;
                    if (awvalid && awready) begin
                        waddr<=awaddr; wid_l<=awid; awready<=0; wready<=1; wst<=W_DATA;
                    end
                end
                W_DATA: begin
                    if (wvalid && wready) begin
                        mem[(waddr>>2) % DEPTH] <= wdata;
                        waddr <= waddr + 4;
                        if (wlast) begin wready<=0; bvalid<=1; bid<=wid_l; bresp<=2'b00; wst<=W_RESP; end
                    end
                end
                W_RESP: begin
                    if (bvalid && bready) begin bvalid<=0; awready<=1; wst<=W_IDLE; end
                end
            endcase
        end
    end

    // Read FSM (in-order, RD_DELAY latency before first beat)
    localparam R_IDLE=0, R_WAIT=1, R_DATA=2;
    reg [1:0] rst_s; reg [AW-1:0] raddr; reg [7:0] rbeat, rlen; reg [IDW-1:0] rid_l;
    integer dcnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_s<=R_IDLE; arready<=1; rvalid<=0; rlast<=0; rdata<=0; rresp<=2'b00; rid<=0;
            raddr<=0; rbeat<=0; rlen<=0; rid_l<=0; dcnt<=0;
        end else begin
            case (rst_s)
                R_IDLE: begin
                    arready<=1;
                    if (arvalid && arready) begin
                        raddr<=araddr; rlen<=arlen; rid_l<=arid; rbeat<=0;
                        arready<=0; dcnt<=RD_DELAY; rst_s<=R_WAIT;
                    end
                end
                R_WAIT: begin
                    if (dcnt<=1) begin
                        rvalid<=1; rid<=rid_l; rresp<=2'b00;
                        rdata<=mem[(raddr>>2) % DEPTH];
                        rlast<=(rlen==0); rst_s<=R_DATA;
                    end else dcnt<=dcnt-1;
                end
                R_DATA: begin
                    if (rvalid && rready) begin
                        if (rlast) begin rvalid<=0; rlast<=0; arready<=1; rst_s<=R_IDLE; end
                        else begin
                            raddr<=raddr+4; rbeat<=rbeat+1;
                            rdata<=mem[((raddr+4)>>2) % DEPTH];
                            rlast<=((rbeat+1)==rlen);
                        end
                    end
                end
            endcase
        end
    end
endmodule
