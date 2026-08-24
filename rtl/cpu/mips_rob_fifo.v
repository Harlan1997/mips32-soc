// Four-entry in-order retirement FIFO used by the opt-in nonblocking CPU.
// The current MEM stage supplies completed data, so entries are ready at
// allocation. The explicit ready bit and complete-tag extension point keep
// the ordering contract visible for late cache responses.
module mips_rob_fifo #(
    parameter DEPTH = 4,
    parameter READY_AT_ALLOC = 1'b1,
    parameter TAG_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
    input wire clk, input wire rst_n, input wire stall, input wire flush,
    input wire complete_valid, input wire [TAG_W-1:0] complete_tag,
    input wire [31:0] complete_rdata, input wire complete_error,
    input wire mem_alloc_valid, input wire mem_ready_at_alloc,
    input wire [31:0] mem_rdata_fmt, input wire [31:0] mem_ex_out,
    input wire [31:0] mem_pc_plus_8, input wire [31:0] mem_inst,
    input wire [31:0] mem_val_rt, input wire mem_mem_read,
    input wire mem_mem_write, input wire [2:0] mem_mem_op,
    input wire [4:0] mem_waddr, input wire [4:0] mem_rd_addr,
    input wire [4:0] mem_cp0_raddr, input wire [2:0] mem_cp0_sel,
    input wire mem_reg_write, input wire mem_cp0_we, input wire mem_is_eret,
    input wire [2:0] mem_tlb_op, input wire mem_except_req,
    input wire [4:0] mem_except_code, input wire mem_except_is_data,
    input wire mem_except_is_tlb_refill, input wire mem_bd,
    input wire [31:0] mem_delay_slot_next_pc, input wire [1:0] mem_mem_to_reg,
    output reg [31:0] wb_rdata_fmt, output reg [31:0] wb_ex_out,
    output reg [31:0] wb_pc_plus_8, output reg [31:0] wb_inst,
    output reg [31:0] wb_val_rt, output reg wb_mem_read,
    output reg wb_mem_write, output reg [2:0] wb_mem_op, output reg wb_valid,
    output reg [4:0] wb_waddr, output reg [4:0] wb_rd_addr,
    output reg [4:0] wb_cp0_raddr, output reg [2:0] wb_cp0_sel,
    output reg wb_reg_write, output reg wb_cp0_we, output reg wb_is_eret,
    output reg [2:0] wb_tlb_op, output reg wb_except_req,
    output reg [4:0] wb_except_code, output reg wb_except_is_data,
    output reg wb_except_is_tlb_refill, output reg wb_bd,
    output reg [31:0] wb_delay_slot_next_pc, output reg [1:0] wb_mem_to_reg
    , output wire [TAG_W-1:0] alloc_tag, output wire alloc_ready,
    output wire head_ready, output wire busy,
    output reg [TAG_W-1:0] wb_tag
);
    localparam PTR_W = TAG_W;
    localparam BW = 232;
    reg [BW-1:0] slot [0:DEPTH-1];
    reg valid [0:DEPTH-1];
    reg ready [0:DEPTH-1];
    reg [PTR_W-1:0] head, tail;
    reg [PTR_W:0] count;

    wire [BW-1:0] alloc_bundle = {
        mem_rdata_fmt, mem_ex_out, mem_pc_plus_8, mem_inst, mem_val_rt,
        mem_mem_read, mem_mem_write, mem_mem_op,
        mem_waddr, mem_rd_addr, mem_cp0_raddr, mem_cp0_sel,
        mem_reg_write, mem_cp0_we, mem_is_eret, mem_tlb_op,
        mem_except_req, mem_except_code, mem_except_is_data,
        mem_except_is_tlb_refill, mem_bd, mem_delay_slot_next_pc,
        mem_mem_to_reg
    };
    wire alloc_valid = mem_alloc_valid;
    // The integrated nonblocking CPU allocates a load as an unready entry
    // and can retire it on the tagged response edge.  Keep this bypass
    // opt-in through READY_AT_ALLOC so the standalone ROB contract, which
    // deliberately tests registered completion latency with READY_AT_ALLOC=0,
    // remains unchanged.
    wire head_complete_now = READY_AT_ALLOC && complete_valid &&
                             (count != 0) && (complete_tag == head);
    wire buffered_commit = valid[head] &&
                           (ready[head] || head_complete_now) &&
                           (count != 0);
    // Preserve the existing MEM/WB latency while the FIFO is empty. A future
    // late-response producer can fill the queue; once occupied, commit is
    // strictly from head and allocation/commit may occur in the same cycle.
    // A nonblocking CPU must not bypass an empty FIFO.  Cut-through makes the
    // registered WB interface observe a different instruction boundary from
    // the allocation/retirement bookkeeping when a load response and the next
    // MEM entry meet.  Keeping every entry in the FIFO preserves one retire
    // lifecycle for ordinary instructions and late loads alike.
    wire cutthrough_commit = (DEPTH == 1) && alloc_valid && (count == 0) &&
                             !stall && READY_AT_ALLOC && mem_ready_at_alloc;
    wire commit_fire = !stall && (buffered_commit || cutthrough_commit);
    wire alloc_fire = alloc_valid && !stall && !cutthrough_commit &&
                      ((count < DEPTH) || buffered_commit);
    wire [31:0] head_complete_fmt = format_complete(
        complete_rdata, slot[head][69:67], slot[head][169:168],
        slot[head][103:72]);
    // A response can make the head retire in the same clock edge.  The slot
    // array is updated with nonblocking assignments below, so reading
    // slot[head] here would commit its previous load value.  Bypass only the
    // response-owned data field; all instruction metadata remains ordered in
    // the already allocated slot.
    // The completion can retire the head on the same edge that it becomes
    // ready.  Carry the response error through this bypass as well as the
    // data value; otherwise a failed load is first retired as a normal
    // instruction and the reused tag receives the stale CacheErr metadata.
    wire [BW-1:0] head_complete_bundle = {
        head_complete_fmt,
        slot[head][199:43],
        complete_error ? 1'b1 : slot[head][42],
        complete_error ? 5'h1e : slot[head][41:37],
        complete_error ? 1'b1 : slot[head][36],
        slot[head][35:0]
    };
    wire [BW-1:0] commit_bundle = cutthrough_commit ? alloc_bundle :
                                   (head_complete_now ? head_complete_bundle :
                                    slot[head]);
    assign alloc_tag = tail;
    assign alloc_ready = (count < DEPTH) || buffered_commit;
    assign head_ready = buffered_commit;
    assign busy = (count != 0);

    function automatic [31:0] format_complete;
        input [31:0] raw;
        input [2:0] op;
        input [1:0] align;
        input [31:0] rt;
        begin
            case (op)
                3'b000: case (align)
                    2'b00: format_complete = {{24{raw[7]}}, raw[7:0]};
                    2'b01: format_complete = {{24{raw[15]}}, raw[15:8]};
                    2'b10: format_complete = {{24{raw[23]}}, raw[23:16]};
                    default: format_complete = {{24{raw[31]}}, raw[31:24]};
                endcase
                3'b001: case (align)
                    2'b00: format_complete = {24'd0, raw[7:0]};
                    2'b01: format_complete = {24'd0, raw[15:8]};
                    2'b10: format_complete = {24'd0, raw[23:16]};
                    default: format_complete = {24'd0, raw[31:24]};
                endcase
                3'b010: format_complete = align[1] ? {{16{raw[31]}}, raw[31:16]} :
                                                   {{16{raw[15]}}, raw[15:0]};
                3'b011: format_complete = align[1] ? {16'd0, raw[31:16]} :
                                                   {16'd0, raw[15:0]};
                3'b101: case (align)
                    2'b00: format_complete = {raw[7:0], rt[23:0]};
                    2'b01: format_complete = {raw[15:0], rt[15:0]};
                    2'b10: format_complete = {raw[23:0], rt[7:0]};
                    default: format_complete = raw;
                endcase
                3'b110: case (align)
                    2'b00: format_complete = raw;
                    2'b01: format_complete = {rt[31:24], raw[31:8]};
                    2'b10: format_complete = {rt[31:16], raw[31:16]};
                    default: format_complete = {rt[31:8], raw[31:24]};
                endcase
                default: format_complete = raw;
            endcase
        end
    endfunction
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
`ifdef ROB_FIFO_DEBUG
            if (flush && rst_n)
                $display("ROBF flush head=%0d tail=%0d count=%0d v=%b%b%b%b r=%b%b%b%b", head, tail, count, valid[3], valid[2], valid[1], valid[0], ready[3], ready[2], ready[1], ready[0]);
`endif
            head <= 0; tail <= 0; count <= 0; wb_valid <= 1'b0;
            wb_tag <= 0;
            wb_rdata_fmt <= 0; wb_ex_out <= 0; wb_pc_plus_8 <= 0;
            wb_inst <= 0; wb_val_rt <= 0; wb_mem_read <= 0;
            wb_mem_write <= 0; wb_mem_op <= 0; wb_waddr <= 0; wb_rd_addr <= 0;
            wb_cp0_raddr <= 0; wb_cp0_sel <= 0; wb_reg_write <= 0;
            wb_cp0_we <= 0; wb_is_eret <= 0; wb_tlb_op <= 0;
            wb_except_req <= 0; wb_except_code <= 0; wb_except_is_data <= 0;
            wb_except_is_tlb_refill <= 0; wb_bd <= 0;
            wb_delay_slot_next_pc <= 0; wb_mem_to_reg <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid[i] <= 1'b0;
                ready[i] <= 1'b0;
            end
        end else begin
`ifdef ROB_FIFO_DEBUG
            if (complete_valid)
                $display("ROBF complete tag=%0d err=%b head=%0d tail=%0d count=%0d v=%b%b%b%b r=%b%b%b%b", complete_tag, complete_error, head, tail, count, valid[3], valid[2], valid[1], valid[0], ready[3], ready[2], ready[1], ready[0]);
            if (alloc_fire)
                $display("ROBF alloc tag=%0d pc8=%h ready=%b head=%0d tail=%0d count=%0d", tail, mem_pc_plus_8, mem_ready_at_alloc, head, tail, count);
            if (commit_fire)
                $display("ROBF commit tag=%0d exc=%b code=%0d head=%0d tail=%0d count=%0d v=%b%b%b%b r=%b%b%b%b", cutthrough_commit ? tail : head, commit_bundle[42], commit_bundle[41:37], head, tail, count, valid[3], valid[2], valid[1], valid[0], ready[3], ready[2], ready[1], ready[0]);
`endif
            // The output bundle and its valid bit are a registered interface.
            // Do not suppress commits by PC: the same PC may retire again
            // after an exception/interrupt flush, and slot validity already
            // provides the required lifecycle protection.
            wb_valid <= commit_fire;
            if (commit_fire) begin
                wb_tag <= cutthrough_commit ? tail : head;
                wb_rdata_fmt <= commit_bundle[231:200];
                wb_ex_out <= commit_bundle[199:168];
                wb_pc_plus_8 <= commit_bundle[167:136];
                wb_inst <= commit_bundle[135:104];
                wb_val_rt <= commit_bundle[103:72];
                wb_mem_read <= commit_bundle[71]; wb_mem_write <= commit_bundle[70];
                wb_mem_op <= commit_bundle[69:67];
                wb_waddr <= commit_bundle[66:62]; wb_rd_addr <= commit_bundle[61:57];
                wb_cp0_raddr <= commit_bundle[56:52]; wb_cp0_sel <= commit_bundle[51:49];
                wb_reg_write <= commit_bundle[48]; wb_cp0_we <= commit_bundle[47];
                wb_is_eret <= commit_bundle[46]; wb_tlb_op <= commit_bundle[45:43];
                wb_except_req <= commit_bundle[42]; wb_except_code <= commit_bundle[41:37];
                wb_except_is_data <= commit_bundle[36];
                wb_except_is_tlb_refill <= commit_bundle[35]; wb_bd <= commit_bundle[34];
                wb_delay_slot_next_pc <= commit_bundle[33:2];
                wb_mem_to_reg <= commit_bundle[1:0];
                if (buffered_commit) begin
                    valid[head] <= 1'b0;
                    ready[head] <= 1'b0;
                    head <= head + 1'b1;
                end
            end else if (!stall) begin
                // Preserve the legacy MEM/WB bubble contract.  In
                // particular, exception and CP0 controls must not remain
                // asserted from an older committed entry while the FIFO is
                // empty or the current MEM cycle is a bubble.
                wb_rdata_fmt <= mem_rdata_fmt;
                wb_ex_out <= mem_ex_out;
                wb_pc_plus_8 <= mem_pc_plus_8;
                wb_inst <= mem_inst;
                wb_val_rt <= mem_val_rt;
                wb_mem_read <= mem_mem_read;
                wb_mem_write <= mem_mem_write;
                wb_mem_op <= mem_mem_op;
                wb_waddr <= mem_waddr;
                wb_rd_addr <= mem_rd_addr;
                wb_cp0_raddr <= mem_cp0_raddr;
                wb_cp0_sel <= mem_cp0_sel;
                wb_reg_write <= mem_reg_write;
                wb_cp0_we <= mem_cp0_we;
                wb_is_eret <= mem_is_eret;
                wb_tlb_op <= mem_tlb_op;
                wb_except_req <= mem_except_req;
                wb_except_code <= mem_except_code;
                wb_except_is_data <= mem_except_is_data;
                wb_except_is_tlb_refill <= mem_except_is_tlb_refill;
                wb_bd <= mem_bd;
                wb_delay_slot_next_pc <= mem_delay_slot_next_pc;
                wb_mem_to_reg <= mem_mem_to_reg;
            end
            if (alloc_fire) begin
                slot[tail] <= alloc_bundle;
                valid[tail] <= 1'b1;
                ready[tail] <= READY_AT_ALLOC && mem_ready_at_alloc;
                tail <= tail + 1'b1;
            end
            // A cache hit/response may be visible in the same cycle that a
            // retiring head frees the slot which is being reused as tail.
            // The newly allocated slot is not `valid` until this edge, so it
            // needs an explicit completion bypass. If the queue is full and
            // head==tail, an old-head completion wins over the new allocation
            // because the tag still names the retiring entry.
            if (complete_valid && alloc_fire &&
                !(buffered_commit && (complete_tag == head)) &&
                (complete_tag == tail)) begin
                slot[tail][231:200] <= format_complete(
                    complete_rdata, alloc_bundle[69:67],
                    alloc_bundle[169:168], alloc_bundle[103:72]);
                if (complete_error) begin
                    slot[tail][42] <= 1'b1;
                    slot[tail][41:37] <= 5'h1E;
                    slot[tail][36] <= 1'b1;
                end
                ready[tail] <= 1'b1;
            end else if (complete_valid && (complete_tag < DEPTH) && valid[complete_tag] &&
                         !(buffered_commit && (complete_tag == head))) begin
                // A late cache response owns the data field of the original
                // instruction.  Error is converted at retirement so younger
                // entries cannot observe a transient response-side fault.
                slot[complete_tag][231:200] <= format_complete(
                    complete_rdata, slot[complete_tag][69:67],
                    slot[complete_tag][169:168], slot[complete_tag][103:72]);
                if (complete_error) begin
                    slot[complete_tag][42] <= 1'b1;  // exception request
                    slot[complete_tag][41:37] <= 5'h1E; // CacheErr
                    slot[complete_tag][36] <= 1'b1; // data-side exception
                end
                ready[complete_tag] <= 1'b1;
            end else if (complete_valid && (count != 0) &&
                         (complete_tag == head)) begin
                // The response tag is architecturally owned by the FIFO
                // head.  During a same-edge allocation/retirement boundary
                // the array valid bit can still reflect the previous edge;
                // the non-empty head contract is sufficient to complete the
                // outstanding request without dropping its response.
                ready[head] <= 1'b1;
                if (complete_error) begin
                    slot[head][42] <= 1'b1;
                    slot[head][41:37] <= 5'h1E;
                    slot[head][36] <= 1'b1;
                end
            end
            // A cut-through commit never occupied a slot, so it must not
            // decrement occupancy.  Only a buffered head retirement removes
            // an entry; otherwise an empty FIFO underflows to all-ones and
            // permanently asserts backpressure.
            case ({alloc_fire, buffered_commit})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
