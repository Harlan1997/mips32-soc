// Bounded physical page-frame lease allocator for the opt-in MMU contract.
// This is an ownership primitive for a kernel-facing page-table layer, not a
// general heap or a replacement for an OS physical-memory manager.
module mmu_page_frame_allocator #(
    parameter integer SLOTS = 16,
    parameter [31:0] PAGE_BASE = 32'h0000_6000,
    parameter [31:0] PAGE_STRIDE = 32'h0000_1000
) (
    input wire clk,
    input wire rst_n,
    input wire alloc_req,
    output reg alloc_valid,
    output reg alloc_fail,
    output reg [31:0] alloc_page,
    output reg [7:0] alloc_generation,
    input wire release_req,
    input wire [31:0] release_page,
    input wire [7:0] release_generation,
    output reg release_valid,
    output reg release_reject
);
    reg [SLOTS-1:0] used;
    reg [7:0] generation [0:SLOTS-1];
    integer i;
    integer release_slot;
    reg found;
    reg release_match;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            used <= {SLOTS{1'b0}};
            alloc_valid <= 1'b0;
            alloc_fail <= 1'b0;
            alloc_page <= 32'd0;
            alloc_generation <= 8'd0;
            release_valid <= 1'b0;
            release_reject <= 1'b0;
            for (i = 0; i < SLOTS; i = i + 1)
                generation[i] <= 8'd0;
        end else begin
            alloc_valid <= 1'b0;
            alloc_fail <= 1'b0;
            release_valid <= 1'b0;
            release_reject <= 1'b0;

            release_slot = -1;
            release_match = 1'b0;
            if (release_req) begin
                for (i = 0; i < SLOTS; i = i + 1)
                    if (release_page == (PAGE_BASE + i * PAGE_STRIDE))
                        release_slot = i;
                if (release_slot >= 0 && used[release_slot] &&
                    generation[release_slot] === release_generation) begin
                    release_match = 1'b1;
                    used[release_slot] <= 1'b0;
                    generation[release_slot] <= generation[release_slot] + 1'b1;
                    release_valid <= 1'b1;
                end else begin
                    release_reject <= 1'b1;
                end
            end

            if (alloc_req) begin
                found = 1'b0;
                for (i = 0; i < SLOTS; i = i + 1) begin
                    // Permit atomic release+alloc of the same page. The
                    // generation returned to the new owner is incremented.
                    if ((!used[i] || (release_match && release_slot == i)) &&
                        !found) begin
                        used[i] <= 1'b1;
                        alloc_page <= PAGE_BASE + i * PAGE_STRIDE;
                        alloc_generation <= generation[i] +
                                            ((release_match && release_slot == i) ? 1'b1 : 1'b0);
                        alloc_valid <= 1'b1;
                        found = 1'b1;
                    end
                end
                if (!found)
                    alloc_fail <= 1'b1;
            end
        end
    end
endmodule
