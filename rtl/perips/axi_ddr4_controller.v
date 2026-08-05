// Protocol-level DDR4 controller for the vendor-neutral RTL contract.
//
// This block owns the AXI slave contract and models the controller command
// sequencing needed before a vendor DFI/PHY adapter is selected.  The backing
// array is simulation storage; it is deliberately not presented as a DRAM or
// PHY model.  The command states make timing/ordering visible to protocol
// tests and keep all AXI responses bounded.
`include "soc_config.vh"

module axi_ddr4_controller #(
    parameter integer MEM_DEPTH_WORDS = 4194304,
    parameter integer INIT_CYCLES = 4,
    parameter integer REFRESH_INTERVAL_CYCLES = 64,
    parameter integer REFRESH_CYCLES = 4,
    parameter integer COMMAND_LATENCY = 1,
    parameter integer INJECT_INIT_FAIL = 1'b0,
    parameter integer INJECT_FATAL = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output reg  [3:0]  s_bid,
    output reg  [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,

    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire        s_arvalid,
    output wire        s_arready,
    output reg  [3:0]  s_rid,
    output reg  [31:0] s_rdata,
    output reg  [1:0]  s_rresp,
    output reg         s_rlast,
    output reg         s_rvalid,
    input  wire        s_rready,

    input  wire        refresh_req,
    output wire        controller_present,
    output wire        init_done,
    output wire        training_done,
    output wire        refresh_busy,
    output wire        fatal_error,
    output wire [15:0] error_code,
    output reg         phy_cmd_valid,
    output reg  [3:0]  phy_cmd,
    output reg  [31:0] phy_addr,
    output reg  [31:0] phy_wdata,
    output reg  [3:0]  phy_wstrb,
    output reg         last_row_hit,
    output reg         last_row_miss
);

    localparam [3:0] CMD_NOP = 4'h0;
    localparam [3:0] CMD_ACT = 4'h1;
    localparam [3:0] CMD_READ = 4'h2;
    localparam [3:0] CMD_WRITE = 4'h3;
    localparam [3:0] CMD_PRE = 4'h4;
    localparam [3:0] CMD_REFRESH = 4'h5;

    localparam [3:0] ERR_INIT_FAIL = 4'h1;
    localparam [3:0] ERR_BAD_AXI = 4'h2;
    localparam [3:0] ERR_FATAL = 4'h4;
    localparam [3:0] ERR_WLAST = 4'h5;

    localparam [3:0] ST_INIT = 4'd0;
    localparam [3:0] ST_READY = 4'd1;
    localparam [3:0] ST_ACT = 4'd2;
    localparam [3:0] ST_READ_CMD = 4'd3;
    localparam [3:0] ST_READ_DATA = 4'd4;
    localparam [3:0] ST_WRITE_CMD = 4'd5;
    localparam [3:0] ST_WRITE_DATA = 4'd6;
    localparam [3:0] ST_PRE = 4'd7;
    localparam [3:0] ST_REFRESH = 4'd8;
    localparam [3:0] ST_FATAL = 4'd9;

    reg [3:0] state;
    reg [31:0] timer;
    reg [31:0] refresh_timer;
    reg [31:0] ram [0:MEM_DEPTH_WORDS-1];
    integer i;

    reg        write_active;
    reg [3:0]  write_id;
    reg [31:0] write_addr;
    reg [7:0]  write_left;
    reg [7:0]  write_len;
    reg        write_bad;

    reg        read_active;
    reg [3:0]  read_id;
    reg [31:0] read_addr;
    reg [7:0]  read_left;
    reg        read_bad;

    reg [31:0] command_addr;
    reg [31:0] pending_data;
    reg [3:0]  pending_strb;
    reg [3:0]  pending_cmd;
    reg [2:0]  active_bank;
    reg [15:0] active_row;
    reg        bank_open;
    reg [15:0] error_code_r;

    function integer word_index;
        input [31:0] addr;
        begin
            word_index = ((addr - `SOC_DDR_BASE) >> 2) % MEM_DEPTH_WORDS;
        end
    endfunction

    function valid_burst;
        input [31:0] addr;
        input [7:0] len;
        input [2:0] size;
        input [1:0] burst;
        reg [32:0] last_addr;
        begin
            last_addr = {1'b0, addr} + ({25'd0, len} << size);
            valid_burst = (addr[1:0] == 2'b00) &&
                          (size == 3'd2) && (burst == 2'b01) &&
                          (len <= 8'd15) &&
                          (addr >= `SOC_DDR_BASE) &&
                          (last_addr[31:0] < (`SOC_DDR_BASE + `SOC_DDR_SIZE)) &&
                          (last_addr[31:12] == addr[31:12]);
        end
    endfunction

    wire controller_ready = (state == ST_READY) && !write_active &&
                             !read_active && !s_bvalid && !s_rvalid;
    assign controller_present = 1'b1;
    assign init_done = (state != ST_INIT) && (state != ST_FATAL);
    assign training_done = init_done;
    assign refresh_busy = (state == ST_REFRESH);
    assign fatal_error = (state == ST_FATAL);
    assign error_code = error_code_r;
    assign s_awready = controller_ready && !refresh_req;
    assign s_arready = controller_ready && !refresh_req && !s_awvalid;
    assign s_wready = (state == ST_WRITE_DATA) && write_active;

    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1)
            ram[i] = 32'd0;
    end

    // Simulation-only firmware preload hook retained under the new instance
    // name so existing SoC boot tests can load a DDR image explicitly.
    // synopsys translate_off
    reg [1023:0] image_hex;
    task load_hex;
        input [1023:0] hex_path;
        begin $readmemh(hex_path, ram); end
    endtask
    initial begin
        image_hex = "";
        if ($value$plusargs("DDR_HEX=%s", image_hex)) load_hex(image_hex);
    end
    // synopsys translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_INIT;
            timer <= (INIT_CYCLES < 1) ? 1 : INIT_CYCLES;
            refresh_timer <= 0;
            write_active <= 1'b0;
            read_active <= 1'b0;
            s_bvalid <= 1'b0;
            s_rvalid <= 1'b0;
            s_rlast <= 1'b0;
            s_bresp <= 2'b00;
            s_rresp <= 2'b00;
            s_bid <= 0;
            s_rid <= 0;
            s_rdata <= 0;
            error_code_r <= 0;
            active_bank <= 0;
            active_row <= 0;
            bank_open <= 1'b0;
            phy_cmd_valid <= 1'b0;
            phy_cmd <= CMD_NOP;
            phy_addr <= 0;
            phy_wdata <= 0;
            phy_wstrb <= 0;
            last_row_hit <= 1'b0;
            last_row_miss <= 1'b0;
        end else begin
            phy_cmd_valid <= 1'b0;
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
            if (s_rvalid && s_rready) begin
                if (read_left == 0) begin
                    s_rvalid <= 1'b0;
                    s_rlast <= 1'b0;
                    read_active <= 1'b0;
                    state <= ST_READY;
                end else begin
                    read_left <= read_left - 1'b1;
                    read_addr <= read_addr + 32'd4;
                    s_rdata <= read_bad ? 32'd0 : ram[word_index(read_addr + 32'd4)];
                    s_rlast <= (read_left == 1);
                end
            end

            if (INJECT_FATAL && state != ST_FATAL) begin
                state <= ST_FATAL;
                error_code_r <= {12'd0, ERR_FATAL};
                write_active <= 1'b0;
                read_active <= 1'b0;
                s_bvalid <= 1'b0;
                s_rvalid <= 1'b0;
            end else begin
                case (state)
                    ST_INIT: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else if (INJECT_INIT_FAIL) begin
                            state <= ST_FATAL;
                            error_code_r <= {12'd0, ERR_INIT_FAIL};
                        end else begin
                            state <= ST_READY;
                            refresh_timer <= 0;
                        end
                    end
                    ST_READY: begin
                        if (refresh_req || ((REFRESH_INTERVAL_CYCLES > 0) &&
                            refresh_timer >= REFRESH_INTERVAL_CYCLES-1 && controller_ready)) begin
                            state <= ST_REFRESH;
                            timer <= (REFRESH_CYCLES < 1) ? 1 : REFRESH_CYCLES;
                            refresh_timer <= 0;
                        end else if (controller_ready) begin
                            refresh_timer <= refresh_timer + 1'b1;
                            if (s_awvalid && s_awready) begin
                                write_active <= 1'b1;
                                write_id <= s_awid;
                                write_addr <= s_awaddr;
                                write_len <= s_awlen;
                                write_left <= s_awlen;
                                write_bad <= !valid_burst(s_awaddr, s_awlen, s_awsize, s_awburst);
                                command_addr <= s_awaddr;
                                pending_cmd <= CMD_WRITE;
                                timer <= COMMAND_LATENCY;
                                last_row_hit <= bank_open &&
                                    (active_bank == s_awaddr[10:8]) &&
                                    (active_row == s_awaddr[27:12]);
                                last_row_miss <= !bank_open ||
                                    (active_bank != s_awaddr[10:8]) ||
                                    (active_row != s_awaddr[27:12]);
                                if (bank_open && (active_bank == s_awaddr[10:8]) &&
                                    (active_row == s_awaddr[27:12]))
                                    state <= ST_WRITE_CMD;
                                else if (bank_open)
                                    state <= ST_PRE;
                                else
                                    state <= ST_ACT;
                            end else if (s_arvalid && s_arready) begin
                                read_active <= 1'b1;
                                read_id <= s_arid;
                                read_addr <= s_araddr;
                                read_left <= s_arlen;
                                read_bad <= !valid_burst(s_araddr, s_arlen, s_arsize, s_arburst);
                                command_addr <= s_araddr;
                                pending_cmd <= CMD_READ;
                                last_row_hit <= bank_open &&
                                    (active_bank == s_araddr[10:8]) &&
                                    (active_row == s_araddr[27:12]);
                                last_row_miss <= !bank_open ||
                                    (active_bank != s_araddr[10:8]) ||
                                    (active_row != s_araddr[27:12]);
                                if (bank_open && (active_bank == s_araddr[10:8]) &&
                                    (active_row == s_araddr[27:12]))
                                    state <= ST_READ_CMD;
                                else if (bank_open)
                                    state <= ST_PRE;
                                else
                                    state <= ST_ACT;
                            end
                        end
                    end
                    ST_ACT: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else begin
                            // Contract-level open-row tracking. The address
                            // slicing is vendor-neutral until the selected
                            // PHY/DRAM geometry supplies the final mapping.
                            active_bank <= command_addr[10:8];
                            active_row <= command_addr[27:12];
                            bank_open <= 1'b1;
                            phy_cmd_valid <= 1'b1;
                            phy_cmd <= CMD_ACT;
                            phy_addr <= command_addr;
                            timer <= COMMAND_LATENCY;
                            state <= (pending_cmd == CMD_READ) ? ST_READ_CMD : ST_WRITE_CMD;
                        end
                    end
                    ST_READ_CMD: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else begin
                            phy_cmd_valid <= 1'b1;
                            phy_cmd <= CMD_READ;
                            phy_addr <= read_addr;
                            s_rid <= read_id;
                            s_rresp <= read_bad ? 2'b11 : 2'b00;
                            s_rdata <= read_bad ? 32'd0 : ram[word_index(read_addr)];
                            s_rlast <= (read_left == 0);
                            s_rvalid <= 1'b1;
                            state <= ST_READ_DATA;
                        end
                    end
                    ST_READ_DATA: begin
                        // R channel progress is handled above; hold response
                        // stable while the master applies backpressure.
                    end
                    ST_WRITE_DATA: begin
                        if (s_wvalid && s_wready) begin
                            if (!write_bad && (s_wlast == (write_left == 0))) begin
                                if (s_wstrb[0]) ram[word_index(write_addr)][7:0] <= s_wdata[7:0];
                                if (s_wstrb[1]) ram[word_index(write_addr)][15:8] <= s_wdata[15:8];
                                if (s_wstrb[2]) ram[word_index(write_addr)][23:16] <= s_wdata[23:16];
                                if (s_wstrb[3]) ram[word_index(write_addr)][31:24] <= s_wdata[31:24];
                            end
                            if (s_wlast || write_left == 0) begin
                                if (!write_bad && (s_wlast != (write_left == 0)))
                                    error_code_r <= {12'd0, ERR_WLAST};
                                s_bid <= write_id;
                                s_bresp <= write_bad ? 2'b11 :
                                           ((s_wlast == (write_left == 0)) ? 2'b00 : 2'b10);
                                s_bvalid <= 1'b1;
                                write_active <= 1'b0;
                                state <= ST_READY;
                            end else begin
                                write_left <= write_left - 1'b1;
                                write_addr <= write_addr + 32'd4;
                            end
                        end
                    end
                    ST_WRITE_CMD: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else begin
                            phy_cmd_valid <= 1'b1;
                            phy_cmd <= CMD_WRITE;
                            phy_addr <= write_addr;
                            phy_wdata <= s_wdata;
                            phy_wstrb <= s_wstrb;
                            state <= ST_WRITE_DATA;
                        end
                    end
                    ST_PRE: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else begin
                            phy_cmd_valid <= 1'b1;
                            phy_cmd <= CMD_PRE;
                            phy_addr <= command_addr;
                            bank_open <= 1'b0;
                            timer <= COMMAND_LATENCY;
                            state <= ST_ACT;
                        end
                    end
                    ST_REFRESH: begin
                        if (timer > 1) timer <= timer - 1'b1;
                        else begin
                            phy_cmd_valid <= 1'b1;
                            phy_cmd <= CMD_REFRESH;
                            phy_addr <= 0;
                            bank_open <= 1'b0;
                            state <= ST_READY;
                        end
                    end
                    ST_FATAL: begin
                        state <= ST_FATAL;
                    end
                    default: begin
                        state <= ST_FATAL;
                        error_code_r <= {12'd0, ERR_FATAL};
                    end
                endcase
            end
        end
    end
endmodule
