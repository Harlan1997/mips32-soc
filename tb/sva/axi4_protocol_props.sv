// AXI4 safety properties for the current single-outstanding contract.
`ifdef SVA_ENABLE
module axi4_protocol_props #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic                    clk,
    input logic                    rst_n,
    input logic                    awvalid, awready,
    input logic [ID_WIDTH-1:0]     awid,
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic [7:0]              awlen,
    input logic [2:0]              awsize,
    input logic [1:0]              awburst,
    input logic                    wvalid, wready,
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic                    wlast,
    input logic                    bvalid, bready,
    input logic [ID_WIDTH-1:0]     bid,
    input logic [1:0]              bresp,
    input logic                    arvalid, arready,
    input logic [ID_WIDTH-1:0]     arid,
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic [7:0]              arlen,
    input logic                    rvalid, rready,
    input logic [ID_WIDTH-1:0]     rid,
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rlast
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    property p_aw_stable;
        awvalid && !awready |=> awvalid && $stable(awaddr) &&
            $stable(awid) && $stable(awlen) && $stable(awsize) &&
            $stable(awburst);
    endproperty
    AW_STABLE: assert property (p_aw_stable)
        else $error("SVA_FAIL AXI4: AW payload changed before AWREADY");

    property p_w_stable;
        wvalid && !wready |=> wvalid && $stable(wdata) && $stable(wlast);
    endproperty
    W_STABLE: assert property (p_w_stable)
        else $error("SVA_FAIL AXI4: W payload changed before WREADY");

    property p_b_stable;
        bvalid && !bready |=> bvalid && $stable(bid) && $stable(bresp);
    endproperty
    B_STABLE: assert property (p_b_stable)
        else $error("SVA_FAIL AXI4: B response changed before BREADY");

    property p_ar_stable;
        arvalid && !arready |=> arvalid && $stable(araddr) &&
            $stable(arid) && $stable(arlen);
    endproperty
    AR_STABLE: assert property (p_ar_stable)
        else $error("SVA_FAIL AXI4: AR payload changed before ARREADY");

    property p_r_stable;
        rvalid && !rready |=> rvalid && $stable(rid) && $stable(rdata) &&
            $stable(rresp) && $stable(rlast);
    endproperty
    R_STABLE: assert property (p_r_stable)
        else $error("SVA_FAIL AXI4: R response changed before RREADY");

    logic       write_active, read_active;
    logic [7:0] write_len, write_beat;
    logic [7:0] read_len, read_beat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_active <= 1'b0;
            write_len    <= 8'd0;
            write_beat   <= 8'd0;
            read_active  <= 1'b0;
            read_len     <= 8'd0;
            read_beat    <= 8'd0;
        end else begin
            if (awvalid && awready) begin
                write_active <= 1'b1;
                write_len    <= awlen;
                write_beat   <= 8'd0;
            end else if (bvalid && bready) begin
                write_active <= 1'b0;
            end
            if (wvalid && wready && !wlast)
                write_beat <= write_beat + 8'd1;

            if (arvalid && arready) begin
                read_active <= 1'b1;
                read_len    <= arlen;
                read_beat   <= 8'd0;
            end else if (rvalid && rready && rlast) begin
                read_active <= 1'b0;
            end
            if (rvalid && rready && !rlast)
                read_beat <= read_beat + 8'd1;
        end
    end

    property p_wlast_count;
        wvalid && wready && write_active |-> (wlast == (write_beat == write_len));
    endproperty
    WLAST_COUNT: assert property (p_wlast_count)
        else $error("SVA_FAIL AXI4: WLAST does not match AWLEN");

    property p_rlast_count;
        rvalid && rready && read_active |-> (rlast == (read_beat == read_len));
    endproperty
    RLAST_COUNT: assert property (p_rlast_count)
        else $error("SVA_FAIL AXI4: RLAST does not match ARLEN");

    property p_no_second_aw;
        write_active && !(bvalid && bready) |-> !awvalid;
    endproperty
    NO_SECOND_AW: assert property (p_no_second_aw)
        else $error("SVA_FAIL AXI4: second AW issued before B completed");

    property p_no_second_ar;
        read_active && !(rvalid && rready && rlast) |-> !arvalid;
    endproperty
    NO_SECOND_AR: assert property (p_no_second_ar)
        else $error("SVA_FAIL AXI4: second AR issued before R burst completed");

    cover property (awvalid && !awready ##1 awvalid && awready);
    cover property (wvalid && !wready ##1 wvalid && wready);
    cover property (arvalid && !arready ##1 arvalid && arready);
    cover property (rvalid && !rready ##1 rvalid && rready);
    cover property (awvalid && awready ##[1:20] bvalid && bready);
    cover property (arvalid && arready ##[1:20] rvalid && rlast && rready);
endmodule
`endif
