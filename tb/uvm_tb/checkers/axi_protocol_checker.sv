`ifndef AXI_PROTOCOL_CHECKER_SV
`define AXI_PROTOCOL_CHECKER_SV

module axi_protocol_checker #(
    parameter string CHECKER_NAME = "axi",
    parameter bit    REQUIRE_SINGLE_OUTSTANDING = 1'b1,
    parameter bit    REQUIRE_W_AFTER_AW = 1'b1
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [3:0]  awid,
    input  logic [31:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,
    input  logic [1:0]  awlock,
    input  logic [3:0]  awcache,
    input  logic [2:0]  awprot,
    input  logic        awvalid,
    input  logic        awready,

    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wlast,
    input  logic        wvalid,
    input  logic        wready,

    input  logic [3:0]  bid,
    input  logic [1:0]  bresp,
    input  logic        bvalid,
    input  logic        bready,

    input  logic [3:0]  arid,
    input  logic [31:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,
    input  logic [1:0]  arlock,
    input  logic [3:0]  arcache,
    input  logic [2:0]  arprot,
    input  logic        arvalid,
    input  logic        arready,

    input  logic [3:0]  rid,
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    input  logic        rlast,
    input  logic        rvalid,
    input  logic        rready
);

    logic        aw_hold_q;
    logic [57:0] aw_payload_q;
    logic        w_hold_q;
    logic [36:0] w_payload_q;
    logic        b_hold_q;
    logic [5:0]  b_payload_q;
    logic        ar_hold_q;
    logic [57:0] ar_payload_q;
    logic        r_hold_q;
    logic [38:0] r_payload_q;

    typedef struct {
        logic [3:0] id;
        logic [8:0] expected_beats;
        logic [8:0] seen_beats;
    } write_req_s;

    typedef struct {
        logic [8:0] expected_beats;
        logic [8:0] seen_beats;
    } read_req_s;

    write_req_s write_data_q[$];
    logic [3:0] write_resp_q[16][$];
    read_req_s  read_q[16][$];

    wire         aw_fire = awvalid && awready;
    wire         w_fire  = wvalid  && wready;
    wire         b_fire  = bvalid  && bready;
    wire         ar_fire = arvalid && arready;
    wire         r_fire  = rvalid  && rready;

    wire [57:0] aw_payload = {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot};
    wire [36:0] w_payload  = {wdata, wstrb, wlast};
    wire [5:0]  b_payload  = {bid, bresp};
    wire [57:0] ar_payload = {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot};
    wire [38:0] r_payload  = {rid, rdata, rresp, rlast};

    function int unsigned write_outstanding_count();
        int unsigned count;

        count = write_data_q.size();
        for (int i = 0; i < 16; i++) begin
            count += write_resp_q[i].size();
        end
        return count;
    endfunction

    function int unsigned read_outstanding_count();
        int unsigned count;

        count = 0;
        for (int i = 0; i < 16; i++) begin
            count += read_q[i].size();
        end
        return count;
    endfunction

    always @(posedge clk or negedge rst_n) begin
        automatic write_req_s write_req;
        automatic read_req_s  read_req;
        automatic logic [3:0] resp_id;
        automatic logic [8:0] next_write_beat;
        automatic logic [8:0] next_read_beat;

        if (!rst_n) begin
            aw_hold_q           <= 1'b0;
            aw_payload_q        <= '0;
            w_hold_q            <= 1'b0;
            w_payload_q         <= '0;
            b_hold_q            <= 1'b0;
            b_payload_q         <= '0;
            ar_hold_q           <= 1'b0;
            ar_payload_q        <= '0;
            r_hold_q            <= 1'b0;
            r_payload_q         <= '0;
            write_data_q.delete();
            for (int i = 0; i < 16; i++) begin
                write_resp_q[i].delete();
                read_q[i].delete();
            end
        end else begin
            if (aw_hold_q) begin
                if (!awvalid) begin
                    $error("[%0t] %s: AWVALID deasserted before AWREADY", $time, CHECKER_NAME);
                end
                if (aw_payload !== aw_payload_q) begin
                    $error("[%0t] %s: AW payload changed while AWVALID waited for AWREADY", $time, CHECKER_NAME);
                end
            end
            if (w_hold_q) begin
                if (!wvalid) begin
                    $error("[%0t] %s: WVALID deasserted before WREADY", $time, CHECKER_NAME);
                end
                if (w_payload !== w_payload_q) begin
                    $error("[%0t] %s: W payload changed while WVALID waited for WREADY", $time, CHECKER_NAME);
                end
            end
            if (b_hold_q) begin
                if (!bvalid) begin
                    $error("[%0t] %s: BVALID deasserted before BREADY", $time, CHECKER_NAME);
                end
                if (b_payload !== b_payload_q) begin
                    $error("[%0t] %s: B payload changed while BVALID waited for BREADY", $time, CHECKER_NAME);
                end
            end
            if (ar_hold_q) begin
                if (!arvalid) begin
                    $error("[%0t] %s: ARVALID deasserted before ARREADY; held={id=%h addr=%h len=%h size=%h burst=%h lock=%h cache=%h prot=%h}",
                           $time, CHECKER_NAME, ar_payload_q[57:54], ar_payload_q[53:22],
                           ar_payload_q[21:14], ar_payload_q[13:11], ar_payload_q[10:9],
                           ar_payload_q[8:7], ar_payload_q[6:3], ar_payload_q[2:0]);
                end
                if (ar_payload !== ar_payload_q) begin
                    $error("[%0t] %s: AR payload changed while ARVALID waited for ARREADY; held={id=%h addr=%h len=%h size=%h burst=%h lock=%h cache=%h prot=%h} current={id=%h addr=%h len=%h size=%h burst=%h lock=%h cache=%h prot=%h}",
                           $time, CHECKER_NAME,
                           ar_payload_q[57:54], ar_payload_q[53:22], ar_payload_q[21:14],
                           ar_payload_q[13:11], ar_payload_q[10:9], ar_payload_q[8:7],
                           ar_payload_q[6:3], ar_payload_q[2:0],
                           arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot);
                end
            end
            if (r_hold_q) begin
                if (!rvalid) begin
                    $error("[%0t] %s: RVALID deasserted before RREADY", $time, CHECKER_NAME);
                end
                if (r_payload !== r_payload_q) begin
                    $error("[%0t] %s: R payload changed while RVALID waited for RREADY", $time, CHECKER_NAME);
                end
            end

            if (aw_fire) begin
                if (REQUIRE_SINGLE_OUTSTANDING &&
                    (write_outstanding_count() != 0) &&
                    !(b_fire && (write_resp_q[bid].size() != 0))) begin
                    $error("[%0t] %s: AW accepted while another write transaction is outstanding", $time, CHECKER_NAME);
                end
                write_req.id             = awid;
                write_req.expected_beats = {1'b0, awlen} + 9'd1;
                write_req.seen_beats     = '0;
                write_data_q.push_back(write_req);
            end

            if (w_fire) begin
                if (REQUIRE_W_AFTER_AW && (write_data_q.size() == 0)) begin
                    $error("[%0t] %s: W beat accepted before an AW transaction", $time, CHECKER_NAME);
                end else if (write_data_q.size() != 0) begin
                    write_req = write_data_q[0];
                    next_write_beat = write_req.seen_beats + 9'd1;

                    if (wlast !== (next_write_beat == write_req.expected_beats)) begin
                        $error("[%0t] %s: WLAST mismatch beat=%0d expected_beats=%0d wlast=%0b",
                               $time, CHECKER_NAME, next_write_beat, write_req.expected_beats, wlast);
                    end

                    write_req.seen_beats = next_write_beat;
                    if (next_write_beat == write_req.expected_beats) begin
                        void'(write_data_q.pop_front());
                        write_resp_q[write_req.id].push_back(write_req.id);
                    end else begin
                        write_data_q[0] = write_req;
                    end
                end
            end

            if (bvalid) begin
                if (write_resp_q[bid].size() == 0) begin
                    $error("[%0t] %s: BVALID asserted with no completed write data for BID=%0d",
                           $time, CHECKER_NAME, bid);
                end
            end

            if (b_fire) begin
                resp_id = bid;
                if (write_resp_q[resp_id].size() != 0) begin
                    void'(write_resp_q[resp_id].pop_front());
                end
            end

            if (ar_fire) begin
                if (REQUIRE_SINGLE_OUTSTANDING &&
                    (read_outstanding_count() != 0) &&
                    !(r_fire && rlast && (read_q[rid].size() != 0))) begin
                    $error("[%0t] %s: AR accepted while another read transaction is outstanding", $time, CHECKER_NAME);
                end
                read_req.expected_beats = {1'b0, arlen} + 9'd1;
                read_req.seen_beats     = '0;
                read_q[arid].push_back(read_req);
            end

            if (rvalid) begin
                if (read_q[rid].size() == 0) begin
                    $error("[%0t] %s: RVALID asserted with no read transaction outstanding for RID=%0d",
                           $time, CHECKER_NAME, rid);
                end else if (r_fire) begin
                    read_req = read_q[rid][0];
                    next_read_beat = read_req.seen_beats + 9'd1;

                    if (rlast !== (next_read_beat == read_req.expected_beats)) begin
                        $error("[%0t] %s: RLAST mismatch beat=%0d expected_beats=%0d rlast=%0b",
                               $time, CHECKER_NAME, next_read_beat, read_req.expected_beats, rlast);
                    end

                    read_req.seen_beats = next_read_beat;
                    if (next_read_beat == read_req.expected_beats) begin
                        void'(read_q[rid].pop_front());
                    end else begin
                        read_q[rid][0] = read_req;
                    end
                end
            end

            aw_hold_q    <= awvalid && !awready;
            aw_payload_q <= aw_payload;
            w_hold_q     <= wvalid && !wready;
            w_payload_q  <= w_payload;
            b_hold_q     <= bvalid && !bready;
            b_payload_q  <= b_payload;
            ar_hold_q    <= arvalid && !arready;
            ar_payload_q <= ar_payload;
            r_hold_q     <= rvalid && !rready;
            r_payload_q  <= r_payload;
        end
    end

endmodule

`endif
