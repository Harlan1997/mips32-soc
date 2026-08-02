// Vendor-neutral ownership contract for a shared SPI/QSPI pin boundary.
//
// A requester must hold *_req until its transaction is complete. Ownership is
// latched for the whole transaction; an active owner is never preempted.
// Command traffic has priority only when the bus is idle or the previous
// owner has released it. A requester that asserts *_active without owning the
// bus is reported as a conflict and cannot drive the pins.

module qspi_shared_pin_arbiter (
    input  wire clk,
    input  wire rst_n,

    input  wire cmd_req,
    input  wire cmd_active,
    input  wire cmd_sclk,
    input  wire cmd_cs_n,
    input  wire cmd_mosi,

    input  wire mem_req,
    input  wire mem_active,
    input  wire mem_sclk,
    input  wire mem_cs_n,
    input  wire mem_mosi,

    output wire cmd_grant,
    output wire mem_grant,
    output wire spi_sclk,
    output wire spi_cs_n,
    output wire spi_mosi,
    output wire busy,
    output wire conflict
);
    localparam [1:0] OWNER_IDLE = 2'd0;
    localparam [1:0] OWNER_CMD  = 2'd1;
    localparam [1:0] OWNER_MEM  = 2'd2;

    reg [1:0] owner_r;

    wire cmd_claim = cmd_req || cmd_active;
    wire mem_claim = mem_req || mem_active;

    assign cmd_grant = (owner_r == OWNER_CMD);
    assign mem_grant = (owner_r == OWNER_MEM);
    assign busy      = (owner_r != OWNER_IDLE);
    assign conflict  = cmd_claim && mem_claim;

    assign spi_sclk = cmd_grant ? cmd_sclk :
                      mem_grant ? mem_sclk : 1'b0;
    assign spi_cs_n = cmd_grant ? cmd_cs_n :
                      mem_grant ? mem_cs_n : 1'b1;
    assign spi_mosi = cmd_grant ? cmd_mosi :
                      mem_grant ? mem_mosi : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner_r <= OWNER_IDLE;
        end else begin
            case (owner_r)
                OWNER_IDLE: begin
                    if (cmd_claim)
                        owner_r <= OWNER_CMD;
                    else if (mem_claim)
                        owner_r <= OWNER_MEM;
                end
                OWNER_CMD: begin
                    if (!cmd_claim) begin
                        if (mem_claim)
                            owner_r <= OWNER_MEM;
                        else
                            owner_r <= OWNER_IDLE;
                    end
                end
                OWNER_MEM: begin
                    if (!mem_claim) begin
                        if (cmd_claim)
                            owner_r <= OWNER_CMD;
                        else
                            owner_r <= OWNER_IDLE;
                    end
                end
                default: owner_r <= OWNER_IDLE;
            endcase
        end
    end
endmodule
