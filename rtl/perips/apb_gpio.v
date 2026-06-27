// =============================================================================
// File Name: apb_gpio.v
// Design:    APB GPIO Peripheral
// Author:    Antigravity
// Description: 
//   A simple 32-bit GPIO peripheral connected to the APB bus.
//   Registers:
//   - 0x00: GPIO_DATA (Read/Write) - Current pin values (for input) or driven values (for output)
//   - 0x04: GPIO_DIR  (Read/Write) - Direction (1 = Output, 0 = Input)
// =============================================================================

module apb_gpio #(
    parameter APB_ADDR_WIDTH = 12
) (
    input  wire                      pclk,
    input  wire                      presetn,
    
    // APB Slave Interface
    input  wire [APB_ADDR_WIDTH-1:0] paddr,
    input  wire                      psel,
    input  wire                      penable,
    input  wire                      pwrite,
    input  wire [31:0]               pwdata,
    output wire                      pready,
    output wire [31:0]               prdata,
    output wire                      pslverr,
    
    // External GPIO Pins
    inout  wire [31:0]               gpio_pins
);

    // Register offsets
    localparam GPIO_DATA_REG = 12'h000;
    localparam GPIO_DIR_REG  = 12'h004;
    
    // Registers
    reg [31:0] gpio_data_out;
    reg [31:0] gpio_dir;
    
    // APB Write
    wire apb_write_en = psel & penable & pwrite;
    
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            gpio_data_out <= 32'd0;
            gpio_dir      <= 32'd0; // All inputs by default
        end else if (apb_write_en) begin
            case (paddr)
                GPIO_DATA_REG: gpio_data_out <= pwdata;
                GPIO_DIR_REG:  gpio_dir      <= pwdata;
                default: ; // Ignore writes to other addresses
            endcase
        end
    end
    
    // Synchronize GPIO inputs (2-stage synchronizer to avoid metastability)
    reg [31:0] gpio_in_sync1;
    reg [31:0] gpio_in_sync2;
    
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            gpio_in_sync1 <= 32'd0;
            gpio_in_sync2 <= 32'd0;
        end else begin
            gpio_in_sync1 <= gpio_pins;
            gpio_in_sync2 <= gpio_in_sync1;
        end
    end
    
    // APB Read
    reg [31:0] rdata_reg;
    always @(*) begin
        case (paddr)
            GPIO_DATA_REG: rdata_reg = (gpio_data_out & gpio_dir) | (gpio_in_sync2 & ~gpio_dir);
            GPIO_DIR_REG:  rdata_reg = gpio_dir;
            default:       rdata_reg = 32'd0;
        endcase
    end
    
    assign prdata  = rdata_reg;
    assign pready  = 1'b1; // Zero wait states
    assign pslverr = 1'b0; // No slave errors
    
    // Tristate GPIO Pin Drivers
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_tristate
            assign gpio_pins[i] = gpio_dir[i] ? gpio_data_out[i] : 1'bz;
        end
    endgenerate

endmodule
