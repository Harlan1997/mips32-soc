// =============================================================================
// File Name: soc_memory_subsystem.v
// Design:    SoC memory subsystem integration
// =============================================================================

`include "soc_config.vh"

module soc_memory_subsystem #(
    parameter ENABLE_FLASH_IMAGE_MODEL = 1'b0,
    parameter SRAM_DEPTH_WORDS = 32768,
    parameter integer SPI_READ_TIMEOUT_CYCLES = 512,
    parameter ENABLE_SHARED_ARB = 1'b0,
    parameter ENABLE_QSPI_QUAD = 1'b0,
    parameter ENABLE_DDR4_STATUS = 1'b0,
    parameter ENABLE_DDR4_STATUS_FATAL = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire [3:0]  qspi_io_i,
    output wire [3:0]  qspi_io_o,
    output wire [3:0]  qspi_io_oe,
    input  wire        spi_arb_grant,
    output wire        spi_req,

    output wire        qspi_timeout_sticky,
    output wire        qspi_controller_present,
    output wire        ddr4_controller_present,
    output wire        ddr4_init_done,
    output wire        ddr4_training_done,
    output wire        ddr4_fatal_error,
    output wire        ddr4_ecc_correctable_error,
    output wire        ddr4_ecc_uncorrectable_error,
    output wire [15:0] ddr4_error_code,

    input  wire [3:0]  s0_awid,
    input  wire [31:0] s0_awaddr,
    input  wire [7:0]  s0_awlen,
    input  wire [2:0]  s0_awsize,
    input  wire [1:0]  s0_awburst,
    input  wire [1:0]  s0_awlock,
    input  wire [3:0]  s0_awcache,
    input  wire [2:0]  s0_awprot,
    input  wire        s0_awvalid,
    output wire        s0_awready,
    input  wire [31:0] s0_wdata,
    input  wire [3:0]  s0_wstrb,
    input  wire        s0_wlast,
    input  wire        s0_wvalid,
    output wire        s0_wready,
    output wire [3:0]  s0_bid,
    output wire [1:0]  s0_bresp,
    output wire        s0_bvalid,
    input  wire        s0_bready,
    input  wire [3:0]  s0_arid,
    input  wire [31:0] s0_araddr,
    input  wire [7:0]  s0_arlen,
    input  wire [2:0]  s0_arsize,
    input  wire [1:0]  s0_arburst,
    input  wire [1:0]  s0_arlock,
    input  wire [3:0]  s0_arcache,
    input  wire [2:0]  s0_arprot,
    input  wire        s0_arvalid,
    output wire        s0_arready,
    output wire [3:0]  s0_rid,
    output wire [31:0] s0_rdata,
    output wire [1:0]  s0_rresp,
    output wire        s0_rlast,
    output wire        s0_rvalid,
    input  wire        s0_rready,

    input  wire [3:0]  s2_awid,
    input  wire [31:0] s2_awaddr,
    input  wire [7:0]  s2_awlen,
    input  wire [2:0]  s2_awsize,
    input  wire [1:0]  s2_awburst,
    input  wire [1:0]  s2_awlock,
    input  wire [3:0]  s2_awcache,
    input  wire [2:0]  s2_awprot,
    input  wire        s2_awvalid,
    output wire        s2_awready,
    input  wire [31:0] s2_wdata,
    input  wire [3:0]  s2_wstrb,
    input  wire        s2_wlast,
    input  wire        s2_wvalid,
    output wire        s2_wready,
    output wire [3:0]  s2_bid,
    output wire [1:0]  s2_bresp,
    output wire        s2_bvalid,
    input  wire        s2_bready,
    input  wire [3:0]  s2_arid,
    input  wire [31:0] s2_araddr,
    input  wire [7:0]  s2_arlen,
    input  wire [2:0]  s2_arsize,
    input  wire [1:0]  s2_arburst,
    input  wire [1:0]  s2_arlock,
    input  wire [3:0]  s2_arcache,
    input  wire [2:0]  s2_arprot,
    input  wire        s2_arvalid,
    output wire        s2_arready,
    output wire [3:0]  s2_rid,
    output wire [31:0] s2_rdata,
    output wire [1:0]  s2_rresp,
    output wire        s2_rlast,
    output wire        s2_rvalid,
    input  wire        s2_rready,

    input  wire [3:0]  s3_awid,
    input  wire [31:0] s3_awaddr,
    input  wire [7:0]  s3_awlen,
    input  wire [2:0]  s3_awsize,
    input  wire [1:0]  s3_awburst,
    input  wire [1:0]  s3_awlock,
    input  wire [3:0]  s3_awcache,
    input  wire [2:0]  s3_awprot,
    input  wire        s3_awvalid,
    output wire        s3_awready,
    input  wire [31:0] s3_wdata,
    input  wire [3:0]  s3_wstrb,
    input  wire        s3_wlast,
    input  wire        s3_wvalid,
    output wire        s3_wready,
    output wire [3:0]  s3_bid,
    output wire [1:0]  s3_bresp,
    output wire        s3_bvalid,
    input  wire        s3_bready,
    input  wire [3:0]  s3_arid,
    input  wire [31:0] s3_araddr,
    input  wire [7:0]  s3_arlen,
    input  wire [2:0]  s3_arsize,
    input  wire [1:0]  s3_arburst,
    input  wire [1:0]  s3_arlock,
    input  wire [3:0]  s3_arcache,
    input  wire [2:0]  s3_arprot,
    input  wire        s3_arvalid,
    output wire        s3_arready,
    output wire [3:0]  s3_rid,
    output wire [31:0] s3_rdata,
    output wire [1:0]  s3_rresp,
    output wire        s3_rlast,
    output wire        s3_rvalid,
    input  wire        s3_rready,

    input  wire [3:0]  s4_awid,
    input  wire [31:0] s4_awaddr,
    input  wire [7:0]  s4_awlen,
    input  wire [2:0]  s4_awsize,
    input  wire [1:0]  s4_awburst,
    input  wire [1:0]  s4_awlock,
    input  wire [3:0]  s4_awcache,
    input  wire [2:0]  s4_awprot,
    input  wire        s4_awvalid,
    output wire        s4_awready,
    input  wire [31:0] s4_wdata,
    input  wire [3:0]  s4_wstrb,
    input  wire        s4_wlast,
    input  wire        s4_wvalid,
    output wire        s4_wready,
    output wire [3:0]  s4_bid,
    output wire [1:0]  s4_bresp,
    output wire        s4_bvalid,
    input  wire        s4_bready,
    input  wire [3:0]  s4_arid,
    input  wire [31:0] s4_araddr,
    input  wire [7:0]  s4_arlen,
    input  wire [2:0]  s4_arsize,
    input  wire [1:0]  s4_arburst,
    input  wire [1:0]  s4_arlock,
    input  wire [3:0]  s4_arcache,
    input  wire [2:0]  s4_arprot,
    input  wire        s4_arvalid,
    output wire        s4_arready,
    output wire [3:0]  s4_rid,
    output wire [31:0] s4_rdata,
    output wire [1:0]  s4_rresp,
    output wire        s4_rlast,
    output wire        s4_rvalid,
    input  wire        s4_rready
);

    // Keep legacy standalone subsystem instantiations functional when the
    // optional shared-pin contract is not enabled at the SoC top.
    wire effective_spi_grant = ENABLE_SHARED_ARB ? spi_arb_grant : 1'b1;

`ifdef SOC_USE_L2_CACHE
    // ---- L2 cache in-line between fabric and axi_ddr_model backing store ----
    wire [3:0]  l2m_awid, l2m_arid, l2m_bid, l2m_rid;
    wire [31:0] l2m_awaddr, l2m_araddr, l2m_wdata, l2m_rdata;
    wire [7:0]  l2m_awlen, l2m_arlen;
    wire [2:0]  l2m_awsize, l2m_arsize;
    wire [1:0]  l2m_awburst, l2m_arburst, l2m_bresp, l2m_rresp;
    wire        l2m_awvalid, l2m_awready, l2m_wvalid, l2m_wready, l2m_wlast;
    wire        l2m_bvalid, l2m_bready, l2m_arvalid, l2m_arready;
    wire        l2m_rvalid, l2m_rready, l2m_rlast;
    wire [3:0]  l2m_wstrb;

    l2_cache #(
        .SIZE_BYTES(131072), .LINE_BYTES(32), .WAYS(8),
        .ID_WIDTH(4), .ADDR_WIDTH(32), .DATA_WIDTH(32)
    ) u_l2_cache (
        .clk(clk), .rst_n(rst_n),
        // Upstream slave = original s0 (from fabric)
        .s_awid(s0_awid), .s_awaddr(s0_awaddr), .s_awlen(s0_awlen),
        .s_awsize(s0_awsize), .s_awburst(s0_awburst),
        .s_awvalid(s0_awvalid), .s_awready(s0_awready),
        .s_wdata(s0_wdata), .s_wstrb(s0_wstrb), .s_wlast(s0_wlast),
        .s_wvalid(s0_wvalid), .s_wready(s0_wready),
        .s_bid(s0_bid), .s_bresp(s0_bresp), .s_bvalid(s0_bvalid), .s_bready(s0_bready),
        .s_arid(s0_arid), .s_araddr(s0_araddr), .s_arlen(s0_arlen),
        .s_arsize(s0_arsize), .s_arburst(s0_arburst),
        .s_arvalid(s0_arvalid), .s_arready(s0_arready),
        .s_rid(s0_rid), .s_rdata(s0_rdata), .s_rresp(s0_rresp),
        .s_rlast(s0_rlast), .s_rvalid(s0_rvalid), .s_rready(s0_rready),
        // Downstream master = new axi_ddr_model
        .m_awid(l2m_awid), .m_awaddr(l2m_awaddr), .m_awlen(l2m_awlen),
        .m_awsize(l2m_awsize), .m_awburst(l2m_awburst),
        .m_awvalid(l2m_awvalid), .m_awready(l2m_awready),
        .m_wdata(l2m_wdata), .m_wstrb(l2m_wstrb), .m_wlast(l2m_wlast),
        .m_wvalid(l2m_wvalid), .m_wready(l2m_wready),
        .m_bid(l2m_bid), .m_bresp(l2m_bresp), .m_bvalid(l2m_bvalid), .m_bready(l2m_bready),
        .m_arid(l2m_arid), .m_araddr(l2m_araddr), .m_arlen(l2m_arlen),
        .m_arsize(l2m_arsize), .m_arburst(l2m_arburst),
        .m_arvalid(l2m_arvalid), .m_arready(l2m_arready),
        .m_rid(l2m_rid), .m_rdata(l2m_rdata), .m_rresp(l2m_rresp),
        .m_rlast(l2m_rlast), .m_rvalid(l2m_rvalid), .m_rready(l2m_rready),
        .snoop_addr(32'h0), .snoop_valid(1'b0),
        .snoop_ack(), .snoop_hit()
    );

    axi_ddr_model #(
        .MEM_DEPTH_WORDS (SRAM_DEPTH_WORDS)
    ) u_axi_sram (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_awid          (l2m_awid),
        .s_awaddr        (l2m_awaddr),
        .s_awlen         (l2m_awlen),
        .s_awsize        (l2m_awsize),
        .s_awburst       (l2m_awburst),
        .s_awvalid       (l2m_awvalid),
        .s_awready       (l2m_awready),
        .s_wdata         (l2m_wdata),
        .s_wstrb         (l2m_wstrb),
        .s_wlast         (l2m_wlast),
        .s_wvalid        (l2m_wvalid),
        .s_wready        (l2m_wready),
        .s_bid           (l2m_bid),
        .s_bresp         (l2m_bresp),
        .s_bvalid        (l2m_bvalid),
        .s_bready        (l2m_bready),
        .s_arid          (l2m_arid),
        .s_araddr        (l2m_araddr),
        .s_arlen         (l2m_arlen),
        .s_arsize        (l2m_arsize),
        .s_arburst       (l2m_arburst),
        .s_arvalid       (l2m_arvalid),
        .s_arready       (l2m_arready),
        .s_rid           (l2m_rid),
        .s_rdata         (l2m_rdata),
        .s_rresp         (l2m_rresp),
        .s_rlast         (l2m_rlast),
        .s_rvalid        (l2m_rvalid),
        .s_rready        (l2m_rready)
    );
