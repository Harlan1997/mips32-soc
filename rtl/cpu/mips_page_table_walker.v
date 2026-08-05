// Two-level 4KB page-table walker for the current CPU/MMU extension contract.
// PTE format: V[0], TABLE[1] for non-leaf entries, W[1], X[2], U[3] for leaf
// entries, PFN[31:12]. One read is outstanding at a time.
module mips_page_table_walker (
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
                        mem_addr <= {mem_rdata[31:12], 12'd0} + {20'd0, va_q[21:12], 2'd0};
                        mem_valid <= 1'b1; state <= ST_L2;
                    end
                end
                ST_L2: if (mem_valid && mem_ready) begin
                    mem_valid <= 1'b0;
                    if (mem_error) begin fault_valid <= 1'b1; fault_code <= FAULT_BUS; state <= ST_RESP; end
                    else if (!mem_rdata[0]) begin fault_valid <= 1'b1; fault_code <= FAULT_MISS; state <= ST_RESP; end
                    else if (!leaf_allowed(mem_rdata, access_q, user_q)) begin
                        fault_valid <= 1'b1;
                        fault_code <= FAULT_PERM;
                        state <= ST_RESP;
                    end else begin
                        leaf_pte <= mem_rdata;
                        pa <= {mem_rdata[31:12], va_q[11:0]};
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
