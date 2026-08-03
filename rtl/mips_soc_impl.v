// =============================================================================
// File Name: mips_soc_impl.v
// Design:    MIPS32 SoC integrated implementation
// Author:    Antigravity
// =============================================================================

module mips_soc_impl #(
    parameter ENABLE_EXT_AXI_MASTER = 1'b0,
    parameter ENABLE_APB_FAULT_INJECTOR = 1'b0,
    parameter ENABLE_FLASH_IMAGE_MODEL = 1'b0,
    parameter ENABLE_UART_PINS = 1'b0,
    parameter integer SPI_READ_TIMEOUT_CYCLES = 512,
    parameter ENABLE_QSPI_QUAD = 1'b0,
    parameter ENABLE_DDR4_STATUS = 1'b0
) (
    input  wire clk,
    input  wire rst_n,

    // External GPIO Pins
    inout  wire [31:0] gpio_pins,

    // Product UART/modem pins. Legacy/UVM configurations leave these disabled.
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        uart_cts_n,
    output wire        uart_rts_n,
    input  wire        uart_dsr_n,
    output wire        uart_dtr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    // SPI Flash Interface
    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    inout  wire [3:0]  qspi_io,

    // JTAG Interface
    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo,

    // External UVM AXI Master for Stress Testing
    input  wire [3:0]  ext_awid,
    input  wire [31:0] ext_awaddr,
    input  wire [7:0]  ext_awlen,
    input  wire [2:0]  ext_awsize,
    input  wire [1:0]  ext_awburst,
    input  wire [1:0]  ext_awlock,
    input  wire [3:0]  ext_awcache,
    input  wire [2:0]  ext_awprot,
    input  wire        ext_awvalid,
    output wire        ext_awready,
    input  wire [31:0] ext_wdata,
    input  wire [3:0]  ext_wstrb,
    input  wire        ext_wlast,
    input  wire        ext_wvalid,
    output wire        ext_wready,
    output wire [3:0]  ext_bid,
    output wire [1:0]  ext_bresp,
    output wire        ext_bvalid,
    input  wire        ext_bready,
    input  wire [3:0]  ext_arid,
    input  wire [31:0] ext_araddr,
    input  wire [7:0]  ext_arlen,
    input  wire [2:0]  ext_arsize,
    input  wire [1:0]  ext_arburst,
    input  wire [1:0]  ext_arlock,
    input  wire [3:0]  ext_arcache,
    input  wire [2:0]  ext_arprot,
    input  wire        ext_arvalid,
    output wire        ext_arready,
    output wire [3:0]  ext_rid,
    output wire [31:0] ext_rdata,
    output wire [1:0]  ext_rresp,
    output wire        ext_rlast,
    output wire        ext_rvalid,
    input  wire        ext_rready
);

    // =========================================================================
    // I-Cache AXI4 Master Interface (M0)
    // =========================================================================
    wire [3:0]  m0_awid;
    wire [31:0] m0_awaddr;
    wire [7:0]  m0_awlen;
    wire [2:0]  m0_awsize;
    wire [1:0]  m0_awburst;
    wire [1:0]  m0_awlock;
    wire [3:0]  m0_awcache;
    wire [2:0]  m0_awprot;
    wire        m0_awvalid;
    wire        m0_awready;
    wire [31:0] m0_wdata;
    wire [3:0]  m0_wstrb;
    wire        m0_wlast;
    wire        m0_wvalid;
    wire        m0_wready;
    wire [3:0]  m0_bid;
    wire [1:0]  m0_bresp;
    wire        m0_bvalid;
    wire        m0_bready;
    wire [3:0]  m0_arid;
    wire [31:0] m0_araddr;
    wire [7:0]  m0_arlen;
    wire [2:0]  m0_arsize;
    wire [1:0]  m0_arburst;
    wire [1:0]  m0_arlock;
    wire [3:0]  m0_arcache;
    wire [2:0]  m0_arprot;
    wire        m0_arvalid;
    wire        m0_arready;
    wire [3:0]  m0_rid;
    wire [31:0] m0_rdata;
    wire [1:0]  m0_rresp;
    wire        m0_rlast;
    wire        m0_rvalid;
    wire        m0_rready;

    // =========================================================================
    // D-Cache AXI4 Master Interface (M1)
    // =========================================================================
    wire [3:0]  m1_awid;
    wire [31:0] m1_awaddr;
    wire [7:0]  m1_awlen;
    wire [2:0]  m1_awsize;
    wire [1:0]  m1_awburst;
    wire [1:0]  m1_awlock;
    wire [3:0]  m1_awcache;
    wire [2:0]  m1_awprot;
    wire        m1_awvalid;
    wire        m1_awready;
    wire [31:0] m1_wdata;
    wire [3:0]  m1_wstrb;
    wire        m1_wlast;
    wire        m1_wvalid;
    wire        m1_wready;
    wire [3:0]  m1_bid;
    wire [1:0]  m1_bresp;
    wire        m1_bvalid;
    wire        m1_bready;
    wire [3:0]  m1_arid;
    wire [31:0] m1_araddr;
    wire [7:0]  m1_arlen;
    wire [2:0]  m1_arsize;
    wire [1:0]  m1_arburst;
    wire [1:0]  m1_arlock;
    wire [3:0]  m1_arcache;
    wire [2:0]  m1_arprot;
    wire        m1_arvalid;
    wire        m1_arready;
    wire [3:0]  m1_rid;
    wire [31:0] m1_rdata;
    wire [1:0]  m1_rresp;
    wire        m1_rlast;
    wire        m1_rvalid;
    wire        m1_rready;

    // =========================================================================
    // SRAM AXI4 Slave Interface (S0)
    // =========================================================================
    wire [3:0]  s0_awid;
    wire [31:0] s0_awaddr;
    wire [7:0]  s0_awlen;
    wire [2:0]  s0_awsize;
    wire [1:0]  s0_awburst;
    wire [1:0]  s0_awlock;
    wire [3:0]  s0_awcache;
    wire [2:0]  s0_awprot;
    wire        s0_awvalid;
    wire        s0_awready;
    wire [31:0] s0_wdata;
    wire [3:0]  s0_wstrb;
    wire        s0_wlast;
    wire        s0_wvalid;
    wire        s0_wready;
    wire [3:0]  s0_bid;
    wire [1:0]  s0_bresp;
    wire        s0_bvalid;
    wire        s0_bready;
    wire [3:0]  s0_arid;
    wire [31:0] s0_araddr;
    wire [7:0]  s0_arlen;
    wire [2:0]  s0_arsize;
    wire [1:0]  s0_arburst;
    wire [1:0]  s0_arlock;
    wire [3:0]  s0_arcache;
    wire [2:0]  s0_arprot;
    wire        s0_arvalid;
    wire        s0_arready;
    wire [3:0]  s0_rid;
    wire [31:0] s0_rdata;
    wire [1:0]  s0_rresp;
    wire        s0_rlast;
    wire        s0_rvalid;
    wire        s0_rready;

    // =========================================================================
    // DMA AXI4 Master Interface (M2)
    // =========================================================================
    wire [3:0]  m2_awid;
    wire [31:0] m2_awaddr;
    wire [7:0]  m2_awlen;
    wire [2:0]  m2_awsize;
    wire [1:0]  m2_awburst;
    wire [1:0]  m2_awlock;
    wire [3:0]  m2_awcache;
    wire [2:0]  m2_awprot;
    wire        m2_awvalid;
    wire        m2_awready;
    wire [31:0] m2_wdata;
    wire [3:0]  m2_wstrb;
    wire        m2_wlast;
    wire        m2_wvalid;
    wire        m2_wready;
    wire [3:0]  m2_bid;
    wire [1:0]  m2_bresp;
    wire        m2_bvalid;
    wire        m2_bready;
    wire [3:0]  m2_arid;
    wire [31:0] m2_araddr;
    wire [7:0]  m2_arlen;
    wire [2:0]  m2_arsize;
    wire [1:0]  m2_arburst;
    wire [1:0]  m2_arlock;
    wire [3:0]  m2_arcache;
    wire [2:0]  m2_arprot;
    wire        m2_arvalid;
    wire        m2_arready;
    wire [3:0]  m2_rid;
    wire [31:0] m2_rdata;
    wire [1:0]  m2_rresp;
    wire        m2_rlast;
    wire        m2_rvalid;
    wire        m2_rready;

    // JTAG AXI Master
    wire [3:0]  jtag_awid;
    wire [31:0] jtag_awaddr;
    wire [7:0]  jtag_awlen;
    wire [2:0]  jtag_awsize;
    wire [1:0]  jtag_awburst;
    wire [1:0]  jtag_awlock;
    wire [3:0]  jtag_awcache;
    wire [2:0]  jtag_awprot;
    wire        jtag_awvalid;
    wire        jtag_awready;
    wire [31:0] jtag_wdata;
    wire [3:0]  jtag_wstrb;
    wire        jtag_wlast;
    wire        jtag_wvalid;
    wire        jtag_wready;
    wire [3:0]  jtag_bid;
    wire [1:0]  jtag_bresp;
    wire        jtag_bvalid;
    wire        jtag_bready;
    wire [3:0]  jtag_arid;
    wire [31:0] jtag_araddr;
    wire [7:0]  jtag_arlen;
    wire [2:0]  jtag_arsize;
    wire [1:0]  jtag_arburst;
    wire [1:0]  jtag_arlock;
    wire [3:0]  jtag_arcache;
    wire [2:0]  jtag_arprot;
    wire        jtag_arvalid;
    wire        jtag_arready;
    wire [3:0]  jtag_rid;
    wire [31:0] jtag_rdata;
    wire [1:0]  jtag_rresp;
    wire        jtag_rlast;
    wire        jtag_rvalid;
    wire        jtag_rready;

    // =========================================================================
    // APB AXI4 Slave Interface (S1)
    // =========================================================================
    wire [3:0]  s1_awid;
    wire [31:0] s1_awaddr;
    wire [7:0]  s1_awlen;
    wire [2:0]  s1_awsize;
    wire [1:0]  s1_awburst;
    wire [1:0]  s1_awlock;
    wire [3:0]  s1_awcache;
    wire [2:0]  s1_awprot;
    wire        s1_awvalid;
    wire        s1_awready;
    wire [31:0] s1_wdata;
    wire [3:0]  s1_wstrb;
    wire        s1_wlast;
    wire        s1_wvalid;
    wire        s1_wready;
    wire [3:0]  s1_bid;
    wire [1:0]  s1_bresp;
    wire        s1_bvalid;
    wire        s1_bready;
    wire [3:0]  s1_arid;
    wire [31:0] s1_araddr;
    wire [7:0]  s1_arlen;
    wire [2:0]  s1_arsize;
    wire [1:0]  s1_arburst;
    wire [1:0]  s1_arlock;
    wire [3:0]  s1_arcache;
    wire [2:0]  s1_arprot;
    wire        s1_arvalid;
    wire        s1_arready;
    wire [3:0]  s1_rid;
    wire [31:0] s1_rdata;
    wire [1:0]  s1_rresp;
    wire        s1_rlast;
    wire        s1_rvalid;
    wire        s1_rready;

    // =========================================================================
    // AXI Slave 2: SPI Flash Controller (0x1000_0000 - 0x1FFF_FFFF)
    // =========================================================================

    // SPI Flash AXI Interface
    wire [3:0]  s2_awid;
    wire [31:0] s2_awaddr;
    wire [7:0]  s2_awlen;
    wire [2:0]  s2_awsize;
    wire [1:0]  s2_awburst;
    wire [1:0]  s2_awlock;
    wire [3:0]  s2_awcache;
    wire [2:0]  s2_awprot;
    wire        s2_awvalid;
    wire        s2_awready;
    wire [31:0] s2_wdata;
    wire [3:0]  s2_wstrb;
    wire        s2_wlast;
    wire        s2_wvalid;
    wire        s2_wready;
    wire [3:0]  s2_bid;
    wire [1:0]  s2_bresp;
    wire        s2_bvalid;
    wire        s2_bready;
    wire [3:0]  s2_arid;
    wire [31:0] s2_araddr;
    wire [7:0]  s2_arlen;
    wire [2:0]  s2_arsize;
    wire [1:0]  s2_arburst;
    wire [1:0]  s2_arlock;
    wire [3:0]  s2_arcache;
    wire [2:0]  s2_arprot;
    wire        s2_arvalid;
    wire        s2_arready;
    wire [3:0]  s2_rid;
    wire [31:0] s2_rdata;
    wire [1:0]  s2_rresp;
    wire        s2_rlast;
    wire        s2_rvalid;
    wire        s2_rready;

    // =========================================================================
    // AXI Slave 3: DDR window (0x0800_0000 - 0x0FFF_FFFF), Phase C.4
    // Behavioral capacity placeholder only (rtl/perips/axi_ddr_behavioral.v).
    // =========================================================================
    wire [3:0]  s3_awid;
    wire [31:0] s3_awaddr;
    wire [7:0]  s3_awlen;
    wire [2:0]  s3_awsize;
    wire [1:0]  s3_awburst;
    wire [1:0]  s3_awlock;
    wire [3:0]  s3_awcache;
    wire [2:0]  s3_awprot;
    wire        s3_awvalid;
    wire        s3_awready;
    wire [31:0] s3_wdata;
    wire [3:0]  s3_wstrb;
    wire        s3_wlast;
    wire        s3_wvalid;
    wire        s3_wready;
    wire [3:0]  s3_bid;
    wire [1:0]  s3_bresp;
    wire        s3_bvalid;
    wire        s3_bready;
    wire [3:0]  s3_arid;
    wire [31:0] s3_araddr;
    wire [7:0]  s3_arlen;
    wire [2:0]  s3_arsize;
    wire [1:0]  s3_arburst;
    wire [1:0]  s3_arlock;
    wire [3:0]  s3_arcache;
    wire [2:0]  s3_arprot;
    wire        s3_arvalid;
    wire        s3_arready;
    wire [3:0]  s3_rid;
    wire [31:0] s3_rdata;
    wire [1:0]  s3_rresp;
    wire        s3_rlast;
    wire        s3_rvalid;
    wire        s3_rready;

    // =========================================================================
    // AXI Slave 4: Product Boot ROM (0x1FC0_0000 - 0x1FC0_FFFF)
    // =========================================================================
    wire [3:0]  s4_awid;
    wire [31:0] s4_awaddr;
    wire [7:0]  s4_awlen;
    wire [2:0]  s4_awsize;
    wire [1:0]  s4_awburst;
    wire [1:0]  s4_awlock;
    wire [3:0]  s4_awcache;
    wire [2:0]  s4_awprot;
    wire        s4_awvalid;
    wire        s4_awready;
    wire [31:0] s4_wdata;
    wire [3:0]  s4_wstrb;
    wire        s4_wlast;
    wire        s4_wvalid;
    wire        s4_wready;
    wire [3:0]  s4_bid;
    wire [1:0]  s4_bresp;
    wire        s4_bvalid;
    wire        s4_bready;
    wire [3:0]  s4_arid;
    wire [31:0] s4_araddr;
    wire [7:0]  s4_arlen;
    wire [2:0]  s4_arsize;
    wire [1:0]  s4_arburst;
    wire [1:0]  s4_arlock;
    wire [3:0]  s4_arcache;
    wire [2:0]  s4_arprot;
    wire        s4_arvalid;
    wire        s4_arready;
    wire [3:0]  s4_rid;
    wire [31:0] s4_rdata;
    wire [1:0]  s4_rresp;
    wire        s4_rlast;
    wire        s4_rvalid;
    wire        s4_rready;

    wire        cpu_int;
    wire        wdt_reset;
    wire        qspi_timeout_sticky;
    wire        ddr4_controller_present, ddr4_init_done, ddr4_training_done, ddr4_fatal_error;
    wire [15:0] ddr4_error_code;
    wire        qspi_controller_present;
    wire        qspi_cmd_sclk;
    wire        qspi_cmd_cs_n;
    wire        qspi_cmd_mosi;
    wire        qspi_cmd_active;
    wire        qspi_cmd_req;
    wire        qspi_cmd_grant;
    wire        mem_spi_sclk;
    wire        mem_spi_cs_n;
    wire        mem_spi_mosi;
    wire        mem_spi_req;
    wire        mem_spi_grant;
    wire        qspi_shared_pin_conflict;
    wire [3:0]  qspi_cmd_io_o;
    wire [3:0]  qspi_cmd_io_oe;
    wire [3:0]  mem_qspi_io_o;
    wire [3:0]  mem_qspi_io_oe;
    wire [3:0]  arb_qspi_io_o;
    wire [3:0]  arb_qspi_io_oe;
    wire        arb_spi_sclk;
    wire        arb_spi_cs_n;
    wire        arb_spi_mosi;
    wire        soc_rst_n;
    assign soc_rst_n = rst_n & ~wdt_reset;

    // Command and AXI XIP share one physical SPI pin boundary. The arbiter
    // holds an owner across the transaction and blocks a new AXI AR while a
    // command trigger is waiting for the bus.
    qspi_shared_pin_arbiter u_qspi_shared_pin_arbiter (
        .clk        (clk),
        .rst_n      (soc_rst_n),
        .cmd_req    (qspi_cmd_req),
        .cmd_active (qspi_cmd_active),
        .cmd_sclk   (qspi_cmd_sclk),
        .cmd_cs_n   (qspi_cmd_cs_n),
        .cmd_mosi   (qspi_cmd_mosi),
        .mem_req    (mem_spi_req),
        .mem_active (!mem_spi_cs_n),
        .mem_sclk   (mem_spi_sclk),
        .mem_cs_n   (mem_spi_cs_n),
        .mem_mosi   (mem_spi_mosi),
        .cmd_grant  (qspi_cmd_grant),
        .mem_grant  (mem_spi_grant),
        .spi_sclk   (arb_spi_sclk),
        .spi_cs_n   (arb_spi_cs_n),
        .spi_mosi   (arb_spi_mosi),
        .busy       (),
        .conflict   (qspi_shared_pin_conflict)
    );

    qspi_soc_pad_mux #(
        .ENABLE_QUAD_IO (ENABLE_QSPI_QUAD)
    ) u_qspi_soc_pad_mux (
        .cmd_grant  (qspi_cmd_grant),
        .cmd_sclk   (qspi_cmd_sclk),
        .cmd_cs_n   (qspi_cmd_cs_n),
        .cmd_io_o   (qspi_cmd_io_o),
        .cmd_io_oe  (qspi_cmd_io_oe),
        .mem_grant  (mem_spi_grant),
        .mem_sclk   (mem_spi_sclk),
        .mem_cs_n   (mem_spi_cs_n),
        .mem_mosi   (mem_spi_mosi),
        .mem_io_o   (mem_qspi_io_o),
        .mem_io_oe  (mem_qspi_io_oe),
        .spi_sclk   (spi_sclk),
        .spi_cs_n   (spi_cs_n),
        .spi_mosi   (spi_mosi),
        .qspi_io_o  (arb_qspi_io_o),
        .qspi_io_oe (arb_qspi_io_oe),
        .qspi_io    (qspi_io)
    );

    // =========================================================================
    // Instantiations
    // =========================================================================

    soc_core_subsystem u_core_subsystem (
        .clk             (clk),
        .rst_n           (soc_rst_n),
        .cpu_int         (cpu_int),

        .inst_awid       (m0_awid),
        .inst_awaddr     (m0_awaddr),
        .inst_awlen      (m0_awlen),
        .inst_awsize     (m0_awsize),
        .inst_awburst    (m0_awburst),
        .inst_awlock     (m0_awlock),
        .inst_awcache    (m0_awcache),
        .inst_awprot     (m0_awprot),
        .inst_awvalid    (m0_awvalid),
        .inst_awready    (m0_awready),
        .inst_wdata      (m0_wdata),
        .inst_wstrb      (m0_wstrb),
        .inst_wlast      (m0_wlast),
        .inst_wvalid     (m0_wvalid),
        .inst_wready     (m0_wready),
        .inst_bid        (m0_bid),
        .inst_bresp      (m0_bresp),
        .inst_bvalid     (m0_bvalid),
        .inst_bready     (m0_bready),
        .inst_arid       (m0_arid),
        .inst_araddr     (m0_araddr),
        .inst_arlen      (m0_arlen),
        .inst_arsize     (m0_arsize),
        .inst_arburst    (m0_arburst),
        .inst_arlock     (m0_arlock),
        .inst_arcache    (m0_arcache),
        .inst_arprot     (m0_arprot),
        .inst_arvalid    (m0_arvalid),
        .inst_arready    (m0_arready),
        .inst_rid        (m0_rid),
        .inst_rdata      (m0_rdata),
        .inst_rresp      (m0_rresp),
        .inst_rlast      (m0_rlast),
        .inst_rvalid     (m0_rvalid),
        .inst_rready     (m0_rready),

        .data_awid       (m1_awid),
        .data_awaddr     (m1_awaddr),
        .data_awlen      (m1_awlen),
        .data_awsize     (m1_awsize),
        .data_awburst    (m1_awburst),
        .data_awlock     (m1_awlock),
        .data_awcache    (m1_awcache),
        .data_awprot     (m1_awprot),
        .data_awvalid    (m1_awvalid),
        .data_awready    (m1_awready),
        .data_wdata      (m1_wdata),
        .data_wstrb      (m1_wstrb),
        .data_wlast      (m1_wlast),
        .data_wvalid     (m1_wvalid),
        .data_wready     (m1_wready),
        .data_bid        (m1_bid),
        .data_bresp      (m1_bresp),
        .data_bvalid     (m1_bvalid),
        .data_bready     (m1_bready),
        .data_arid       (m1_arid),
        .data_araddr     (m1_araddr),
        .data_arlen      (m1_arlen),
        .data_arsize     (m1_arsize),
        .data_arburst    (m1_arburst),
        .data_arlock     (m1_arlock),
        .data_arcache    (m1_arcache),
        .data_arprot     (m1_arprot),
        .data_arvalid    (m1_arvalid),
        .data_arready    (m1_arready),
        .data_rid        (m1_rid),
        .data_rdata      (m1_rdata),
        .data_rresp      (m1_rresp),
        .data_rlast      (m1_rlast),
        .data_rvalid     (m1_rvalid),
        .data_rready     (m1_rready),

        .debug_stall     (),
        .debug_flush     ()
    );

    soc_fabric #(
        .ENABLE_EXT_AXI_MASTER (ENABLE_EXT_AXI_MASTER)
    ) u_soc_fabric (
        .clk          (clk),
        .rst_n        (soc_rst_n),
        .m0_arid      (m0_arid),
        .m0_araddr    (m0_araddr),
        .m0_arlen     (m0_arlen),
        .m0_arsize    (m0_arsize),
        .m0_arburst   (m0_arburst),
        .m0_arlock    (m0_arlock),
        .m0_arcache   (m0_arcache),
        .m0_arprot    (m0_arprot),
        .m0_arvalid   (m0_arvalid),
        .m0_rready    (m0_rready),
        .m0_arready   (m0_arready),
        .m0_rid       (m0_rid),
        .m0_rdata     (m0_rdata),
        .m0_rresp     (m0_rresp),
        .m0_rlast     (m0_rlast),
        .m0_rvalid    (m0_rvalid),
        .m1_awid      (m1_awid),
        .m1_awaddr    (m1_awaddr),
        .m1_awlen     (m1_awlen),
        .m1_awsize    (m1_awsize),
        .m1_awburst   (m1_awburst),
        .m1_awlock    (m1_awlock),
        .m1_awcache   (m1_awcache),
        .m1_awprot    (m1_awprot),
        .m1_awvalid   (m1_awvalid),
        .m1_wdata     (m1_wdata),
        .m1_wstrb     (m1_wstrb),
        .m1_wlast     (m1_wlast),
        .m1_wvalid    (m1_wvalid),
        .m1_bready    (m1_bready),
        .m1_arid      (m1_arid),
        .m1_araddr    (m1_araddr),
        .m1_arlen     (m1_arlen),
        .m1_arsize    (m1_arsize),
        .m1_arburst   (m1_arburst),
        .m1_arlock    (m1_arlock),
        .m1_arcache   (m1_arcache),
        .m1_arprot    (m1_arprot),
        .m1_arvalid   (m1_arvalid),
        .m1_rready    (m1_rready),
        .m1_awready   (m1_awready),
        .m1_wready    (m1_wready),
        .m1_bid       (m1_bid),
        .m1_bresp     (m1_bresp),
        .m1_bvalid    (m1_bvalid),
        .m1_arready   (m1_arready),
        .m1_rid       (m1_rid),
        .m1_rdata     (m1_rdata),
        .m1_rresp     (m1_rresp),
        .m1_rlast     (m1_rlast),
        .m1_rvalid    (m1_rvalid),
        .m2_awid      (m2_awid),
        .m2_awaddr    (m2_awaddr),
        .m2_awlen     (m2_awlen),
        .m2_awsize    (m2_awsize),
        .m2_awburst   (m2_awburst),
        .m2_awlock    (m2_awlock),
        .m2_awcache   (m2_awcache),
        .m2_awprot    (m2_awprot),
        .m2_awvalid   (m2_awvalid),
        .m2_wdata     (m2_wdata),
        .m2_wstrb     (m2_wstrb),
        .m2_wlast     (m2_wlast),
        .m2_wvalid    (m2_wvalid),
        .m2_bready    (m2_bready),
        .m2_arid      (m2_arid),
        .m2_araddr    (m2_araddr),
        .m2_arlen     (m2_arlen),
        .m2_arsize    (m2_arsize),
        .m2_arburst   (m2_arburst),
        .m2_arlock    (m2_arlock),
        .m2_arcache   (m2_arcache),
        .m2_arprot    (m2_arprot),
        .m2_arvalid   (m2_arvalid),
        .m2_rready    (m2_rready),
        .m2_awready   (m2_awready),
        .m2_wready    (m2_wready),
        .m2_bid       (m2_bid),
        .m2_bresp     (m2_bresp),
        .m2_bvalid    (m2_bvalid),
        .m2_arready   (m2_arready),
        .m2_rid       (m2_rid),
        .m2_rdata     (m2_rdata),
        .m2_rresp     (m2_rresp),
        .m2_rlast     (m2_rlast),
        .m2_rvalid    (m2_rvalid),
        .jtag_awid    (jtag_awid),
        .jtag_awaddr  (jtag_awaddr),
        .jtag_awlen   (jtag_awlen),
        .jtag_awsize  (jtag_awsize),
        .jtag_awburst (jtag_awburst),
        .jtag_awlock  (jtag_awlock),
        .jtag_awcache (jtag_awcache),
        .jtag_awprot  (jtag_awprot),
        .jtag_awvalid (jtag_awvalid),
        .jtag_wdata   (jtag_wdata),
        .jtag_wstrb   (jtag_wstrb),
        .jtag_wlast   (jtag_wlast),
        .jtag_wvalid  (jtag_wvalid),
        .jtag_bready  (jtag_bready),
        .jtag_arid    (jtag_arid),
        .jtag_araddr  (jtag_araddr),
        .jtag_arlen   (jtag_arlen),
        .jtag_arsize  (jtag_arsize),
        .jtag_arburst (jtag_arburst),
        .jtag_arlock  (jtag_arlock),
        .jtag_arcache (jtag_arcache),
        .jtag_arprot  (jtag_arprot),
        .jtag_arvalid (jtag_arvalid),
        .jtag_rready  (jtag_rready),
        .jtag_awready (jtag_awready),
        .jtag_wready  (jtag_wready),
        .jtag_bid     (jtag_bid),
        .jtag_bresp   (jtag_bresp),
        .jtag_bvalid  (jtag_bvalid),
        .jtag_arready (jtag_arready),
        .jtag_rid     (jtag_rid),
        .jtag_rdata   (jtag_rdata),
        .jtag_rresp   (jtag_rresp),
        .jtag_rlast   (jtag_rlast),
        .jtag_rvalid  (jtag_rvalid),
        .ext_awid     (ext_awid),
        .ext_awaddr   (ext_awaddr),
        .ext_awlen    (ext_awlen),
        .ext_awsize   (ext_awsize),
        .ext_awburst  (ext_awburst),
        .ext_awlock   (ext_awlock),
        .ext_awcache  (ext_awcache),
        .ext_awprot   (ext_awprot),
        .ext_awvalid  (ext_awvalid),
        .ext_wdata    (ext_wdata),
        .ext_wstrb    (ext_wstrb),
        .ext_wlast    (ext_wlast),
        .ext_wvalid   (ext_wvalid),
        .ext_bready   (ext_bready),
        .ext_arid     (ext_arid),
        .ext_araddr   (ext_araddr),
        .ext_arlen    (ext_arlen),
        .ext_arsize   (ext_arsize),
        .ext_arburst  (ext_arburst),
        .ext_arlock   (ext_arlock),
        .ext_arcache  (ext_arcache),
        .ext_arprot   (ext_arprot),
        .ext_arvalid  (ext_arvalid),
        .ext_rready   (ext_rready),
        .ext_awready  (ext_awready),
        .ext_wready   (ext_wready),
        .ext_bid      (ext_bid),
        .ext_bresp    (ext_bresp),
        .ext_bvalid   (ext_bvalid),
        .ext_arready  (ext_arready),
        .ext_rid      (ext_rid),
        .ext_rdata    (ext_rdata),
        .ext_rresp    (ext_rresp),
        .ext_rlast    (ext_rlast),
        .ext_rvalid   (ext_rvalid),
        .s0_awid      (s0_awid),
        .s0_awaddr    (s0_awaddr),
        .s0_awlen     (s0_awlen),
        .s0_awsize    (s0_awsize),
        .s0_awburst   (s0_awburst),
        .s0_awlock    (s0_awlock),
        .s0_awcache   (s0_awcache),
        .s0_awprot    (s0_awprot),
        .s0_awvalid   (s0_awvalid),
        .s0_wdata     (s0_wdata),
        .s0_wstrb     (s0_wstrb),
        .s0_wlast     (s0_wlast),
        .s0_wvalid    (s0_wvalid),
        .s0_bready    (s0_bready),
        .s0_arid      (s0_arid),
        .s0_araddr    (s0_araddr),
        .s0_arlen     (s0_arlen),
        .s0_arsize    (s0_arsize),
        .s0_arburst   (s0_arburst),
        .s0_arlock    (s0_arlock),
        .s0_arcache   (s0_arcache),
        .s0_arprot    (s0_arprot),
        .s0_arvalid   (s0_arvalid),
        .s0_rready    (s0_rready),
        .s0_awready   (s0_awready),
        .s0_wready    (s0_wready),
        .s0_bid       (s0_bid),
        .s0_bresp     (s0_bresp),
        .s0_bvalid    (s0_bvalid),
        .s0_arready   (s0_arready),
        .s0_rid       (s0_rid),
        .s0_rdata     (s0_rdata),
        .s0_rresp     (s0_rresp),
        .s0_rlast     (s0_rlast),
        .s0_rvalid    (s0_rvalid),
        .s1_awid      (s1_awid),
        .s1_awaddr    (s1_awaddr),
        .s1_awlen     (s1_awlen),
        .s1_awsize    (s1_awsize),
        .s1_awburst   (s1_awburst),
        .s1_awlock    (s1_awlock),
        .s1_awcache   (s1_awcache),
        .s1_awprot    (s1_awprot),
        .s1_awvalid   (s1_awvalid),
        .s1_wdata     (s1_wdata),
        .s1_wstrb     (s1_wstrb),
        .s1_wlast     (s1_wlast),
        .s1_wvalid    (s1_wvalid),
        .s1_bready    (s1_bready),
        .s1_arid      (s1_arid),
        .s1_araddr    (s1_araddr),
        .s1_arlen     (s1_arlen),
        .s1_arsize    (s1_arsize),
        .s1_arburst   (s1_arburst),
        .s1_arlock    (s1_arlock),
        .s1_arcache   (s1_arcache),
        .s1_arprot    (s1_arprot),
        .s1_arvalid   (s1_arvalid),
        .s1_rready    (s1_rready),
        .s1_awready   (s1_awready),
        .s1_wready    (s1_wready),
        .s1_bid       (s1_bid),
        .s1_bresp     (s1_bresp),
        .s1_bvalid    (s1_bvalid),
        .s1_arready   (s1_arready),
        .s1_rid       (s1_rid),
        .s1_rdata     (s1_rdata),
        .s1_rresp     (s1_rresp),
        .s1_rlast     (s1_rlast),
        .s1_rvalid    (s1_rvalid),
        .s2_awid      (s2_awid),
        .s2_awaddr    (s2_awaddr),
        .s2_awlen     (s2_awlen),
        .s2_awsize    (s2_awsize),
        .s2_awburst   (s2_awburst),
        .s2_awlock    (s2_awlock),
        .s2_awcache   (s2_awcache),
        .s2_awprot    (s2_awprot),
        .s2_awvalid   (s2_awvalid),
        .s2_wdata     (s2_wdata),
        .s2_wstrb     (s2_wstrb),
        .s2_wlast     (s2_wlast),
        .s2_wvalid    (s2_wvalid),
        .s2_bready    (s2_bready),
        .s2_arid      (s2_arid),
        .s2_araddr    (s2_araddr),
        .s2_arlen     (s2_arlen),
        .s2_arsize    (s2_arsize),
        .s2_arburst   (s2_arburst),
        .s2_arlock    (s2_arlock),
        .s2_arcache   (s2_arcache),
        .s2_arprot    (s2_arprot),
        .s2_arvalid   (s2_arvalid),
        .s2_rready    (s2_rready),
        .s2_awready   (s2_awready),
        .s2_wready    (s2_wready),
        .s2_bid       (s2_bid),
        .s2_bresp     (s2_bresp),
        .s2_bvalid    (s2_bvalid),
        .s2_arready   (s2_arready),
        .s2_rid       (s2_rid),
        .s2_rdata     (s2_rdata),
        .s2_rresp     (s2_rresp),
        .s2_rlast     (s2_rlast),
        .s2_rvalid    (s2_rvalid),
        .s3_awid      (s3_awid),
        .s3_awaddr    (s3_awaddr),
        .s3_awlen     (s3_awlen),
        .s3_awsize    (s3_awsize),
        .s3_awburst   (s3_awburst),
        .s3_awlock    (s3_awlock),
        .s3_awcache   (s3_awcache),
        .s3_awprot    (s3_awprot),
        .s3_awvalid   (s3_awvalid),
        .s3_wdata     (s3_wdata),
        .s3_wstrb     (s3_wstrb),
        .s3_wlast     (s3_wlast),
        .s3_wvalid    (s3_wvalid),
        .s3_bready    (s3_bready),
        .s3_arid      (s3_arid),
        .s3_araddr    (s3_araddr),
        .s3_arlen     (s3_arlen),
        .s3_arsize    (s3_arsize),
        .s3_arburst   (s3_arburst),
        .s3_arlock    (s3_arlock),
        .s3_arcache   (s3_arcache),
        .s3_arprot    (s3_arprot),
        .s3_arvalid   (s3_arvalid),
        .s3_rready    (s3_rready),
        .s3_awready   (s3_awready),
        .s3_wready    (s3_wready),
        .s3_bid       (s3_bid),
        .s3_bresp     (s3_bresp),
        .s3_bvalid    (s3_bvalid),
        .s3_arready   (s3_arready),
        .s3_rid       (s3_rid),
        .s3_rdata     (s3_rdata),
        .s3_rresp     (s3_rresp),
        .s3_rlast     (s3_rlast),
        .s3_rvalid    (s3_rvalid),
        .s4_awid      (s4_awid),
        .s4_awaddr    (s4_awaddr),
        .s4_awlen     (s4_awlen),
        .s4_awsize    (s4_awsize),
        .s4_awburst   (s4_awburst),
        .s4_awlock    (s4_awlock),
        .s4_awcache   (s4_awcache),
        .s4_awprot    (s4_awprot),
        .s4_awvalid   (s4_awvalid),
        .s4_wdata     (s4_wdata),
        .s4_wstrb     (s4_wstrb),
        .s4_wlast     (s4_wlast),
        .s4_wvalid    (s4_wvalid),
        .s4_bready    (s4_bready),
        .s4_arid      (s4_arid),
        .s4_araddr    (s4_araddr),
        .s4_arlen     (s4_arlen),
        .s4_arsize    (s4_arsize),
        .s4_arburst   (s4_arburst),
        .s4_arlock    (s4_arlock),
        .s4_arcache   (s4_arcache),
        .s4_arprot    (s4_arprot),
        .s4_arvalid   (s4_arvalid),
        .s4_rready    (s4_rready),
        .s4_awready   (s4_awready),
        .s4_wready    (s4_wready),
        .s4_bid       (s4_bid),
        .s4_bresp     (s4_bresp),
        .s4_bvalid    (s4_bvalid),
        .s4_arready   (s4_arready),
        .s4_rid       (s4_rid),
        .s4_rdata     (s4_rdata),
        .s4_rresp     (s4_rresp),
        .s4_rlast     (s4_rlast),
        .s4_rvalid    (s4_rvalid)
    );

    soc_memory_subsystem #(
        .ENABLE_FLASH_IMAGE_MODEL (ENABLE_FLASH_IMAGE_MODEL),
        .SRAM_DEPTH_WORDS         (32768),
        .SPI_READ_TIMEOUT_CYCLES  (SPI_READ_TIMEOUT_CYCLES),
        .ENABLE_SHARED_ARB        (1'b1),
        .ENABLE_QSPI_QUAD         (ENABLE_QSPI_QUAD)
        ,.ENABLE_DDR4_STATUS      (ENABLE_DDR4_STATUS)
    ) u_memory_subsystem (
        .clk          (clk),
        .rst_n        (soc_rst_n),
        .spi_sclk     (mem_spi_sclk),
        .spi_cs_n     (mem_spi_cs_n),
        .spi_mosi     (mem_spi_mosi),
        .spi_miso     (spi_miso),
        .qspi_io_i    (qspi_io),
        .qspi_io_o    (mem_qspi_io_o),
        .qspi_io_oe   (mem_qspi_io_oe),
        .spi_arb_grant          (mem_spi_grant),
        .spi_req                (mem_spi_req),
        .qspi_timeout_sticky     (qspi_timeout_sticky),
        .qspi_controller_present (qspi_controller_present),
        .ddr4_controller_present (ddr4_controller_present),
        .ddr4_init_done          (ddr4_init_done),
        .ddr4_training_done      (ddr4_training_done),
        .ddr4_fatal_error        (ddr4_fatal_error),
        .ddr4_error_code         (ddr4_error_code),

        .s0_awid      (s0_awid),
        .s0_awaddr    (s0_awaddr),
        .s0_awlen     (s0_awlen),
        .s0_awsize    (s0_awsize),
        .s0_awburst   (s0_awburst),
        .s0_awlock    (s0_awlock),
        .s0_awcache   (s0_awcache),
        .s0_awprot    (s0_awprot),
        .s0_awvalid   (s0_awvalid),
        .s0_awready   (s0_awready),
        .s0_wdata     (s0_wdata),
        .s0_wstrb     (s0_wstrb),
        .s0_wlast     (s0_wlast),
        .s0_wvalid    (s0_wvalid),
        .s0_wready    (s0_wready),
        .s0_bid       (s0_bid),
        .s0_bresp     (s0_bresp),
        .s0_bvalid    (s0_bvalid),
        .s0_bready    (s0_bready),
        .s0_arid      (s0_arid),
        .s0_araddr    (s0_araddr),
        .s0_arlen     (s0_arlen),
        .s0_arsize    (s0_arsize),
        .s0_arburst   (s0_arburst),
        .s0_arlock    (s0_arlock),
        .s0_arcache   (s0_arcache),
        .s0_arprot    (s0_arprot),
        .s0_arvalid   (s0_arvalid),
        .s0_arready   (s0_arready),
        .s0_rid       (s0_rid),
        .s0_rdata     (s0_rdata),
        .s0_rresp     (s0_rresp),
        .s0_rlast     (s0_rlast),
        .s0_rvalid    (s0_rvalid),
        .s0_rready    (s0_rready),

        .s2_awid      (s2_awid),
        .s2_awaddr    (s2_awaddr),
        .s2_awlen     (s2_awlen),
        .s2_awsize    (s2_awsize),
        .s2_awburst   (s2_awburst),
        .s2_awlock    (s2_awlock),
        .s2_awcache   (s2_awcache),
        .s2_awprot    (s2_awprot),
        .s2_awvalid   (s2_awvalid),
        .s2_awready   (s2_awready),
        .s2_wdata     (s2_wdata),
        .s2_wstrb     (s2_wstrb),
        .s2_wlast     (s2_wlast),
        .s2_wvalid    (s2_wvalid),
        .s2_wready    (s2_wready),
        .s2_bid       (s2_bid),
        .s2_bresp     (s2_bresp),
        .s2_bvalid    (s2_bvalid),
        .s2_bready    (s2_bready),
        .s2_arid      (s2_arid),
        .s2_araddr    (s2_araddr),
        .s2_arlen     (s2_arlen),
        .s2_arsize    (s2_arsize),
        .s2_arburst   (s2_arburst),
        .s2_arlock    (s2_arlock),
        .s2_arcache   (s2_arcache),
        .s2_arprot    (s2_arprot),
        .s2_arvalid   (s2_arvalid),
        .s2_arready   (s2_arready),
        .s2_rid       (s2_rid),
        .s2_rdata     (s2_rdata),
        .s2_rresp     (s2_rresp),
        .s2_rlast     (s2_rlast),
        .s2_rvalid    (s2_rvalid),
        .s2_rready    (s2_rready),

        .s3_awid      (s3_awid),
        .s3_awaddr    (s3_awaddr),
        .s3_awlen     (s3_awlen),
        .s3_awsize    (s3_awsize),
        .s3_awburst   (s3_awburst),
        .s3_awlock    (s3_awlock),
        .s3_awcache   (s3_awcache),
        .s3_awprot    (s3_awprot),
        .s3_awvalid   (s3_awvalid),
        .s3_awready   (s3_awready),
        .s3_wdata     (s3_wdata),
        .s3_wstrb     (s3_wstrb),
        .s3_wlast     (s3_wlast),
        .s3_wvalid    (s3_wvalid),
        .s3_wready    (s3_wready),
        .s3_bid       (s3_bid),
        .s3_bresp     (s3_bresp),
        .s3_bvalid    (s3_bvalid),
        .s3_bready    (s3_bready),
        .s3_arid      (s3_arid),
        .s3_araddr    (s3_araddr),
        .s3_arlen     (s3_arlen),
        .s3_arsize    (s3_arsize),
        .s3_arburst   (s3_arburst),
        .s3_arlock    (s3_arlock),
        .s3_arcache   (s3_arcache),
        .s3_arprot    (s3_arprot),
        .s3_arvalid   (s3_arvalid),
        .s3_arready   (s3_arready),
        .s3_rid       (s3_rid),
        .s3_rdata     (s3_rdata),
        .s3_rresp     (s3_rresp),
        .s3_rlast     (s3_rlast),
        .s3_rvalid    (s3_rvalid),
        .s3_rready    (s3_rready),
        .s4_awid      (s4_awid),
        .s4_awaddr    (s4_awaddr),
        .s4_awlen     (s4_awlen),
        .s4_awsize    (s4_awsize),
        .s4_awburst   (s4_awburst),
        .s4_awlock    (s4_awlock),
        .s4_awcache   (s4_awcache),
        .s4_awprot    (s4_awprot),
        .s4_awvalid   (s4_awvalid),
        .s4_awready   (s4_awready),
        .s4_wdata     (s4_wdata),
        .s4_wstrb     (s4_wstrb),
        .s4_wlast     (s4_wlast),
        .s4_wvalid    (s4_wvalid),
        .s4_wready    (s4_wready),
        .s4_bid       (s4_bid),
        .s4_bresp     (s4_bresp),
        .s4_bvalid    (s4_bvalid),
        .s4_bready    (s4_bready),
        .s4_arid      (s4_arid),
        .s4_araddr    (s4_araddr),
        .s4_arlen     (s4_arlen),
        .s4_arsize    (s4_arsize),
        .s4_arburst   (s4_arburst),
        .s4_arlock    (s4_arlock),
        .s4_arcache   (s4_arcache),
        .s4_arprot    (s4_arprot),
        .s4_arvalid   (s4_arvalid),
        .s4_arready   (s4_arready),
        .s4_rid       (s4_rid),
        .s4_rdata     (s4_rdata),
        .s4_rresp     (s4_rresp),
        .s4_rlast     (s4_rlast),
        .s4_rvalid    (s4_rvalid),
        .s4_rready    (s4_rready)
    );

    // synopsys translate_off
    task preload_sram_hex;
        input [1023:0] hex_path;
        begin
            u_memory_subsystem.preload_sram_hex(hex_path);
        end
    endtask
    // synopsys translate_on

    soc_peripheral_subsystem #(
        .ENABLE_APB_FAULT_INJECTOR (ENABLE_APB_FAULT_INJECTOR),
        .ENABLE_QSPI_SHARED_ARB   (1'b1),
        .ENABLE_QSPI_QUAD         (ENABLE_QSPI_QUAD)
    ) u_peripheral_subsystem (
        .clk          (clk),
        .rst_n        (rst_n),
        .gpio_pins    (gpio_pins),
        .uart_rx      (ENABLE_UART_PINS ? uart_rx    : 1'b1),
        .uart_tx      (uart_tx),
        .uart_cts_n   (ENABLE_UART_PINS ? uart_cts_n : 1'b0),
        .uart_rts_n   (uart_rts_n),
        .uart_dsr_n   (ENABLE_UART_PINS ? uart_dsr_n : 1'b0),
        .uart_dtr_n   (uart_dtr_n),
        .uart_dcd_n   (ENABLE_UART_PINS ? uart_dcd_n : 1'b0),
        .uart_ri_n    (ENABLE_UART_PINS ? uart_ri_n  : 1'b1),
        .cpu_int      (cpu_int),
        .wdt_reset    (wdt_reset),
        .qspi_timeout_sticky     (qspi_timeout_sticky),
        .qspi_controller_present (qspi_controller_present),
        .ddr4_controller_present (ddr4_controller_present),
        .ddr4_init_done          (ddr4_init_done),
        .ddr4_training_done      (ddr4_training_done),
        .ddr4_fatal_error        (ddr4_fatal_error),
        .ddr4_error_code         (ddr4_error_code),
        .spi_miso     (spi_miso),
        .qspi_cmd_grant (qspi_cmd_grant),
        .spi_sclk     (qspi_cmd_sclk),
        .spi_cs_n     (qspi_cmd_cs_n),
        .spi_mosi     (qspi_cmd_mosi),
        .qspi_io_i    (qspi_io),
        .qspi_io_o    (qspi_cmd_io_o),
        .qspi_io_oe   (qspi_cmd_io_oe),
        .qspi_active  (qspi_cmd_active),
        .qspi_cmd_req (qspi_cmd_req),

        .s_awid       (s1_awid),
        .s_awaddr     (s1_awaddr),
        .s_awlen      (s1_awlen),
        .s_awsize     (s1_awsize),
        .s_awburst    (s1_awburst),
        .s_awlock     (s1_awlock),
        .s_awcache    (s1_awcache),
        .s_awprot     (s1_awprot),
        .s_awvalid    (s1_awvalid),
        .s_awready    (s1_awready),
        .s_wdata      (s1_wdata),
        .s_wstrb      (s1_wstrb),
        .s_wlast      (s1_wlast),
        .s_wvalid     (s1_wvalid),
        .s_wready     (s1_wready),
        .s_bid        (s1_bid),
        .s_bresp      (s1_bresp),
        .s_bvalid     (s1_bvalid),
        .s_bready     (s1_bready),
        .s_arid       (s1_arid),
        .s_araddr     (s1_araddr),
        .s_arlen      (s1_arlen),
        .s_arsize     (s1_arsize),
        .s_arburst    (s1_arburst),
        .s_arlock     (s1_arlock),
        .s_arcache    (s1_arcache),
        .s_arprot     (s1_arprot),
        .s_arvalid    (s1_arvalid),
        .s_arready    (s1_arready),
        .s_rid        (s1_rid),
        .s_rdata      (s1_rdata),
        .s_rresp      (s1_rresp),
        .s_rlast      (s1_rlast),
        .s_rvalid     (s1_rvalid),
        .s_rready     (s1_rready),

        .m_awid       (m2_awid),
        .m_awaddr     (m2_awaddr),
        .m_awlen      (m2_awlen),
        .m_awsize     (m2_awsize),
        .m_awburst    (m2_awburst),
        .m_awlock     (m2_awlock),
        .m_awcache    (m2_awcache),
        .m_awprot     (m2_awprot),
        .m_awvalid    (m2_awvalid),
        .m_awready    (m2_awready),
        .m_wdata      (m2_wdata),
        .m_wstrb      (m2_wstrb),
        .m_wlast      (m2_wlast),
        .m_wvalid     (m2_wvalid),
        .m_wready     (m2_wready),
        .m_bid        (m2_bid),
        .m_bresp      (m2_bresp),
        .m_bvalid     (m2_bvalid),
        .m_bready     (m2_bready),
        .m_arid       (m2_arid),
        .m_araddr     (m2_araddr),
        .m_arlen      (m2_arlen),
        .m_arsize     (m2_arsize),
        .m_arburst    (m2_arburst),
        .m_arlock     (m2_arlock),
        .m_arcache    (m2_arcache),
        .m_arprot     (m2_arprot),
        .m_arvalid    (m2_arvalid),
        .m_arready    (m2_arready),
        .m_rid        (m2_rid),
        .m_rdata      (m2_rdata),
        .m_rresp      (m2_rresp),
        .m_rlast      (m2_rlast),
        .m_rvalid     (m2_rvalid),
        .m_rready     (m2_rready)
    );

    soc_debug_subsystem u_debug_subsystem (
        .clk          (clk),
        .rst_n        (soc_rst_n),
        .tck          (tck),
        .tms          (tms),
        .tdi          (tdi),
        .tdo          (tdo),

        .m_awid       (jtag_awid),
        .m_awaddr     (jtag_awaddr),
        .m_awlen      (jtag_awlen),
        .m_awsize     (jtag_awsize),
        .m_awburst    (jtag_awburst),
        .m_awlock     (jtag_awlock),
        .m_awcache    (jtag_awcache),
        .m_awprot     (jtag_awprot),
        .m_awvalid    (jtag_awvalid),
        .m_awready    (jtag_awready),
        .m_wdata      (jtag_wdata),
        .m_wstrb      (jtag_wstrb),
        .m_wlast      (jtag_wlast),
        .m_wvalid     (jtag_wvalid),
        .m_wready     (jtag_wready),
        .m_bid        (jtag_bid),
        .m_bresp      (jtag_bresp),
        .m_bvalid     (jtag_bvalid),
        .m_bready     (jtag_bready),

        .m_arid       (jtag_arid),
        .m_araddr     (jtag_araddr),
        .m_arlen      (jtag_arlen),
        .m_arsize     (jtag_arsize),
        .m_arburst    (jtag_arburst),
        .m_arlock     (jtag_arlock),
        .m_arcache    (jtag_arcache),
        .m_arprot     (jtag_arprot),
        .m_arvalid    (jtag_arvalid),
        .m_arready    (jtag_arready),
        .m_rid        (jtag_rid),
        .m_rdata      (jtag_rdata),
        .m_rresp      (jtag_rresp),
        .m_rlast      (jtag_rlast),
        .m_rvalid     (jtag_rvalid),
        .m_rready     (jtag_rready)
    );

endmodule
