// =============================================================================
// axi_mo_slave.v — MULTI-outstanding in-order AXI4 read slave (TB only).
// Accepts up to Q ARs before responding (arready stays high while queue !full),
// then returns single-beat OKAY responses in order after LAT cycles each.
// Used by tb_xbar_multi_ot to prove the crossbar accepts N_OT outstanding ARs
// at its boundary (readiness for a future non-blocking L2 / MSHR L1).
// =============================================================================
`timescale 1ns/1ps

module axi_mo_slave #(
    parameter IDW=4, parameter AW=32, parameter DW=32, parameter Q=4, parameter LAT=4
) (
    input  wire clk, input wire rst_n,
    input  wire [IDW-1:0] arid, input wire [AW-1:0] araddr, input wire [7:0] arlen,
    input  wire arvalid, output wire arready,
    output reg  [IDW-1:0] rid, output reg [DW-1:0] rdata, output reg [1:0] rresp,
    output reg  rlast, output reg rvalid, input wire rready
);
    // simple FIFO of accepted requests
    reg [IDW-1:0] q_id [0:Q-1];
    reg [AW-1:0]  q_addr[0:Q-1];
    integer head, tail, cnt;
    integer wait_cnt;

    assign arready = (cnt < Q);
    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head<=0; tail<=0; cnt<=0; wait_cnt<=0;
            rvalid<=0; rlast<=0; rid<=0; rdata<=0; rresp<=2'b00;
        end else begin
            // accept AR
            if (ar_fire) begin
                q_id[tail]<=arid; q_addr[tail]<=araddr;
                tail<=(tail+1)%Q;
            end
            // response engine (single beat per request)
            if (!rvalid && (cnt != 0 || ar_fire)) begin
                if (wait_cnt >= LAT-1) begin
                    rvalid<=1; rlast<=1;
                    rid<=q_id[head]; rdata<={q_addr[head]}; rresp<=2'b00;
                    wait_cnt<=0;
                end else wait_cnt<=wait_cnt+1;
            end else if (r_fire) begin
                rvalid<=0; rlast<=0;
                head<=(head+1)%Q;
            end
            // count update
            case ({ar_fire, (r_fire?1'b1:1'b0)})
                2'b10: cnt<=cnt+1;
                2'b01: cnt<=cnt-1;
                default: cnt<=cnt;
            endcase
        end
    end
endmodule
