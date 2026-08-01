// =============================================================================
// File Name: ddr4_phy_behavioral.v
// Design:    Vendor-neutral DDR4 abstract PHY behavior model (F1)
// Description:
//   Models the controller-facing behavior that can be verified before a
//   foundry/vendor PHY is available. This is intentionally not a DFI port
//   implementation: command/address and training timing remain abstract.
//   The model provides deterministic init/training, refresh busy, read/write,
//   backpressure and sticky error behavior for contract verification.
//
//   Evidence classification: BLOCK_VERIFIED (vendor-neutral). It must not be
//   used as evidence for a TSMC N28 IO, Synopsys DFI port, SI/PI margin or
//   product DDR4 boot.
// =============================================================================

module ddr4_phy_behavioral #(
    parameter integer MEM_DEPTH_WORDS = 1024,
    parameter integer INIT_CYCLES = 4,
    parameter integer TRAIN_CYCLES = 4,
    parameter integer REFRESH_CYCLES = 3
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        init_start,
    input  wire        inject_init_fail,
    input  wire        inject_training_fail,
    input  wire        inject_fatal,
    input  wire        refresh_req,

    // Abstract command interface. A future vendor adapter maps this interface
    // to the selected PHY's DFI ports after the port list is available.
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [3:0]  cmd,
    input  wire [31:0] cmd_addr,
    input  wire [31:0] cmd_wdata,
    input  wire [3:0]  cmd_wstrb,

    output reg         rd_valid,
    input  wire        rd_ready,
    output reg  [31:0] rd_data,
    output reg         rd_error,
    output reg  [15:0] rd_error_code,

    output reg         init_done,
    output reg         training_done,
    output wire        refresh_busy,
    output reg         fatal_error,
    output reg  [15:0] error_code
);

    localparam [3:0] CMD_NOP = 4'h0;
    localparam [3:0] CMD_READ = 4'h1;
    localparam [3:0] CMD_WRITE = 4'h2;
    localparam [3:0] CMD_REFRESH = 4'h3;

    localparam [2:0] ST_RESET = 3'd0;
    localparam [2:0] ST_INIT = 3'd1;
    localparam [2:0] ST_TRAIN = 3'd2;
    localparam [2:0] ST_READY = 3'd3;
    localparam [2:0] ST_REFRESH = 3'd4;
    localparam [2:0] ST_FATAL = 3'd5;

    localparam [15:0] ERR_INIT_FAIL = 16'h0001;
    localparam [15:0] ERR_TRAIN_FAIL = 16'h0002;
    localparam [15:0] ERR_BAD_COMMAND = 16'h0003;
    localparam [15:0] ERR_FATAL_INJECT = 16'h0004;

    reg [2:0] state;
    reg [31:0] phase_count;
    reg [31:0] ram [0:MEM_DEPTH_WORDS-1];
    integer i;

    function integer word_index;
        input [31:0] addr;
        begin
            word_index = (addr >> 2) % MEM_DEPTH_WORDS;
        end
    endfunction

    assign cmd_ready = (state == ST_READY) && !rd_valid;
    assign refresh_busy = (state == ST_REFRESH);

    initial begin
        for (i = 0; i < MEM_DEPTH_WORDS; i = i + 1)
            ram[i] = 32'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_RESET;
            phase_count    <= 32'd0;
            rd_valid       <= 1'b0;
            rd_data        <= 32'd0;
            rd_error       <= 1'b0;
            rd_error_code  <= 16'd0;
            init_done      <= 1'b0;
            training_done  <= 1'b0;
            fatal_error    <= 1'b0;
            error_code     <= 16'd0;
        end else begin
            if (rd_valid && rd_ready)
                rd_valid <= 1'b0;

            if (inject_fatal && (state != ST_FATAL)) begin
                state       <= ST_FATAL;
                fatal_error <= 1'b1;
                error_code  <= ERR_FATAL_INJECT;
                rd_valid    <= 1'b0;
            end else begin
                case (state)
                    ST_RESET: begin
                        init_done     <= 1'b0;
                        training_done <= 1'b0;
                        if (init_start) begin
                            state       <= ST_INIT;
                            phase_count <= (INIT_CYCLES < 1) ? 32'd1 : INIT_CYCLES;
                        end
                    end
                    ST_INIT: begin
                        if (phase_count > 1) begin
                            phase_count <= phase_count - 1'b1;
                        end else if (inject_init_fail) begin
                            state       <= ST_FATAL;
                            fatal_error <= 1'b1;
                            error_code  <= ERR_INIT_FAIL;
                        end else begin
                            state       <= ST_TRAIN;
                            phase_count <= (TRAIN_CYCLES < 1) ? 32'd1 : TRAIN_CYCLES;
                        end
                    end
                    ST_TRAIN: begin
                        if (phase_count > 1) begin
                            phase_count <= phase_count - 1'b1;
                        end else if (inject_training_fail) begin
                            state       <= ST_FATAL;
                            fatal_error <= 1'b1;
                            error_code  <= ERR_TRAIN_FAIL;
                        end else begin
                            state         <= ST_READY;
                            init_done     <= 1'b1;
                            training_done <= 1'b1;
                        end
                    end
                    ST_READY: begin
                        if (refresh_req) begin
                            state       <= ST_REFRESH;
                            phase_count <= (REFRESH_CYCLES < 1) ? 32'd1 : REFRESH_CYCLES;
                        end else if (cmd_valid && cmd_ready) begin
                            case (cmd)
                                CMD_READ: begin
                                    rd_valid      <= 1'b1;
                                    rd_data       <= ram[word_index(cmd_addr)];
                                    rd_error      <= 1'b0;
                                    rd_error_code <= 16'd0;
                                end
                                CMD_WRITE: begin
                                    if (cmd_wstrb[0]) ram[word_index(cmd_addr)][7:0]   <= cmd_wdata[7:0];
                                    if (cmd_wstrb[1]) ram[word_index(cmd_addr)][15:8]  <= cmd_wdata[15:8];
                                    if (cmd_wstrb[2]) ram[word_index(cmd_addr)][23:16] <= cmd_wdata[23:16];
                                    if (cmd_wstrb[3]) ram[word_index(cmd_addr)][31:24] <= cmd_wdata[31:24];
                                end
                                CMD_REFRESH: begin
                                    state       <= ST_REFRESH;
                                    phase_count <= (REFRESH_CYCLES < 1) ? 32'd1 : REFRESH_CYCLES;
                                end
                                CMD_NOP: begin
                                end
                                default: begin
                                    state       <= ST_FATAL;
                                    fatal_error <= 1'b1;
                                    error_code  <= ERR_BAD_COMMAND;
                                end
                            endcase
                        end
                    end
                    ST_REFRESH: begin
                        if (phase_count > 1)
                            phase_count <= phase_count - 1'b1;
                        else
                            state <= ST_READY;
                    end
                    ST_FATAL: begin
                        state       <= ST_FATAL;
                        fatal_error <= 1'b1;
                    end
                    default: state <= ST_FATAL;
                endcase
            end
        end
    end

endmodule
