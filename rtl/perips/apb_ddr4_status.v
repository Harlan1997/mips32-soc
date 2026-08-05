// Vendor-neutral DDR4 initialization/training status contract.
// This adapter is not a PHY/controller and is not in the default S3 path.
// APB offsets: VERSION, STATUS, ERROR, CONTROL(W1C).
module apb_ddr4_status #(
    parameter ENABLE_ERROR_INJECT = 1'b0
) (
    input wire clk, input wire rst_n,
    input wire controller_present, input wire init_done, input wire training_done,
    input wire fatal_error, input wire [15:0] error_code,
    input wire psel, input wire penable, input wire pwrite, input wire [4:0] paddr,
    input wire [31:0] pwdata, output reg [31:0] prdata,
    output wire pready, output wire pslverr
);
    localparam [31:0] VERSION = 32'h4444_5201;
    reg [31:0] error_r; reg error_seen_r; reg error_inject_r;
    wire wr = psel & penable & pwrite; wire rd = psel & penable & ~pwrite;
    wire error_active = (fatal_error && (error_code != 16'd0)) || error_inject_r;
    assign pready = 1'b1; assign pslverr = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_r <= 32'd0; error_seen_r <= 1'b0; error_inject_r <= 1'b0;
        end
        else begin
            if (ENABLE_ERROR_INJECT && wr && paddr[4:2] == 3'b011) begin
                if (pwdata[1]) error_inject_r <= 1'b1;
                if (pwdata[2]) error_inject_r <= 1'b0;
            end
            if (error_active && !error_seen_r)
                error_r <= error_inject_r ? 32'h0004_0004 : {16'h0004, error_code};
            error_seen_r <= error_active;
            if (wr && paddr[4:2] == 3'b011 && pwdata[0]) begin error_r <= 32'd0; error_seen_r <= error_active; end
        end
    end
    always @(*) begin
        prdata = 32'd0;
        if (rd) case (paddr[4:2])
            3'b000: prdata = VERSION;
            3'b001: prdata = {28'd0, fatal_error, training_done, init_done, controller_present};
            3'b010: prdata = error_r;
            default: prdata = 32'd0;
        endcase
    end
endmodule