`else
    axi_ddr_model #(
        .MEM_DEPTH_WORDS (SRAM_DEPTH_WORDS)
    ) u_axi_sram (
        .clk             (clk),
        .rst_n           (rst_n),

        .s_awid          (s0_awid),
        .s_awaddr        (s0_awaddr),
        .s_awlen         (s0_awlen),
        .s_awsize        (s0_awsize),
        .s_awburst       (s0_awburst),
        .s_awvalid       (s0_awvalid),
        .s_awready       (s0_awready),
        .s_wdata         (s0_wdata),
        .s_wstrb         (s0_wstrb),
        .s_wlast         (s0_wlast),
        .s_wvalid        (s0_wvalid),
        .s_wready        (s0_wready),
        .s_bid           (s0_bid),
        .s_bresp         (s0_bresp),
        .s_bvalid        (s0_bvalid),
        .s_bready        (s0_bready),
        .s_arid          (s0_arid),
        .s_araddr        (s0_araddr),
        .s_arlen         (s0_arlen),
        .s_arsize        (s0_arsize),
        .s_arburst       (s0_arburst),
        .s_arvalid       (s0_arvalid),
        .s_arready       (s0_arready),
        .s_rid           (s0_rid),
        .s_rdata         (s0_rdata),
        .s_rresp         (s0_rresp),
        .s_rlast         (s0_rlast),
        .s_rvalid        (s0_rvalid),
        .s_rready        (s0_rready)
    );
`endif

    // synopsys translate_off
    task preload_sram_hex;
        input [1023:0] hex_path;
        begin
            u_axi_sram.load_hex(hex_path);
        end
    endtask
    // synopsys translate_on

    // ---- DDR4 window: protocol-level controller.
    // The controller owns AXI acceptance, DDR command sequencing, refresh,
    // address/error checks and the vendor-neutral simulation backing store.
    wire ddr4_ctrl_present_i, ddr4_init_done_i, ddr4_training_done_i;
    wire ddr4_refresh_busy_i, ddr4_fatal_error_i;
    wire ddr4_ecc_correctable_error_i, ddr4_ecc_uncorrectable_error_i;
    wire [15:0] ddr4_error_code_i;
    wire ddr4_phy_cmd_valid_i;
    wire [3:0] ddr4_phy_cmd_i;
    wire [31:0] ddr4_phy_addr_i, ddr4_phy_wdata_i;
    wire [3:0] ddr4_phy_wstrb_i;
    wire ddr4_last_row_hit_i, ddr4_last_row_miss_i;
    axi_ddr4_controller #(
        .INJECT_FATAL(ENABLE_DDR4_STATUS_FATAL),
        .ENABLE_ECC(ENABLE_DDR4_STATUS)
    ) u_axi_ddr4_controller (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_awid          (s3_awid),
        .s_awaddr        (s3_awaddr),
        .s_awlen         (s3_awlen),
        .s_awsize        (s3_awsize),
        .s_awburst       (s3_awburst),
        .s_awvalid       (s3_awvalid),
        .s_awready       (s3_awready),
        .s_wdata         (s3_wdata),
        .s_wstrb         (s3_wstrb),
        .s_wlast         (s3_wlast),
        .s_wvalid        (s3_wvalid),
        .s_wready        (s3_wready),
        .s_bid           (s3_bid),
        .s_bresp         (s3_bresp),
        .s_bvalid        (s3_bvalid),
        .s_bready        (s3_bready),
        .s_arid          (s3_arid),
        .s_araddr        (s3_araddr),
        .s_arlen         (s3_arlen),
        .s_arsize        (s3_arsize),
        .s_arburst       (s3_arburst),
        .s_arvalid       (s3_arvalid),
        .s_arready       (s3_arready),
        .s_rid           (s3_rid),
        .s_rdata         (s3_rdata),
        .s_rresp         (s3_rresp),
        .s_rlast         (s3_rlast),
        .s_rvalid        (s3_rvalid),
        .s_rready        (s3_rready),
        .refresh_req     (1'b0),
        .controller_present(ddr4_ctrl_present_i),
        .init_done       (ddr4_init_done_i),
        .training_done   (ddr4_training_done_i),
        .refresh_busy    (ddr4_refresh_busy_i),
        .fatal_error     (ddr4_fatal_error_i),
        .ecc_correctable_error(ddr4_ecc_correctable_error_i),
        .ecc_uncorrectable_error(ddr4_ecc_uncorrectable_error_i),
        .error_code      (ddr4_error_code_i),
        .phy_cmd_valid   (ddr4_phy_cmd_valid_i),
        .phy_cmd         (ddr4_phy_cmd_i),
        .phy_addr        (ddr4_phy_addr_i),
        .phy_wdata       (ddr4_phy_wdata_i),
        .phy_wstrb       (ddr4_phy_wstrb_i),
        .last_row_hit    (ddr4_last_row_hit_i),
        .last_row_miss   (ddr4_last_row_miss_i)
    );

    generate
        if (ENABLE_DDR4_STATUS) begin : g_ddr4_status_phy
            assign ddr4_controller_present = ddr4_ctrl_present_i;
            assign ddr4_init_done = ddr4_init_done_i;
            assign ddr4_training_done = ddr4_training_done_i;
            assign ddr4_fatal_error = ddr4_fatal_error_i;
            assign ddr4_ecc_correctable_error = ddr4_ecc_correctable_error_i;
            assign ddr4_ecc_uncorrectable_error = ddr4_ecc_uncorrectable_error_i;
            assign ddr4_error_code = ddr4_error_code_i;
        end else begin : g_no_ddr4_status_phy
            assign ddr4_controller_present = 1'b0;
            assign ddr4_init_done = 1'b0;
            assign ddr4_training_done = 1'b0;
            assign ddr4_fatal_error = 1'b0;
            assign ddr4_ecc_correctable_error = 1'b0;
            assign ddr4_ecc_uncorrectable_error = 1'b0;
            assign ddr4_error_code = 16'd0;
        end
    endgenerate

    // synopsys translate_off
    task preload_ddr_hex;
        input [1023:0] hex_path;
        begin
            u_axi_ddr4_controller.load_hex(hex_path);
        end
    endtask
    // synopsys translate_on

    // Keep the shared-pin ownership request asserted from AXI acceptance
    // through completion. The controller's CS can remain inactive for one
    // cycle while the timeout guard hands the request downstream, so CS alone
    // is not sufficient to describe an in-flight memory transaction.
    wire spi_transaction_active;

    generate
    if (ENABLE_FLASH_IMAGE_MODEL) begin : g_flash_image_model
        wire flash_model_arready;
        assign qspi_timeout_sticky     = 1'b0;
        assign qspi_controller_present = 1'b0;
        assign qspi_io_o                = 4'h0;
        assign qspi_io_oe               = 4'h0;
        assign s2_arready              = effective_spi_grant && flash_model_arready;
        assign spi_transaction_active  = !flash_model_arready;
        axi_flash_image_model u_axi_flash_image_model (
            .clk             (clk),
            .rst_n           (rst_n),

            .s_awid          (s2_awid),
            .s_awaddr        (s2_awaddr),
            .s_awlen         (s2_awlen),
            .s_awsize        (s2_awsize),
            .s_awburst       (s2_awburst),
            .s_awlock        (s2_awlock),
            .s_awcache       (s2_awcache),
            .s_awprot        (s2_awprot),
            .s_awvalid       (s2_awvalid),
            .s_awready       (s2_awready),
            .s_wdata         (s2_wdata),
            .s_wstrb         (s2_wstrb),
            .s_wlast         (s2_wlast),
            .s_wvalid        (s2_wvalid),
            .s_wready        (s2_wready),
            .s_bid           (s2_bid),
            .s_bresp         (s2_bresp),
            .s_bvalid        (s2_bvalid),
            .s_bready        (s2_bready),

            .s_arid          (s2_arid),
            .s_araddr        (s2_araddr),
            .s_arlen         (s2_arlen),
            .s_arsize        (s2_arsize),
            .s_arburst       (s2_arburst),
            .s_arlock        (s2_arlock),
            .s_arcache       (s2_arcache),
            .s_arprot        (s2_arprot),
            .s_arvalid       (s2_arvalid && effective_spi_grant),
            .s_arready       (flash_model_arready),
            .s_rid           (s2_rid),
            .s_rdata         (s2_rdata),
            .s_rresp         (s2_rresp),
            .s_rlast         (s2_rlast),
            .s_rvalid        (s2_rvalid),
            .s_rready        (s2_rready),

            .spi_sclk        (spi_sclk),
            .spi_cs_n        (spi_cs_n),
            .spi_mosi        (spi_mosi),
            .spi_miso        (spi_miso)
        );
    end else if (ENABLE_QSPI_QUAD) begin : g_quad_xip_controller
        wire [3:0]  flash_arid;
        wire [31:0] flash_araddr;
        wire [7:0]  flash_arlen;
        wire [2:0]  flash_arsize;
        wire [1:0]  flash_arburst;
        wire [1:0]  flash_arlock;
        wire [3:0]  flash_arcache;
        wire [2:0]  flash_arprot;
        wire        flash_arvalid;
        wire        flash_arready;
        wire        flash_guard_arready;
        wire [3:0]  flash_rid;
        wire [31:0] flash_rdata;
        wire [1:0]  flash_rresp;
        wire        flash_rlast;
        wire        flash_rvalid;
        wire        flash_rready;
        wire        flash_timeout_sticky;
        wire [3:0]  quad_io_o;
        wire [3:0]  quad_io_oe;
        tri  [3:0]  quad_io;

        // Preserve the AXI-side timeout/error ABI while replacing only the
        // pin-level controller with the vendor-neutral quad bridge.
        assign qspi_timeout_sticky     = flash_timeout_sticky;
        assign qspi_controller_present = 1'b1;
        assign qspi_io_o                = quad_io_o;
        assign qspi_io_oe               = quad_io_oe;
        assign quad_io                  = qspi_io_i;

        axi_read_timeout_guard #(
            .TIMEOUT_CYCLES (SPI_READ_TIMEOUT_CYCLES)
        ) u_axi_read_timeout_guard_quad (
            .clk             (clk),
            .rst_n           (rst_n),
            .s_arid          (s2_arid),
            .s_araddr        (s2_araddr),
            .s_arlen         (s2_arlen),
            .s_arsize        (s2_arsize),
            .s_arburst       (s2_arburst),
            .s_arlock        (s2_arlock),
            .s_arcache       (s2_arcache),
            .s_arprot        (s2_arprot),
            .s_arvalid       (s2_arvalid && effective_spi_grant),
            .s_arready       (flash_guard_arready),
            .s_rid           (s2_rid),
            .s_rdata         (s2_rdata),
            .s_rresp         (s2_rresp),
            .s_rlast         (s2_rlast),
            .s_rvalid        (s2_rvalid),
            .s_rready        (s2_rready),
            .m_arid          (flash_arid),
            .m_araddr        (flash_araddr),
            .m_arlen         (flash_arlen),
            .m_arsize        (flash_arsize),
            .m_arburst       (flash_arburst),
            .m_arlock        (flash_arlock),
            .m_arcache       (flash_arcache),
            .m_arprot        (flash_arprot),
            .m_arvalid       (flash_arvalid),
            .m_arready       (flash_arready),
            .m_rid           (flash_rid),
            .m_rdata         (flash_rdata),
            .m_rresp         (flash_rresp),
            .m_rlast         (flash_rlast),
            .m_rvalid        (flash_rvalid),
            .m_rready        (flash_rready),
            .timeout_sticky  (flash_timeout_sticky)
        );

        assign s2_arready = effective_spi_grant && flash_guard_arready;
        assign spi_transaction_active = !flash_guard_arready;

        qspi_axi_xip #(
            .COMMAND_TIMEOUT_CYCLES (SPI_READ_TIMEOUT_CYCLES),
            .ENABLE_QUAD_IO         (1'b1),
            .ENDIAN_SWAP            (1'b1)
        ) u_qspi_axi_xip (
            .clk             (clk),
            .rst_n           (rst_n),
            .s_arid          (flash_arid),
            .s_araddr        (flash_araddr),
            .s_arlen         (flash_arlen),
            .s_arsize        (flash_arsize),
            .s_arburst       (flash_arburst),
            .s_arlock        (flash_arlock),
            .s_arcache       (flash_arcache),
            .s_arprot        (flash_arprot),
            .s_arvalid       (flash_arvalid),
            .s_arready       (flash_arready),
            .s_rid           (flash_rid),
            .s_rdata         (flash_rdata),
            .s_rresp         (flash_rresp),
            .s_rlast         (flash_rlast),
            .s_rvalid        (flash_rvalid),
            .s_rready        (flash_rready),
            .s_awid          (s2_awid),
            .s_awaddr        (s2_awaddr),
            .s_awlen         (s2_awlen),
            .s_awsize        (s2_awsize),
            .s_awburst       (s2_awburst),
            .s_awlock        (s2_awlock),
            .s_awcache       (s2_awcache),
            .s_awprot        (s2_awprot),
            .s_awvalid       (s2_awvalid),
            .s_awready       (s2_awready),
            .s_wdata         (s2_wdata),
            .s_wstrb         (s2_wstrb),
            .s_wlast         (s2_wlast),
            .s_wvalid        (s2_wvalid),
            .s_wready        (s2_wready),
            .s_bid           (s2_bid),
            .s_bresp         (s2_bresp),
            .s_bvalid        (s2_bvalid),
            .s_bready        (s2_bready),
            .spi_sclk        (spi_sclk),
            .spi_cs_n        (spi_cs_n),
            .spi_mosi        (spi_mosi),
            .spi_miso        (spi_miso),
            .qspi_io_o       (quad_io_o),
            .qspi_io_oe      (quad_io_oe),
            .qspi_io         (quad_io),
            .active          ()
        );
    end else begin : g_spi_flash_controller
        assign qspi_io_o  = 4'h0;
        assign qspi_io_oe = 4'h0;
        wire [3:0]  flash_arid;
        wire [31:0] flash_araddr;
        wire [7:0]  flash_arlen;
        wire [2:0]  flash_arsize;
        wire [1:0]  flash_arburst;
        wire [1:0]  flash_arlock;
        wire [3:0]  flash_arcache;
        wire [2:0]  flash_arprot;
        wire        flash_arvalid;
        wire        flash_arready;
        wire        flash_guard_arready;
        wire [3:0]  flash_rid;
        wire [31:0] flash_rdata;
        wire [1:0]  flash_rresp;
        wire        flash_rlast;
        wire        flash_rvalid;
        wire        flash_rready;
        wire        flash_timeout_sticky;

        assign qspi_timeout_sticky     = flash_timeout_sticky;
        assign qspi_controller_present = 1'b1;

        // The pin-level controller has no flash-ready signal. Bound AXI-side
        // acceptance and response latency here so a wedged controller cannot
        // hold the CPU indefinitely.
        axi_read_timeout_guard #(
            .TIMEOUT_CYCLES (SPI_READ_TIMEOUT_CYCLES)
        ) u_axi_read_timeout_guard (
            .clk             (clk),
            .rst_n           (rst_n),
            .s_arid          (s2_arid),
            .s_araddr        (s2_araddr),
            .s_arlen         (s2_arlen),
            .s_arsize        (s2_arsize),
            .s_arburst       (s2_arburst),
            .s_arlock        (s2_arlock),
            .s_arcache       (s2_arcache),
            .s_arprot        (s2_arprot),
            .s_arvalid       (s2_arvalid && effective_spi_grant),
            .s_arready       (flash_guard_arready),
            .s_rid           (s2_rid),
            .s_rdata         (s2_rdata),
            .s_rresp         (s2_rresp),
            .s_rlast         (s2_rlast),
            .s_rvalid        (s2_rvalid),
            .s_rready        (s2_rready),
            .m_arid          (flash_arid),
            .m_araddr        (flash_araddr),
            .m_arlen         (flash_arlen),
            .m_arsize        (flash_arsize),
            .m_arburst       (flash_arburst),
            .m_arlock        (flash_arlock),
            .m_arcache       (flash_arcache),
            .m_arprot        (flash_arprot),
            .m_arvalid       (flash_arvalid),
            .m_arready       (flash_arready),
            .m_rid           (flash_rid),
            .m_rdata         (flash_rdata),
            .m_rresp         (flash_rresp),
            .m_rlast         (flash_rlast),
            .m_rvalid        (flash_rvalid),
            .m_rready        (flash_rready),
            .timeout_sticky  (flash_timeout_sticky)
        );

        assign s2_arready = effective_spi_grant && flash_guard_arready;
        assign spi_transaction_active = !flash_guard_arready;

        axi_spi_flash u_axi_spi_flash (
            .clk             (clk),
            .rst_n           (rst_n),

            .s_awid          (s2_awid),
            .s_awaddr        (s2_awaddr),
            .s_awlen         (s2_awlen),
            .s_awsize        (s2_awsize),
            .s_awburst       (s2_awburst),
            .s_awlock        (s2_awlock),
            .s_awcache       (s2_awcache),
            .s_awprot        (s2_awprot),
            .s_awvalid       (s2_awvalid),
            .s_awready       (s2_awready),
            .s_wdata         (s2_wdata),
            .s_wstrb         (s2_wstrb),
            .s_wlast         (s2_wlast),
            .s_wvalid        (s2_wvalid),
            .s_wready        (s2_wready),
            .s_bid           (s2_bid),
            .s_bresp         (s2_bresp),
            .s_bvalid        (s2_bvalid),
            .s_bready        (s2_bready),

            .s_arid          (flash_arid),
            .s_araddr        (flash_araddr),
            .s_arlen         (flash_arlen),
            .s_arsize        (flash_arsize),
            .s_arburst       (flash_arburst),
            .s_arlock        (flash_arlock),
            .s_arcache       (flash_arcache),
            .s_arprot        (flash_arprot),
            .s_arvalid       (flash_arvalid),
            .s_arready       (flash_arready),
            .s_rid           (flash_rid),
            .s_rdata         (flash_rdata),
            .s_rresp         (flash_rresp),
            .s_rlast         (flash_rlast),
            .s_rvalid        (flash_rvalid),
            .s_rready        (flash_rready),

            .spi_sclk        (spi_sclk),
            .spi_cs_n        (spi_cs_n),
            .spi_mosi        (spi_mosi),
            .spi_miso        (spi_miso)
        );
    end
    endgenerate

    // The request remains asserted while an AXI flash read is waiting for a
    // grant, while the guard/controller owns an in-flight transaction, or
    // while the physical controller owns the pins. This lets the shared
    // arbiter prevent a command trigger from colliding with XIP.
    assign spi_req = ENABLE_SHARED_ARB &&
                     (s2_arvalid || spi_transaction_active || !spi_cs_n);

    // ---- Product Boot ROM (S4) ----
    // This is a distinct read-only slave so reset fetches cannot alias the
    // writable SRAM/L2 path. ROM_INIT_FILE and +BOOT_ROM_HEX are simulation
    // hooks; the production image is supplied by the mask-ROM flow.
    axi_boot_rom u_axi_boot_rom (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_awid          (s4_awid),
        .s_awaddr        (s4_awaddr),
        .s_awlen         (s4_awlen),
        .s_awsize        (s4_awsize),
        .s_awburst       (s4_awburst),
        .s_awlock        (s4_awlock),
        .s_awcache       (s4_awcache),
        .s_awprot        (s4_awprot),
        .s_awvalid       (s4_awvalid),
        .s_awready       (s4_awready),
        .s_wdata         (s4_wdata),
        .s_wstrb         (s4_wstrb),
        .s_wlast         (s4_wlast),
        .s_wvalid        (s4_wvalid),
        .s_wready        (s4_wready),
        .s_bid           (s4_bid),
        .s_bresp         (s4_bresp),
        .s_bvalid        (s4_bvalid),
        .s_bready        (s4_bready),
        .s_arid          (s4_arid),
        .s_araddr        (s4_araddr),
        .s_arlen         (s4_arlen),
        .s_arsize        (s4_arsize),
        .s_arburst       (s4_arburst),
        .s_arlock        (s4_arlock),
        .s_arcache       (s4_arcache),
        .s_arprot        (s4_arprot),
        .s_arvalid       (s4_arvalid),
        .s_arready       (s4_arready),
        .s_rid           (s4_rid),
        .s_rdata         (s4_rdata),
        .s_rresp         (s4_rresp),
        .s_rlast         (s4_rlast),
        .s_rvalid        (s4_rvalid),
        .s_rready        (s4_rready)
    );

endmodule
