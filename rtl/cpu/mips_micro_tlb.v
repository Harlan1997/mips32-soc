// Small fully-associative translation caches used in the opt-in MMU path.
// The main TLB remains authoritative: a miss here is filled only from a
// successful main-TLB lookup, and any architectural TLB update invalidates
// both caches before the next lookup.
`include "soc_config.vh"

module mips_micro_tlb #(
    parameter ENTRIES = 4,
    parameter INDEX_BITS = 2
) (
    input wire clk,
    input wire rst_n,
    input wire flush,

    input wire [31:0] i_va,
    input wire [7:0] i_asid,
    input wire i_main_hit,
    input wire i_main_multi_hit,
    input wire [15:0] i_main_mask,
    input wire [18:0] i_main_vpn2,
    input wire i_main_g,
    input wire [31:0] i_main_lo0,
    input wire [31:0] i_main_lo1,

    input wire [31:0] d_va,
    input wire [7:0] d_asid,
    input wire d_main_hit,
    input wire d_main_multi_hit,
    input wire [15:0] d_main_mask,
    input wire [18:0] d_main_vpn2,
    input wire d_main_g,
    input wire [31:0] d_main_lo0,
    input wire [31:0] d_main_lo1,

    output wire i_hit,
    output wire i_multi_hit,
    output wire i_v,
    output wire i_d,
    output wire [2:0] i_c,
    output wire [19:0] i_pfn,
    output wire d_hit,
    output wire d_multi_hit,
    output wire d_v,
    output wire d_d,
    output wire [2:0] d_c,
    output wire [19:0] d_pfn
);
    reg valid_i [0:ENTRIES-1];
    reg valid_d [0:ENTRIES-1];
    reg [18:0] vpn_i [0:ENTRIES-1];
    reg [18:0] vpn_d [0:ENTRIES-1];
    reg [7:0] asid_i [0:ENTRIES-1];
    reg [7:0] asid_d [0:ENTRIES-1];
    reg [15:0] mask_i [0:ENTRIES-1];
    reg [15:0] mask_d [0:ENTRIES-1];
    reg global_i [0:ENTRIES-1];
    reg global_d [0:ENTRIES-1];
    reg [31:0] lo0_i [0:ENTRIES-1];
    reg [31:0] lo1_i [0:ENTRIES-1];
    reg [31:0] lo0_d [0:ENTRIES-1];
    reg [31:0] lo1_d [0:ENTRIES-1];
    reg [INDEX_BITS-1:0] next_i, next_d;

    function [5:0] odd_bit;
        input [15:0] mask;
        begin
            case (mask)
                16'h0003: odd_bit = 6'd14;
                16'h000f: odd_bit = 6'd16;
                16'h003f: odd_bit = 6'd18;
                16'h00ff: odd_bit = 6'd20;
                16'h03ff: odd_bit = 6'd22;
                16'h0fff: odd_bit = 6'd24;
                16'h3fff: odd_bit = 6'd26;
                default:  odd_bit = 6'd12;
            endcase
        end
    endfunction

    function [19:0] adjusted_pfn;
        input [19:0] pfn;
        input [31:0] va;
        input [15:0] mask;
        begin
            case (mask)
                16'h0003: adjusted_pfn = {pfn[19:2], va[13:12]};
                16'h000f: adjusted_pfn = {pfn[19:4], va[15:12]};
                16'h003f: adjusted_pfn = {pfn[19:6], va[17:12]};
                16'h00ff: adjusted_pfn = {pfn[19:8], va[19:12]};
                16'h03ff: adjusted_pfn = {pfn[19:10], va[21:12]};
                16'h0fff: adjusted_pfn = {pfn[19:12], va[23:12]};
                16'h3fff: adjusted_pfn = {pfn[19:14], va[25:12]};
                default:  adjusted_pfn = pfn;
            endcase
        end
    endfunction

    wire [ENTRIES-1:0] i_matches;
    wire [ENTRIES-1:0] d_matches;
    genvar g;
    generate for (g = 0; g < ENTRIES; g = g + 1) begin : g_match
        assign i_matches[g] = valid_i[g] &&
            (((vpn_i[g] ^ i_va[31:13]) & {3'b111, ~mask_i[g]}) == 19'b0) &&
            (global_i[g] || (asid_i[g] == i_asid));
        assign d_matches[g] = valid_d[g] &&
            (((vpn_d[g] ^ d_va[31:13]) & {3'b111, ~mask_d[g]}) == 19'b0) &&
            (global_d[g] || (asid_d[g] == d_asid));
    end endgenerate

    reg i_found, d_found, i_many, d_many;
    reg [INDEX_BITS-1:0] i_index, d_index;
    integer n;
    always @(*) begin
        i_found = 1'b0; i_many = 1'b0; i_index = 0;
        d_found = 1'b0; d_many = 1'b0; d_index = 0;
        for (n = ENTRIES-1; n >= 0; n = n-1) begin
            if (i_matches[n]) begin i_many = i_many | i_found; i_found = 1'b1; i_index = n; end
            if (d_matches[n]) begin d_many = d_many | d_found; d_found = 1'b1; d_index = n; end
        end
    end

    wire [15:0] i_mask_sel = mask_i[i_index];
    wire [15:0] d_mask_sel = mask_d[d_index];
    wire [31:0] i_lo = i_va[odd_bit(i_mask_sel)] ? lo1_i[i_index] : lo0_i[i_index];
    wire [31:0] d_lo = d_va[odd_bit(d_mask_sel)] ? lo1_d[d_index] : lo0_d[d_index];
    assign i_hit = i_found;
    assign i_multi_hit = i_many;
    assign i_v = i_lo[1]; assign i_d = i_lo[2]; assign i_c = i_lo[5:3];
    assign i_pfn = adjusted_pfn(i_lo[25:6], i_va, i_mask_sel);
    assign d_hit = d_found;
    assign d_multi_hit = d_many;
    assign d_v = d_lo[1]; assign d_d = d_lo[2]; assign d_c = d_lo[5:3];
    assign d_pfn = adjusted_pfn(d_lo[25:6], d_va, d_mask_sel);

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_i <= 0; next_d <= 0;
            for (k = 0; k < ENTRIES; k = k + 1) begin
                valid_i[k] <= 1'b0;
                valid_d[k] <= 1'b0;
            end
        end else if (flush) begin
            next_i <= 0; next_d <= 0;
            for (k = 0; k < ENTRIES; k = k + 1) begin
                valid_i[k] <= 1'b0;
                valid_d[k] <= 1'b0;
            end
        end else begin
            if (i_main_hit && !i_main_multi_hit && !i_found) begin
                valid_i[next_i] <= 1'b1; vpn_i[next_i] <= i_main_vpn2;
                asid_i[next_i] <= i_asid; mask_i[next_i] <= i_main_mask;
                global_i[next_i] <= i_main_g; lo0_i[next_i] <= i_main_lo0; lo1_i[next_i] <= i_main_lo1;
                next_i <= next_i + 1'b1;
            end
            if (d_main_hit && !d_main_multi_hit && !d_found) begin
                valid_d[next_d] <= 1'b1; vpn_d[next_d] <= d_main_vpn2;
                asid_d[next_d] <= d_asid; mask_d[next_d] <= d_main_mask;
                global_d[next_d] <= d_main_g; lo0_d[next_d] <= d_main_lo0; lo1_d[next_d] <= d_main_lo1;
                next_d <= next_d + 1'b1;
            end
        end
    end
endmodule
