// Opt-in L1 non-blocking transaction contract.
//
// This block deliberately exposes a small, explicit interface instead of
// silently changing dcache's legacy CPU handshake.  It accepts up to two
// distinct cache-line misses, merges one secondary request to an already
// outstanding line, preserves both request IDs in the responses, and drains a four-entry
// writeback queue.  The downstream line port may return responses out of
// order.  The default SoC continues to instantiate dcache.

module l1_cache_nb #(
    parameter MSHR_COUNT = 2,
    parameter WB_DEPTH   = 4,
    parameter SETS       = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_valid,
    input  wire        cpu_we,
    input  wire [3:0]  cpu_id,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_be,
    input  wire        cache_maint_invalidate,
    input  wire [4:0]  cache_maint_op,
    input  wire [31:0] cache_maint_addr,
    output wire        cache_maint_ready,
    output reg         cache_maint_done,
    output reg         cache_maint_error,
    output wire        cpu_ready,
    output reg         rsp_valid,
    output reg  [3:0]  rsp_id,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_error,
    input  wire        rsp_ready,

    output reg         mem_req_valid,
    output reg         mem_req_we,
    output reg  [31:0] mem_req_addr,
    output reg  [255:0] mem_req_wdata,
    input  wire        mem_req_ready,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_addr,
    input  wire [255:0] mem_rsp_data,
    input  wire        mem_rsp_error,
    output reg  [3:0]  mshr_occupancy,
    output reg  [3:0]  wb_occupancy
);
    localparam SET_BITS = $clog2(SETS);
    localparam TAG_BITS = 32 - 5 - SET_BITS;
    localparam MSHR_BITS = $clog2(MSHR_COUNT);
    localparam WB_BITS = $clog2(WB_DEPTH);

    reg valid [0:SETS-1];
    reg dirty [0:SETS-1];
    reg [TAG_BITS-1:0] tags [0:SETS-1];
    reg [255:0] lines [0:SETS-1];

    reg mvalid [0:MSHR_COUNT-1];
    reg miss_issued [0:MSHR_COUNT-1];
    reg [31:0] mline [0:MSHR_COUNT-1];
    reg [3:0] mid [0:MSHR_COUNT-1];
    reg [31:0] maddr [0:MSHR_COUNT-1];
    reg mwe [0:MSHR_COUNT-1];
    reg [31:0] mwdata [0:MSHR_COUNT-1];
    reg [3:0] mbe [0:MSHR_COUNT-1];
    reg secondary_valid [0:MSHR_COUNT-1];
    reg [3:0] secondary_id [0:MSHR_COUNT-1];
    reg [31:0] secondary_addr [0:MSHR_COUNT-1];
    reg secondary_we [0:MSHR_COUNT-1];
    reg [31:0] secondary_wdata [0:MSHR_COUNT-1];
    reg [3:0] secondary_be [0:MSHR_COUNT-1];

    // Refill responses can arrive out of order, and one refill can produce a
    // primary plus a secondary response in the same cycle.  Keep those
    // events in a FIFO instead of overwriting the single visible response
    // register.  The CPU-facing ready contract below still exposes one
    // request at a time for compatibility with the legacy owner.
    localparam RSP_DEPTH = MSHR_COUNT + 2;
    localparam RSP_BITS = (RSP_DEPTH <= 2) ? 1 : $clog2(RSP_DEPTH);
    reg [3:0] rsp_fifo_id [0:RSP_DEPTH-1];
    reg [31:0] rsp_fifo_data [0:RSP_DEPTH-1];
    reg rsp_fifo_error [0:RSP_DEPTH-1];
    reg [RSP_BITS-1:0] rsp_head, rsp_tail;
    reg [RSP_BITS:0] rsp_count;
    reg any_mvalid;

    reg [31:0] wb_addr [0:WB_DEPTH-1];
    reg [255:0] wb_data [0:WB_DEPTH-1];
    reg [WB_BITS-1:0] wb_head, wb_tail;
    reg [WB_BITS:0] wb_count;
    reg maint_active;

    wire [SET_BITS-1:0] req_set = cpu_addr[5 +: SET_BITS];
    wire [TAG_BITS-1:0] req_tag = cpu_addr[31 -: TAG_BITS];
    wire [31:0] req_line = {cpu_addr[31:5], 5'b0};
    wire hit = valid[req_set] && tags[req_set] == req_tag;
    reg free_mshr;
    reg [MSHR_BITS-1:0] free_mshr_i;
    reg merge_mshr;
    reg [MSHR_BITS-1:0] merge_mshr_i;
    integer i;
    always @(*) begin
        free_mshr = 1'b0; free_mshr_i = 0;
        merge_mshr = 1'b0; merge_mshr_i = 0;
        any_mvalid = 1'b0;
        for (i = 0; i < MSHR_COUNT; i = i + 1) begin
            if (mvalid[i]) any_mvalid = 1'b1;
            if (!mvalid[i] && !free_mshr) begin free_mshr = 1'b1; free_mshr_i = i; end
            if (mvalid[i] && mline[i] == req_line) begin merge_mshr = 1'b1; merge_mshr_i = i; end
        end
    end

    // The legacy CPU-facing contract has one visible response at a time. A
    // merged request consumes the per-MSHR secondary slot rather than being
    // silently dropped.
    always @(*) begin
        rsp_valid = (rsp_count != 0);
        rsp_id = rsp_fifo_id[rsp_head];
        rsp_rdata = rsp_fifo_data[rsp_head];
        rsp_error = rsp_fifo_error[rsp_head];
    end

    wire rsp_pop = (rsp_count != 0) && rsp_ready;
    wire hit_push = cpu_valid && cpu_ready && hit;
    reg mem_match;
    reg [MSHR_BITS-1:0] mem_match_i;
    integer match_i;
    always @(*) begin
        mem_match = 1'b0;
        mem_match_i = 0;
        for (match_i = 0; match_i < MSHR_COUNT; match_i = match_i + 1)
            if (mem_rsp_valid && mvalid[match_i] &&
                mline[match_i] == {mem_rsp_addr[31:5], 5'b0} && !mem_match) begin
                mem_match = 1'b1;
                mem_match_i = match_i;
            end
    end

    integer response_push_count;
    always @(*) begin
        response_push_count = 0;
        if (hit_push) response_push_count = response_push_count + 1;
        if (mem_match) begin
            response_push_count = response_push_count + 1;
            if (secondary_valid[mem_match_i])
                response_push_count = response_push_count + 1;
        end
    end

    assign cpu_ready = !maint_active && (rsp_count == 0) && (hit || merge_mshr || free_mshr) &&
                       (hit || !dirty[req_set] || wb_count < WB_DEPTH) &&
                       (!merge_mshr || !secondary_valid[merge_mshr_i]);

    // Maintenance is accepted only after all line requests, responses and
    // queued writebacks have drained. The CPU adapter holds CACHE valid until
    // the one-cycle completion indication is observed.
    assign cache_maint_ready = !maint_active && !cache_maint_done && !any_mvalid &&
                               (rsp_count == 0) && (wb_count == 0) &&
                               !mem_req_valid;

    integer j;
    always @(*) begin
        mem_req_valid = 1'b0; mem_req_we = 1'b0; mem_req_addr = 0;
        mem_req_wdata = 0;
        // Drain an eviction before issuing a refill.  A dirty victim and its
        // replacement can target the same downstream line resource; allowing
        // the refill to win here can return stale data before the victim is
        // visible in memory.
        if (wb_count != 0 && !mem_req_valid) begin
            mem_req_valid = 1'b1; mem_req_we = 1'b1;
            mem_req_addr = wb_addr[wb_head]; mem_req_wdata = wb_data[wb_head];
        end
        for (j = 0; j < MSHR_COUNT; j = j + 1)
            if (mvalid[j] && !miss_issued[j] && !mem_req_valid) begin
                mem_req_valid = 1'b1; mem_req_addr = mline[j];
            end
    end

    function automatic [255:0] merge_store;
        input [255:0] line;
        input [31:0] addr;
        input [31:0] wdata_in;
        input [3:0] be_in;
        reg [255:0] result;
        integer bit_offset;
        begin
            result = line;
            bit_offset = addr[4:2] * 32;
            if (be_in[0]) result[bit_offset +: 8] = wdata_in[7:0];
            if (be_in[1]) result[bit_offset + 8 +: 8] = wdata_in[15:8];
            if (be_in[2]) result[bit_offset + 16 +: 8] = wdata_in[23:16];
            if (be_in[3]) result[bit_offset + 24 +: 8] = wdata_in[31:24];
            merge_store = result;
        end
    endfunction

    integer k;
    reg [31:0] fill_word;
    reg [255:0] filled_line;
    reg [31:0] primary_rsp_word;
    reg [31:0] secondary_rsp_word;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_head <= 0; rsp_tail <= 0; rsp_count <= 0;
            wb_head <= 0; wb_tail <= 0; wb_count <= 0;
            maint_active <= 1'b0;
            cache_maint_done <= 1'b0;
            cache_maint_error <= 1'b0;
            mshr_occupancy <= 0; wb_occupancy <= 0;
            for (k = 0; k < SETS; k = k + 1) begin valid[k] <= 0; dirty[k] <= 0; end
            for (k = 0; k < MSHR_COUNT; k = k + 1) begin
                mvalid[k] <= 0; miss_issued[k] <= 0; secondary_valid[k] <= 0;
            end
        end else begin
            cache_maint_done <= 1'b0;
            cache_maint_error <= 1'b0;
            if (maint_active && wb_count == 0) begin
                maint_active <= 1'b0;
                cache_maint_done <= 1'b1;
            end
            if (cache_maint_invalidate && cache_maint_ready) begin
                /* The adapter serializes maintenance against live traffic.
                 * Writeback operations use the same ordered queue as normal
                 * eviction. Completion is delayed until that queue drains,
                 * so a following uncached access cannot observe stale data. */
                reg maint_match;
                reg maint_wb;
                reg maint_inv;
                maint_match = 1'b0;
                maint_wb = (cache_maint_op == 5'b00001) ||
                           (cache_maint_op == 5'b11001) ||
                           (cache_maint_op == 5'b11101);
                maint_inv = (cache_maint_op == 5'b00001) ||
                            (cache_maint_op == 5'b10101) ||
                            (cache_maint_op == 5'b11001);
                if (cache_maint_op == 5'b10101 ||
                    cache_maint_op == 5'b11001 ||
                    cache_maint_op == 5'b11101) begin
                    maint_match = valid[cache_maint_addr[5 +: SET_BITS]] &&
                                  tags[cache_maint_addr[5 +: SET_BITS]] ==
                                  cache_maint_addr[31 -: TAG_BITS];
                end else if (cache_maint_op == 5'b00001) begin
                    maint_match = valid[cache_maint_addr[5 +: SET_BITS]];
                end
                if (maint_match && maint_wb && dirty[cache_maint_addr[5 +: SET_BITS]]) begin
                    wb_addr[wb_tail] <= {tags[cache_maint_addr[5 +: SET_BITS]],
                                         cache_maint_addr[5 +: SET_BITS], 5'b0};
                    wb_data[wb_tail] <= lines[cache_maint_addr[5 +: SET_BITS]];
                    wb_tail <= wb_tail + 1'b1;
                    wb_count <= wb_count + 1'b1;
                    dirty[cache_maint_addr[5 +: SET_BITS]] <= 1'b0;
                    maint_active <= 1'b1;
                end
                if (maint_match && maint_inv) begin
                    valid[cache_maint_addr[5 +: SET_BITS]] <= 1'b0;
                    dirty[cache_maint_addr[5 +: SET_BITS]] <= 1'b0;
                end else if (maint_match && maint_wb) begin
                    dirty[cache_maint_addr[5 +: SET_BITS]] <= 1'b0;
                end else if (!maint_match &&
                             (cache_maint_op != 5'b10101) &&
                             (cache_maint_op != 5'b11001) &&
                             (cache_maint_op != 5'b11101) &&
                             (cache_maint_op != 5'b00001)) begin
                    for (k = 0; k < SETS; k = k + 1) begin
                        valid[k] <= 1'b0;
                        dirty[k] <= 1'b0;
                    end
                end
                for (k = 0; k < MSHR_COUNT; k = k + 1) begin
                    mvalid[k] <= 1'b0;
                    miss_issued[k] <= 1'b0;
                    secondary_valid[k] <= 1'b0;
                end
                if (!(maint_match && maint_wb && dirty[cache_maint_addr[5 +: SET_BITS]]))
                    cache_maint_done <= 1'b1;
            end

            if (rsp_pop)
                rsp_head <= rsp_head + 1'b1;

            // Enqueue hit, primary refill, and secondary responses in that
            // order.  A refill may contribute two entries; the count update
            // is therefore calculated once per cycle.
            if (hit_push) begin
                rsp_fifo_id[rsp_tail] <= cpu_id;
                rsp_fifo_data[rsp_tail] <= lines[req_set][cpu_addr[4:2]*32 +: 32];
                rsp_fifo_error[rsp_tail] <= 1'b0;
            end

            if (mem_req_valid && mem_req_ready) begin
`ifdef L1_NB_DEBUG
                $display("L1NB MEM_REQ %s addr=%h", mem_req_we ? "WB" : "RF", mem_req_addr);
`endif
                if (mem_req_we) begin
                    wb_head <= wb_head + 1'b1;
                    wb_count <= wb_count - 1'b1;
                end else begin
                    for (k = 0; k < MSHR_COUNT; k = k + 1)
                        if (mvalid[k] && !miss_issued[k] && mline[k] == mem_req_addr)
                            miss_issued[k] <= 1'b1;
                end
            end

            if (cpu_valid && cpu_ready) begin
`ifdef L1_NB_DEBUG
                $display("L1NB CPU_REQ %s id=%h addr=%h data=%h be=%h hit=%b merge=%b", cpu_we ? "ST" : "LD", cpu_id, cpu_addr, cpu_wdata, cpu_be, hit, merge_mshr);
`endif
                if (hit) begin
                    if (cpu_we) begin
                        fill_word = lines[req_set][cpu_addr[4:2]*32 +: 32];
                        if (cpu_be[0]) fill_word[7:0] = cpu_wdata[7:0];
                        if (cpu_be[1]) fill_word[15:8] = cpu_wdata[15:8];
                        if (cpu_be[2]) fill_word[23:16] = cpu_wdata[23:16];
                        if (cpu_be[3]) fill_word[31:24] = cpu_wdata[31:24];
                        lines[req_set][cpu_addr[4:2]*32 +: 32] <= fill_word;
                        dirty[req_set] <= 1'b1;
                    end
                end else if (!merge_mshr) begin
                    if (valid[req_set] && dirty[req_set]) begin
                        wb_addr[wb_tail] <= {tags[req_set], req_set, 5'b0};
                        wb_data[wb_tail] <= lines[req_set];
                        wb_tail <= wb_tail + 1'b1;
                        wb_count <= wb_count + 1'b1;
                    end
                    mvalid[free_mshr_i] <= 1'b1; miss_issued[free_mshr_i] <= 1'b0;
                    mline[free_mshr_i] <= req_line; mid[free_mshr_i] <= cpu_id;
                    maddr[free_mshr_i] <= cpu_addr;
                    mwe[free_mshr_i] <= cpu_we; mwdata[free_mshr_i] <= cpu_wdata;
                    mbe[free_mshr_i] <= cpu_be;
                end else begin
                    secondary_valid[merge_mshr_i] <= 1'b1;
                    secondary_id[merge_mshr_i] <= cpu_id;
                    secondary_addr[merge_mshr_i] <= cpu_addr;
                    secondary_we[merge_mshr_i] <= cpu_we;
                    secondary_wdata[merge_mshr_i] <= cpu_wdata;
                    secondary_be[merge_mshr_i] <= cpu_be;
                end
            end

            if (mem_rsp_valid) begin
`ifdef L1_NB_DEBUG
                $display("L1NB MEM_RSP addr=%h err=%b data0=%h", mem_rsp_addr, mem_rsp_error, mem_rsp_data[31:0]);
`endif
                for (k = 0; k < MSHR_COUNT; k = k + 1)
                    if (mvalid[k] && mline[k] == {mem_rsp_addr[31:5],5'b0}) begin
                        valid[mem_rsp_addr[5 +: SET_BITS]] <= !mem_rsp_error;
                        dirty[mem_rsp_addr[5 +: SET_BITS]] <=
                            (mwe[k] || secondary_valid[k]) && !mem_rsp_error;
                        tags[mem_rsp_addr[5 +: SET_BITS]] <=
                            mem_rsp_addr[31 -: TAG_BITS];
                        filled_line = mem_rsp_data;
                        if (mwe[k] && !mem_rsp_error)
                            filled_line = merge_store(filled_line, maddr[k], mwdata[k], mbe[k]);
                        primary_rsp_word = filled_line[maddr[k][4:2]*32 +: 32];
                        if (secondary_valid[k] && !mem_rsp_error)
                            filled_line = merge_store(filled_line, secondary_addr[k],
                                                      secondary_wdata[k], secondary_be[k]);
                        secondary_rsp_word = filled_line[secondary_addr[k][4:2]*32 +: 32];
                        lines[mem_rsp_addr[5 +: SET_BITS]] <= filled_line;
                        rsp_fifo_id[rsp_tail + hit_push] <= mid[k];
                        rsp_fifo_data[rsp_tail + hit_push] <= primary_rsp_word;
                        rsp_fifo_error[rsp_tail + hit_push] <= mem_rsp_error;
                        if (secondary_valid[k]) begin
                            rsp_fifo_id[rsp_tail + hit_push + 1'b1] <= secondary_id[k];
                            rsp_fifo_data[rsp_tail + hit_push + 1'b1] <= secondary_rsp_word;
                            rsp_fifo_error[rsp_tail + hit_push + 1'b1] <= mem_rsp_error;
                        end
                        secondary_valid[k] <= 1'b0;
                        mvalid[k] <= 1'b0;
                    end
            end
            if (response_push_count != 0)
                rsp_tail <= rsp_tail + response_push_count;
`ifdef L1_NB_DEBUG
            if (response_push_count != 0)
                $display("L1NB RSP_PUSH count=%0d id0=%h data0=%h", response_push_count,
                         rsp_fifo_id[rsp_tail], rsp_fifo_data[rsp_tail]);
`endif
            if (response_push_count != 0 || rsp_pop)
                rsp_count <= rsp_count + response_push_count - (rsp_pop ? 1 : 0);
            // Build occupancy from the current MSHR bitmap. Nonblocking
            // assignments to the output itself would otherwise accumulate
            // from its previous value instead of counting the entries.
            mshr_occupancy = 0;
            for (k = 0; k < MSHR_COUNT; k = k + 1)
                if (mvalid[k]) mshr_occupancy = mshr_occupancy + 1'b1;
            wb_occupancy <= wb_count;
        end
    end
endmodule
