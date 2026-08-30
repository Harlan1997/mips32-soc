// Two-level page-table walker for the current CPU/MMU extension contract.
// PTE format: V[0], TABLE[1] for non-leaf entries, W[1], X[2], U[3] for leaf
// entries, PFN[31:12]. One read is outstanding at a time.  PAGE_MASK changes
// the leaf-page offset and L2 index while retaining the existing 10-bit L1
// directory geometry.  This supports the contract page sizes 4 KiB, 16 KiB,
// 64 KiB, 256 KiB, 1 MiB, 4 MiB and 16 MiB without changing the interface.
module mips_page_table_walker #(
    parameter [15:0] PAGE_MASK = 16'h0000
) (
    input wire clk, input wire rst_n,
    input wire req_valid, output wire req_ready,
    input wire [31:0] ptbr, input wire [31:0] va,
    input wire [1:0] access, input wire user_mode,
    output reg mem_valid, output reg [31:0] mem_addr,
    input wire mem_ready, input wire [31:0] mem_rdata,
    input wire mem_error,
    output reg resp_valid, output reg [31:0] pa,
    output reg fault_valid, output reg [2:0] fault_code,
    output reg [31:0] leaf_pte
);
    localparam ST_IDLE = 2'd0, ST_L1 = 2'd1, ST_L2 = 2'd2, ST_RESP = 2'd3;
    localparam FAULT_MISS = 3'd1, FAULT_PERM = 3'd2, FAULT_BUS = 3'd3,
               FAULT_FORMAT = 3'd4;
    reg [1:0] state;
    reg [31:0] va_q, ptbr_q;
    reg [1:0] access_q;
    reg user_q;

    assign req_ready = (state == ST_IDLE);

    function automatic leaf_allowed;
        input [31:0] pte;
        input [1:0] a;
        input u;
        begin
            leaf_allowed = pte[0] && (!u || pte[3]) &&
                           ((a == 2'd0) ? pte[2] :
                            (a == 2'd1) ? (pte[1] || pte[2]) : pte[1]);
        end
    endfunction

    function automatic [31:0] l2_index_offset;
        input [31:0] v;
        begin
            case (PAGE_MASK)
                // Each leaf PTE is still one 32-bit word. Larger pages
                // reduce the number of L2 index bits; they do not change
                // the byte stride between adjacent PTEs.
                16'h0003: l2_index_offset = {22'd0, v[21:14], 2'd0};
                16'h000f: l2_index_offset = {26'd0, v[21:16], 2'd0};
                16'h003f: l2_index_offset = {30'd0, v[21:18], 2'd0};
                16'h00ff: l2_index_offset = {30'd0, v[21:20], 2'd0};
                16'h03ff,
                16'h0fff: l2_index_offset = 32'd0;
                default:  l2_index_offset = {20'd0, v[21:12], 2'd0};
            endcase
        end
    endfunction

    function automatic leaf_format_valid;
        input [31:0] pte;
        begin
            // A larger leaf must be aligned to its own page size.  Invalid
            // low PFN bits are rejected instead of silently aliasing pages.
            case (PAGE_MASK)
                16'h0003: leaf_format_valid = (pte[13:12] == 2'b00);
                16'h000f: leaf_format_valid = (pte[15:12] == 4'b0000);
                16'h003f: leaf_format_valid = (pte[17:12] == 6'b000000);
                16'h00ff: leaf_format_valid = (pte[19:12] == 8'b00000000);
                16'h03ff: leaf_format_valid = (pte[21:12] == 10'b0000000000);
                16'h0fff: leaf_format_valid = (pte[23:12] == 12'b000000000000);
                default:  leaf_format_valid = 1'b1;
            endcase
        end
    endfunction

    function automatic [31:0] leaf_pa;
        input [31:0] pte;
        input [31:0] v;
        begin
            case (PAGE_MASK)
                16'h0003: leaf_pa = {pte[31:14], v[13:0]};
                16'h000f: leaf_pa = {pte[31:16], v[15:0]};
                16'h003f: leaf_pa = {pte[31:18], v[17:0]};
                16'h00ff: leaf_pa = {pte[31:20], v[19:0]};
                16'h03ff: leaf_pa = {pte[31:22], v[21:0]};
                16'h0fff: leaf_pa = {pte[31:24], v[23:0]};
                default:  leaf_pa = {pte[31:12], v[11:0]};
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE; mem_valid <= 1'b0; resp_valid <= 1'b0;
            fault_valid <= 1'b0; fault_code <= 3'd0; pa <= 32'd0; leaf_pte <= 32'd0; mem_addr <= 32'd0;
            va_q <= 0; ptbr_q <= 0; access_q <= 0; user_q <= 0;
        end else begin
            resp_valid <= 1'b0;
            case (state)
                ST_IDLE: if (req_valid) begin
                    fault_valid <= 1'b0;
                    va_q <= va; ptbr_q <= {ptbr[31:12], 12'd0};
                    access_q <= access; user_q <= user_mode;
                    mem_addr <= {ptbr[31:12], 12'd0} + {20'd0, va[31:22], 2'd0};
                    mem_valid <= 1'b1; state <= ST_L1;
                end
                ST_L1: if (mem_valid && mem_ready) begin
                    mem_valid <= 1'b0;
                    if (mem_error) begin fault_valid <= 1'b1; fault_code <= FAULT_BUS; state <= ST_RESP; end
                    else if (!mem_rdata[0]) begin fault_valid <= 1'b1; fault_code <= FAULT_MISS; state <= ST_RESP; end
                    else if (!mem_rdata[1]) begin fault_valid <= 1'b1; fault_code <= FAULT_FORMAT; state <= ST_RESP; end
                    else begin
                        mem_addr <= {mem_rdata[31:12], 12'd0} + l2_index_offset(va_q);
                        mem_valid <= 1'b1; state <= ST_L2;
                    end
                end
                ST_L2: if (mem_valid && mem_ready) begin
                    mem_valid <= 1'b0;
                    if (mem_error) begin fault_valid <= 1'b1; fault_code <= FAULT_BUS; state <= ST_RESP; end
                    else if (!mem_rdata[0]) begin fault_valid <= 1'b1; fault_code <= FAULT_MISS; state <= ST_RESP; end
                    else if (!leaf_format_valid(mem_rdata) ||
                             !leaf_allowed(mem_rdata, access_q, user_q)) begin
                        fault_valid <= 1'b1;
                        fault_code <= FAULT_PERM;
                        state <= ST_RESP;
                    end else begin
                        leaf_pte <= mem_rdata;
                        pa <= leaf_pa(mem_rdata, va_q);
                        state <= ST_RESP;
                    end
                end
                ST_RESP: begin
                    resp_valid <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
