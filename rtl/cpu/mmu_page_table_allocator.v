// Bounded page-table root lease allocator for the current MMU contract.
// This is a deterministic hardware-facing ownership model, not a heap or OS.
module mmu_page_table_allocator #(
    parameter integer SLOTS = 4,
    parameter [31:0] ROOT_BASE = 32'h0010_0000,
    parameter [31:0] ROOT_STRIDE = 32'h0000_1000
) (
    input wire clk,
    input wire rst_n,
    input wire alloc_req,
    output reg alloc_valid,
    output reg alloc_fail,
    output reg [31:0] alloc_root,
    output reg [7:0] alloc_generation,
    input wire release_req,
    input wire [31:0] release_root,
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
            alloc_root <= 32'd0;
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
                    if (release_root == (ROOT_BASE + i * ROOT_STRIDE))
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
                    // Permit an atomic release+alloc of the same slot.  The
                    // returned token is the incremented generation, so an
                    // old owner cannot retain access after the handoff.
                    if ((!used[i] || (release_match && release_slot == i)) &&
                        !found) begin
                        used[i] <= 1'b1;
                        alloc_root <= ROOT_BASE + i * ROOT_STRIDE;
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
