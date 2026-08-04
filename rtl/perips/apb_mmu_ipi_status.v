// APB control/status wrapper for the dual-core TLB shootdown contract.
// Register offsets are relative to the APB window: 0x20..0x38.
module apb_mmu_ipi_status #(parameter TIMEOUT_CYCLES = 16) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [5:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    input  wire        target_present,
    input  wire        ack_valid,
    input  wire        ack_target,
    input  wire [7:0]  ack_generation,
    output wire        invalidate_valid,
    output wire        invalidate_target,
    output wire [7:0]  invalidate_generation,
    output wire [7:0]  invalidate_asid,
    output wire [19:0] invalidate_vpn,
    output wire [1:0]  invalidate_scope
);
    wire wr = psel & penable & pwrite;
    wire rd = psel & penable & ~pwrite;
    wire [3:0] word = paddr[5:2];
    reg target_r;
    reg [7:0] generation_r, asid_r;
    reg [19:0] vpn_r;
    reg [1:0] scope_r;
    reg [5:0] status_r;
    wire send_valid = wr && word == 4'd12 && pwdata[0];
    wire busy, pending, done_pulse, timeout_pulse, rejected_pulse, stale_pulse;

    mmu_ipi_shootdown #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_shootdown (
        .clk(clk), .rst_n(rst_n),
        .send_valid(send_valid), .send_target(target_r),
        .send_generation(generation_r), .send_asid(asid_r),
        .send_vpn(vpn_r), .send_scope(scope_r),
        .target_present(target_present), .ack_valid(ack_valid),
        .ack_target(ack_target), .ack_generation(ack_generation),
        .busy(busy), .pending(pending), .invalidate_valid(invalidate_valid),
        .invalidate_target(invalidate_target),
        .invalidate_generation(invalidate_generation),
        .invalidate_asid(invalidate_asid), .invalidate_vpn(invalidate_vpn),
        .invalidate_scope(invalidate_scope), .done(done_pulse),
        .timeout(timeout_pulse), .rejected(rejected_pulse),
        .stale_ack(stale_pulse)
    );

    assign pready = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_r <= 1'b0;
            generation_r <= 8'd0;
            asid_r <= 8'd0;
            vpn_r <= 20'd0;
            scope_r <= 2'd0;
            status_r <= 6'd0;
        end else begin
            if (wr && word == 4'd8) begin
                target_r <= pwdata[0];
                generation_r <= pwdata[15:8];
            end
            if (wr && word == 4'd9) asid_r <= pwdata[7:0];
            if (wr && word == 4'd10) vpn_r <= pwdata[19:0];
            if (wr && word == 4'd11) scope_r <= pwdata[1:0];
            if (done_pulse) status_r[2] <= 1'b1;
            if (timeout_pulse) status_r[3] <= 1'b1;
            if (rejected_pulse) status_r[4] <= 1'b1;
            if (stale_pulse) status_r[5] <= 1'b1;
            if (wr && word == 4'd14) status_r <= status_r & ~pwdata[5:0];
        end
    end

    always @(*) begin
        prdata = 32'd0;
        if (rd) case (word)
            4'd8:  prdata = {16'd0, generation_r, 7'd0, target_r};
            4'd9:  prdata = {24'd0, asid_r};
            4'd10: prdata = {12'd0, vpn_r};
            4'd11: prdata = {30'd0, scope_r};
            4'd13: begin
                prdata[0] = busy;
                prdata[1] = pending;
                prdata[2] = status_r[2];
                prdata[3] = status_r[3];
                prdata[4] = status_r[4];
                prdata[5] = status_r[5];
            end
            default: prdata = 32'd0;
        endcase
    end
endmodule
