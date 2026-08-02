// Vendor-neutral serial NOR flash behavioral endpoint.
//
// This model is intentionally small and pin-oriented.  It is used to prove
// that the QSPI command contract can exchange data with a flash-like device;
// it is not a timing, voltage, endurance, or vendor-model replacement.

module spi_flash_behavioral #(
    parameter integer MEM_BYTES = 65536,
    parameter [7:0]  JEDEC_MFG  = 8'hef,
    parameter [7:0]  JEDEC_TYPE = 8'h40,
    parameter [7:0]  JEDEC_DENS = 8'h16,
    parameter [1023:0] INIT_FILE = ""
) (
    input  wire clk,
    input  wire rst_n,
    input  wire spi_sclk,
    input  wire spi_cs_n,
    input  wire spi_mosi,
    output reg  spi_miso
);
    localparam [3:0] ST_CMD     = 4'd0;
    localparam [3:0] ST_ADDR    = 4'd1;
    localparam [3:0] ST_READ    = 4'd2;
    localparam [3:0] ST_STATUS  = 4'd3;
    localparam [3:0] ST_ID      = 4'd4;
    localparam [3:0] ST_PROGRAM = 4'd5;
    localparam [3:0] ST_ERASE   = 4'd6;
    localparam [3:0] ST_IGNORE  = 4'd7;

    reg [7:0] mem [0:MEM_BYTES-1];
    reg [3:0] state;
    reg [7:0] cmd_r;
    reg [7:0] shift_r;
    reg [23:0] addr_r;
    reg [23:0] active_addr_r;
    reg [5:0] bit_count_r;
    reg [15:0] byte_count_r;
    reg out_started_r;
    reg wel_r;
    reg wip_r;
    integer i;

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

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1)
            mem[i] = 8'hff;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // A transaction starts at CS assertion.  The command parser runs on the
    // rising SPI edge; the controller samples MISO on the following falling
    // edge, so output bits are combinational from the current read position.
    always @(negedge spi_cs_n or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_CMD;
            cmd_r          <= 8'h0;
            shift_r        <= 8'h0;
            addr_r         <= 24'h0;
            active_addr_r  <= 24'h0;
            bit_count_r    <= 0;
            byte_count_r   <= 0;
            out_started_r  <= 1'b0;
            wel_r          <= 1'b0;
            wip_r          <= 1'b0;
        end else begin
            state          <= ST_CMD;
            cmd_r          <= 8'h0;
            shift_r        <= 8'h0;
            addr_r         <= 24'h0;
            active_addr_r  <= 24'h0;
            bit_count_r    <= 0;
            byte_count_r   <= 0;
            out_started_r  <= 1'b0;
        end
    end

    // Commit program/erase at CS deassertion.  Page program data is captured
    // as it arrives; NOR semantics only clear bits (1 -> 0).
    always @(posedge spi_cs_n or negedge rst_n) begin
        if (!rst_n) begin
            wip_r <= 1'b0;
        end else if (state == ST_ERASE && wel_r) begin
            for (i = 0; i < 4096; i = i + 1)
                mem[mem_index({active_addr_r[23:12], 12'h000}, i)] <= 8'hff;
            wip_r <= 1'b0;
            wel_r <= 1'b0;
        end else if (state == ST_PROGRAM && wel_r) begin
            wip_r <= 1'b0;
            wel_r <= 1'b0;
        end
    end

    // Parse command, address, and write data on the rising SPI edge.
    always @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_CMD;
            cmd_r       <= 8'h0;
            shift_r     <= 8'h0;
            addr_r      <= 24'h0;
            active_addr_r <= 24'h0;
            bit_count_r <= 0;
            byte_count_r <= 0;
            out_started_r <= 1'b0;
            wel_r       <= 1'b0;
            wip_r       <= 1'b0;
        end else if (!spi_cs_n) begin
            case (state)
                ST_CMD: begin
                    shift_r <= {shift_r[6:0], spi_mosi};
                    if (bit_count_r == 7) begin
                        cmd_r       <= {shift_r[6:0], spi_mosi};
                        bit_count_r <= 0;
                        case ({shift_r[6:0], spi_mosi})
                            8'h03: state <= ST_ADDR;
                            8'h02: state <= ST_ADDR;
                            8'h20: state <= ST_ADDR;
                            8'h05: begin
                                state <= ST_STATUS; bit_count_r <= 0;
                                out_started_r <= 1'b0;
                            end
                            8'h9f: begin
                                state <= ST_ID; bit_count_r <= 0;
                                out_started_r <= 1'b0;
                            end
                            8'h06: begin wel_r <= 1'b1; state <= ST_IGNORE; end
                            default: state <= ST_IGNORE;
                        endcase
                    end else begin
                        bit_count_r <= bit_count_r + 1'b1;
                    end
                end
                ST_ADDR: begin
                    addr_r <= {addr_r[22:0], spi_mosi};
                    if (bit_count_r == 23) begin
                        active_addr_r <= {addr_r[22:0], spi_mosi};
                        bit_count_r <= 0;
                        byte_count_r <= 0;
                        if (cmd_r == 8'h02) begin
                            state <= ST_PROGRAM;
                            wip_r <= wel_r;
                        end else if (cmd_r == 8'h20) begin
                            state <= ST_ERASE;
                            wip_r <= wel_r;
                        end else begin
                            state <= ST_READ;
                            out_started_r <= 1'b0;
                        end
                    end else begin
                        bit_count_r <= bit_count_r + 1'b1;
                    end
                end
                ST_PROGRAM: begin
                    shift_r <= {shift_r[6:0], spi_mosi};
                    if (bit_count_r == 7) begin
                        if (wel_r)
                            mem[mem_index(active_addr_r, byte_count_r)] <=
                                mem[mem_index(active_addr_r, byte_count_r)] &
                                {shift_r[6:0], spi_mosi};
                        byte_count_r <= byte_count_r + 1'b1;
                        bit_count_r <= 0;
                    end else begin
                        bit_count_r <= bit_count_r + 1'b1;
                    end
                end
                default: begin
                    // Read/status/ID output phases do not consume MOSI.  The
                    // first rising edge after the command/address phase is
                    // the edge that presents output bit 7; it must not be
                    // counted as a prior falling-edge sample.
                    if ((state == ST_READ || state == ST_STATUS || state == ST_ID) &&
                        !out_started_r)
                        out_started_r <= 1'b1;
                end
            endcase
        end
    end

    // Advance the response stream after the controller has sampled the bit on
    // the falling edge.  A byte wraps naturally to the next memory location.
    always @(negedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count_r  <= 0;
            byte_count_r <= 0;
            out_started_r <= 1'b0;
        end else if (!spi_cs_n && out_started_r &&
                     (state == ST_READ || state == ST_STATUS || state == ST_ID)) begin
            if (bit_count_r == 7) begin
                bit_count_r <= 0;
                byte_count_r <= byte_count_r + 1'b1;
            end else begin
                bit_count_r <= bit_count_r + 1'b1;
            end
        end
    end

    always @(*) begin
        spi_miso = 1'b0;
        if (!spi_cs_n) begin
            case (state)
                ST_READ: begin
                    spi_miso = mem[mem_index(active_addr_r, byte_count_r)]
                               [7-bit_count_r];
                end
                ST_STATUS: begin
                    // Status byte is {6'b0, WEL, WIP}, sent MSB first.
                    spi_miso = (bit_count_r == 6) ? wel_r :
                               (bit_count_r == 7) ? wip_r : 1'b0;
                end
                ST_ID: begin
                    case (byte_count_r)
                        0: spi_miso = JEDEC_MFG[7-bit_count_r];
                        1: spi_miso = JEDEC_TYPE[7-bit_count_r];
                        default: spi_miso = JEDEC_DENS[7-bit_count_r];
                    endcase
                end
                default: spi_miso = 1'b0;
            endcase
        end
    end

    // Keep clk in the interface so a future timing model can add an internal
    // busy timer without changing the testbench contract.
    wire unused_clk = clk;
endmodule
