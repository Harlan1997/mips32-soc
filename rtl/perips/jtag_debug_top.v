// =============================================================================
// File Name: jtag_debug_top.v
// Design:    JTAG TAP Controller & AXI4 Debug Master
// Author:    Antigravity
// Description:
//   A standard JTAG TAP state machine compliant with IEEE 1149.1.
//   Includes a basic Debug Module that translates custom JTAG instructions
//   into AXI4 Master transactions to inspect and modify SoC memory/peripherals.
// =============================================================================

module jtag_debug_top (
    // SoC System Clock and Reset
    input  wire        clk,
    input  wire        rst_n,

    // JTAG Pins
    input  wire        tck,
    input  wire        trst_n,
    input  wire        tms,
    input  wire        tdi,
    output reg         tdo,

    // AXI4 Master Interface
    output wire [3:0]  m_awid,
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire [2:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire [1:0]  m_awlock,
    output wire [3:0]  m_awcache,
    output wire [2:0]  m_awprot,
    output wire        m_awvalid,
    input  wire        m_awready,
    
    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,
    
    input  wire [3:0]  m_bid,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,

    output wire [3:0]  m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire [1:0]  m_arlock,
    output wire [3:0]  m_arcache,
    output wire [2:0]  m_arprot,
    output wire        m_arvalid,
    input  wire        m_arready,
    
    input  wire [3:0]  m_rid,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready
);

    // =========================================================================
    // JTAG TAP State Machine (16 States)
    // =========================================================================
    localparam TEST_LOGIC_RESET = 4'h0;
    localparam RUN_TEST_IDLE    = 4'h1;
    localparam SELECT_DR_SCAN   = 4'h2;
    localparam CAPTURE_DR       = 4'h3;
    localparam SHIFT_DR         = 4'h4;
    localparam EXIT1_DR         = 4'h5;
    localparam PAUSE_DR         = 4'h6;
    localparam EXIT2_DR         = 4'h7;
    localparam UPDATE_DR        = 4'h8;
    localparam SELECT_IR_SCAN   = 4'h9;
    localparam CAPTURE_IR       = 4'hA;
    localparam SHIFT_IR         = 4'hB;
    localparam EXIT1_IR         = 4'hC;
    localparam PAUSE_IR         = 4'hD;
    localparam EXIT2_IR         = 4'hE;
    localparam UPDATE_IR        = 4'hF;

    reg [3:0] tap_state, next_tap_state;
    
    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            // VCS coverage off
            tap_state <= TEST_LOGIC_RESET;
            // VCS coverage on
        end
        else         tap_state <= next_tap_state;
    end

    always @(*) begin
        case (tap_state)
            TEST_LOGIC_RESET: next_tap_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    next_tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   next_tap_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       next_tap_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         next_tap_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         next_tap_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         next_tap_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         next_tap_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        next_tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   next_tap_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       next_tap_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         next_tap_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         next_tap_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         next_tap_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         next_tap_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        next_tap_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            // VCS coverage off
            default:          next_tap_state = TEST_LOGIC_RESET;
            // VCS coverage on
        endcase
    end

    // Instruction Register (4 bits)
    reg [3:0] ir_reg;
    reg [3:0] ir_shift;
    
    localparam IR_IDCODE = 4'h1;
    localparam IR_AXI_CMD = 4'h8;
    localparam IR_AXI_DAT = 4'h9;
    localparam IR_BYPASS = 4'hF;

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_reg <= IR_IDCODE;
            ir_shift <= 4'h0;
        end else begin
            if (tap_state == TEST_LOGIC_RESET) begin
                ir_reg <= IR_IDCODE;
            end else if (tap_state == CAPTURE_IR) begin
                ir_shift <= 4'b0101; // JTAG spec requires 01 on LSBs
            end else if (tap_state == SHIFT_IR) begin
                ir_shift <= {tdi, ir_shift[3:1]};
            end else if (tap_state == UPDATE_IR) begin
                ir_reg <= ir_shift;
            end
        end
    end

    // Data Registers
    reg [31:0] idcode_reg = 32'h1000_A001; // Dummy IDCODE
    reg [31:0] bypass_reg;
    
    // Custom AXI Debug Registers (in TCK domain)
    // CMD format: [31] Write/Read, [30:0] Address
    reg [64:0] axi_cmd_shift; // 65-bit shift (1-bit Write, 32-bit Addr, 32-bit Data)
    reg [31:0] axi_addr;
    reg [31:0] axi_wdata;
    reg        axi_do_write;
    reg        axi_do_read;
    
    wire [31:0] axi_rdata_sync; // From AXI domain
    wire        axi_rvalid_sync;

    always @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            axi_cmd_shift <= 65'd0;
            axi_do_write  <= 1'b0;
            axi_do_read   <= 1'b0;
        end else begin
            axi_do_write <= 1'b0;
            axi_do_read  <= 1'b0;
            
            if (tap_state == CAPTURE_DR) begin
                if (ir_reg == IR_IDCODE)
                    axi_cmd_shift[31:0] <= idcode_reg;
                else if (ir_reg == IR_AXI_CMD)
                    axi_cmd_shift <= {1'b0, axi_addr, axi_rdata_sync};
            end else if (tap_state == SHIFT_DR) begin
                if (ir_reg == IR_IDCODE)
                    axi_cmd_shift[31:0] <= {tdi, axi_cmd_shift[31:1]};
                else if (ir_reg == IR_AXI_CMD)
                    axi_cmd_shift <= {tdi, axi_cmd_shift[64:1]};
            end else if (tap_state == UPDATE_DR) begin
                if (ir_reg == IR_AXI_CMD) begin
                    axi_addr <= axi_cmd_shift[63:32];
                    axi_wdata <= axi_cmd_shift[31:0];
                    if (axi_cmd_shift[64]) axi_do_write <= 1'b1;
                    else                   axi_do_read  <= 1'b1;
                end
            end
        end
    end

    // TDO Output (falling edge)
    always @(negedge tck or negedge trst_n) begin
        if (!trst_n) tdo <= 1'b0;
        else begin
            if (tap_state == SHIFT_IR)
                tdo <= ir_shift[0];
            else if (tap_state == SHIFT_DR) begin
                if (ir_reg == IR_IDCODE)
                    tdo <= axi_cmd_shift[0];
                else if (ir_reg == IR_AXI_CMD)
                    tdo <= axi_cmd_shift[0];
                else
                    tdo <= bypass_reg[0];
            end else
                tdo <= 1'b0;
        end
    end

    // =========================================================================
    // Clock Domain Crossing (TCK -> System Clock)
    // =========================================================================
    // Very simple CDC for demonstration (real JTAG needs proper async FIFOs)
    reg [2:0] write_req_sync;
    reg [2:0] read_req_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_req_sync <= 3'd0;
            read_req_sync  <= 3'd0;
        end else begin
            write_req_sync <= {write_req_sync[1:0], axi_do_write};
            read_req_sync  <= {read_req_sync[1:0], axi_do_read};
        end
    end
    
    wire start_axi_write = (write_req_sync[2:1] == 2'b01);
    wire start_axi_read  = (read_req_sync[2:1] == 2'b01);

    // =========================================================================
    // AXI4 Master State Machine (System Clock Domain)
    // =========================================================================
    localparam ST_IDLE = 3'd0;
    localparam ST_AW   = 3'd1;
    localparam ST_W    = 3'd2;
    localparam ST_B    = 3'd3;
    localparam ST_AR   = 3'd4;
    localparam ST_R    = 3'd5;
    
    reg [2:0] axi_state, next_axi_state;
    reg [31:0] captured_rdata;
    reg [31:0] axi_addr_q;
    reg [31:0] axi_wdata_q;

    // The command registers are written in the TCK domain. Capture each
    // request payload as the system-clock FSM accepts its start indication so
    // a following JTAG UPDATE_DR cannot alter an in-flight AXI transaction.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_addr_q  <= 32'd0;
            axi_wdata_q <= 32'd0;
        end else if (axi_state == ST_IDLE &&
                     (start_axi_write || start_axi_read)) begin
            axi_addr_q  <= axi_addr;
            axi_wdata_q <= axi_wdata;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // VCS coverage off
            axi_state <= ST_IDLE;
            // VCS coverage on
        end
        else        axi_state <= next_axi_state;
    end
    
    always @(*) begin
        next_axi_state = axi_state;
        case (axi_state)
            ST_IDLE: begin
                if (start_axi_write) next_axi_state = ST_AW;
                else if (start_axi_read) next_axi_state = ST_AR;
            end
            ST_AW: if (m_awvalid && m_awready) next_axi_state = ST_W;
            ST_W:  if (m_wvalid && m_wready)   next_axi_state = ST_B;
            ST_B:  if (m_bvalid && m_bready)   next_axi_state = ST_IDLE;
            ST_AR: if (m_arvalid && m_arready) next_axi_state = ST_R;
            ST_R:  if (m_rvalid && m_rready)   next_axi_state = ST_IDLE;
            // VCS coverage off
            default: next_axi_state = ST_IDLE;
            // VCS coverage on
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) captured_rdata <= 32'd0;
        else if (axi_state == ST_R && m_rvalid && m_rready) captured_rdata <= m_rdata;
    end
    
    assign axi_rdata_sync = captured_rdata;

    // AXI Master Assignments
    assign m_awid    = 4'd3;
    assign m_awaddr  = axi_addr_q;
    assign m_awlen   = 8'd0;
    assign m_awsize  = 3'b010;
    assign m_awburst = 2'b01;
    assign m_awlock  = 2'd0;
    assign m_awcache = 4'd0;
    assign m_awprot  = 3'd0;
    assign m_awvalid = (axi_state == ST_AW);
    
    assign m_wdata   = axi_wdata_q;
    assign m_wstrb   = 4'hF;
    assign m_wlast   = 1'b1;
    assign m_wvalid  = (axi_state == ST_W);
    assign m_bready  = (axi_state == ST_B);
    
    assign m_arid    = 4'd3;
    assign m_araddr  = axi_addr_q;
    assign m_arlen   = 8'd0;
    assign m_arsize  = 3'b010;
    assign m_arburst = 2'b01;
    assign m_arlock  = 2'd0;
    assign m_arcache = 4'd0;
    assign m_arprot  = 3'd0;
    assign m_arvalid = (axi_state == ST_AR);
    assign m_rready  = (axi_state == ST_R);

endmodule
