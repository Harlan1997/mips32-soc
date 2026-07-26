// =============================================================================
// File Name: apb_wdt.v
// Design:    APB Watchdog Timer
// Author:    Antigravity — Phase D
// Description:
//   Simple software-fed watchdog. If not petted within TIMEOUT clocks after
//   arming, asserts wdt_reset (level, active-high) into the reset aggregator.
//   Pet by writing PETVAL to WDT_KICK register. Disable by clearing CTRL.EN.
//
// Register map (APB, byte offsets):
//   0x00 CTRL   : {30'd0, LOCK, EN}
//   0x04 LOAD   : 32-bit initial count value written on arm / pet
//   0x08 VAL    : current count value (RO)
//   0x0C KICK   : write PETVAL (=0x1ACCE551) to pet
//   0x10 STATUS : {31'd0, expired}   (W1C on expired)
// =============================================================================

module apb_wdt (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [4:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    output reg         wdt_reset
);

    localparam PETVAL = 32'h1ACC_E551;

    reg [31:0] load_r;
    reg [31:0] val_r;
    reg        ctrl_en;
    reg        ctrl_lock;
    reg        expired_r;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire   wr = psel & penable & pwrite;
    wire   rd = psel & penable & ~pwrite;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_r    <= 32'hFFFF_FFFF;
            val_r     <= 32'h0;
            ctrl_en   <= 1'b0;
            ctrl_lock <= 1'b0;
            expired_r <= 1'b0;
            wdt_reset <= 1'b0;
        end else begin
            wdt_reset <= expired_r;
            if (ctrl_en) begin
                if (val_r == 32'h0) begin
                    expired_r <= 1'b1;
                    ctrl_en   <= 1'b0;
                end else begin
                    val_r <= val_r - 1'b1;
                end
            end

            if (wr) begin
                case (paddr[4:2])
                    3'b000: if (!ctrl_lock) begin
                        ctrl_en   <= pwdata[0];
                        ctrl_lock <= pwdata[1];
                        if (pwdata[0]) val_r <= load_r; // arm loads count
                    end
                    3'b001: if (!ctrl_lock) load_r <= pwdata;
                    3'b011: if (pwdata == PETVAL) val_r <= load_r; // pet
                    3'b100: if (pwdata[0]) expired_r <= 1'b0;      // W1C
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        prdata = 32'h0;
        if (rd) begin
            case (paddr[4:2])
                3'b000: prdata = {30'h0, ctrl_lock, ctrl_en};
                3'b001: prdata = load_r;
                3'b010: prdata = val_r;
                3'b100: prdata = {31'h0, expired_r};
                default: prdata = 32'h0;
            endcase
        end
    end

endmodule
