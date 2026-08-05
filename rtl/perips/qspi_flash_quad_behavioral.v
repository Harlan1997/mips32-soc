// Vendor-neutral x4-output serial flash endpoint for RTL functional tests.
//
// It accepts the deliberately small 0x6B contract used by qspi_axi_xip when
// ENABLE_QUAD_IO is set: x1 opcode, x1 24-bit address, then x4 data nibbles.
// This model has no timing, voltage, endurance, or vendor-specific behavior.

module qspi_flash_quad_behavioral #(
    parameter integer MEM_BYTES = 65536
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       spi_sclk,
    input  wire       spi_cs_n,
    inout  wire [3:0] spi_io
);
    localparam [2:0] ST_CMD       = 3'd0;
    localparam [2:0] ST_ADDR      = 3'd1;
    localparam [2:0] ST_DATA      = 3'd2;
    localparam [2:0] ST_DATA_ARM  = 3'd3;
    localparam [2:0] ST_IGNORE    = 3'd4;

    reg [7:0] mem [0:MEM_BYTES-1];
    reg [2:0] state;
    reg [7:0] shift_r;
    reg [7:0] cmd_r;
    reg [23:0] addr_r;
    reg [23:0] active_addr_r;
    reg [5:0] bit_count_r;
    reg [15:0] byte_count_r;
    reg [3:0] io_o_r;
    reg [3:0] io_oe_r;
    function automatic integer mem_index(input [23:0] base,
                                          input integer offset);
        integer value;
        begin
            value = base + offset;
            while (value >= MEM_BYTES)
                value = value - MEM_BYTES;
            while (value < 0)
                value = value + MEM_BYTES;
            mem_index = value;
        end
    endfunction

    always @(negedge spi_cs_n or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_CMD;
            shift_r        <= 8'h0;
            cmd_r          <= 8'h0;
            addr_r         <= 24'h0;
            active_addr_r  <= 24'h0;
            bit_count_r    <= 0;
            byte_count_r   <= 0;
        end else begin
            state          <= ST_CMD;
            shift_r        <= 8'h0;
            cmd_r          <= 8'h0;
            addr_r         <= 24'h0;
            active_addr_r  <= 24'h0;
            bit_count_r    <= 0;
            byte_count_r   <= 0;
        end
    end

    // The controller emits command/address on lane 0 and samples the flash
    // output on falling SCLK edges during the x4 data phase.
    always @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_CMD;
            shift_r       <= 8'h0;
            cmd_r         <= 8'h0;
            addr_r        <= 24'h0;
            active_addr_r <= 24'h0;
            bit_count_r   <= 0;
            byte_count_r  <= 0;
        end else if (!spi_cs_n) begin
            case (state)
                ST_CMD: begin
                    shift_r <= {shift_r[6:0], spi_io[0]};
                    if (bit_count_r == 7) begin
                        cmd_r       <= {shift_r[6:0], spi_io[0]};
                        bit_count_r <= 0;
                        state       <= ({shift_r[6:0], spi_io[0]} == 8'h6b) ?
                                       ST_ADDR : ST_IGNORE;
                    end else begin
                        bit_count_r <= bit_count_r + 1'b1;
                    end
                end
                ST_ADDR: begin
                    addr_r <= {addr_r[22:0], spi_io[0]};
                    if (bit_count_r == 23) begin
                        active_addr_r <= {addr_r[22:0], spi_io[0]};
                        bit_count_r <= 0;
                        byte_count_r <= 0;
                        // The controller enters its data state on the
                        // following falling edge. Arm the flash model so the
                        // first data nibble remains visible through that
                        // boundary instead of being advanced early.
                        state <= ST_DATA_ARM;
                    end else begin
                        bit_count_r <= bit_count_r + 1'b1;
                    end
                end
                default: begin end
            endcase
        end
    end

    always @(negedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count_r <= 0;
            byte_count_r <= 0;
        end else if (!spi_cs_n && state == ST_DATA_ARM) begin
            state <= ST_DATA;
            bit_count_r <= 0;
            byte_count_r <= 0;
        end else if (!spi_cs_n && state == ST_DATA) begin
            if (bit_count_r == 4) begin
                bit_count_r <= 0;
                byte_count_r <= byte_count_r + 1'b1;
            end else begin
                bit_count_r <= 4;
            end
        end
    end

    always @(*) begin
        io_o_r = 4'h0;
        io_oe_r = 4'h0;
        if (!spi_cs_n && state == ST_DATA) begin
            io_oe_r = 4'hf;
            if (bit_count_r == 0)
                io_o_r = mem[mem_index(active_addr_r, byte_count_r)][7:4];
            else
                io_o_r = mem[mem_index(active_addr_r, byte_count_r)][3:0];
        end
    end

    assign spi_io[0] = io_oe_r[0] ? io_o_r[0] : 1'bz;
    assign spi_io[1] = io_oe_r[1] ? io_o_r[1] : 1'bz;
    assign spi_io[2] = io_oe_r[2] ? io_o_r[2] : 1'bz;
    assign spi_io[3] = io_oe_r[3] ? io_o_r[3] : 1'bz;

    wire unused_clk = clk;
endmodule
