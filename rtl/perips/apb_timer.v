// =============================================================================
// File Name: apb_timer.v
// Design:    APB Timer Peripheral
// Author:    Antigravity
// =============================================================================

module apb_timer (
    input  wire        pclk,
    input  wire        presetn,
    
    // APB Slave Interface
    input  wire [31:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    
    // Interrupt output
    output wire        timer_int
);

    // Register Offsets
    localparam TMR_CTRL = 8'h00;
    localparam TMR_LOAD = 8'h04;
    localparam TMR_VAL  = 8'h08;
    localparam TMR_INT  = 8'h0C;
    
    // Registers
    reg [31:0] r_ctrl;
    reg [31:0] r_load;
    reg [31:0] r_val;
    reg [31:0] r_int;
    
    wire write_en = psel & penable & pwrite & pready;
    wire read_en  = psel & ~pwrite & pready;
    
    // APB writes
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_ctrl <= 32'd0;
            r_load <= 32'd0;
            r_int  <= 32'd0;
        end else begin
            if (write_en) begin
                case (paddr[7:0])
                    TMR_CTRL: r_ctrl <= pwdata;
                    TMR_LOAD: r_load <= pwdata;
                    TMR_INT:  begin
                        if (pwdata[0]) // Write 1 to clear
                            r_int[0] <= 1'b0;
                    end
                endcase
            end else if (r_ctrl[0] && r_val == 32'd0) begin
                // Generate interrupt if enabled
                if (r_ctrl[1])
                    r_int[0] <= 1'b1;
            end
        end
    end
    
    // Timer counter logic
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            r_val <= 32'd0;
        end else begin
            if (write_en && paddr[7:0] == TMR_VAL) begin
                // Explicit write to counter value
                r_val <= pwdata;
            end else if (write_en && paddr[7:0] == TMR_LOAD) begin
                // Writing load value also updates the current value (auto-reload on start)
                r_val <= pwdata;
            end else if (r_ctrl[0]) begin
                if (r_val == 32'd0)
                    r_val <= r_load;
                else
                    r_val <= r_val - 32'd1;
            end
        end
    end
    
    // APB reads
    reg [31:0] rdata_out;
    always @(*) begin
        case (paddr[7:0])
            TMR_CTRL: rdata_out = r_ctrl;
            TMR_LOAD: rdata_out = r_load;
            TMR_VAL:  rdata_out = r_val;
            TMR_INT:  rdata_out = r_int;
            default:  rdata_out = 32'd0;
        endcase
    end
    
    reg wait_state;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            wait_state <= 1'b0;
        else if (psel && penable && !wait_state)
            wait_state <= 1'b1;
        else
            wait_state <= 1'b0;
    end

    assign prdata = rdata_out;
    assign pready = wait_state;
    assign pslverr = 1'b0;
    
    assign timer_int = r_int[0];

endmodule
