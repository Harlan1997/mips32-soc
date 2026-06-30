// =============================================================================
// File Name: mips_soc.v
// Design:    MIPS32 Minimum SoC Top (CPU + Caches + AXI Arbiter + SRAM)
// Author:    Antigravity
// =============================================================================

module mips_soc (
    input  wire clk,
    input  wire rst_n,
    
    // External GPIO Pins
    inout  wire [31:0] gpio_pins,
    
    // SPI Flash Interface
    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    
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
    // Master Interconnect Interface (AxiM)
    // =========================================================================
    wire [3:0]  axim_awid;
    wire [31:0] axim_awaddr;
    wire [7:0]  axim_awlen;
    wire [2:0]  axim_awsize;
    wire [1:0]  axim_awburst;
    wire [1:0]  axim_awlock;
    wire [3:0]  axim_awcache;
    wire [2:0]  axim_awprot;
    wire        axim_awvalid;
    wire        axim_awready;
    wire [31:0] axim_wdata;
    wire [3:0]  axim_wstrb;
    wire        axim_wlast;
    wire        axim_wvalid;
    wire        axim_wready;
    wire [3:0]  axim_bid;
    wire [1:0]  axim_bresp;
    wire        axim_bvalid;
    wire        axim_bready;
    wire [3:0]  axim_arid;
    wire [31:0] axim_araddr;
    wire [7:0]  axim_arlen;
    wire [2:0]  axim_arsize;
    wire [1:0]  axim_arburst;
    wire [1:0]  axim_arlock;
    wire [3:0]  axim_arcache;
    wire [2:0]  axim_arprot;
    wire        axim_arvalid;
    wire        axim_arready;
    wire [3:0]  axim_rid;
    wire [31:0] axim_rdata;
    wire [1:0]  axim_rresp;
    wire        axim_rlast;
    wire        axim_rvalid;
    wire        axim_rready;
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

    // =========================================================================
    // Cascaded Master Interconnect Interface (AxiM2)
    // =========================================================================
    wire [3:0]  axim2_awid;
    wire [31:0] axim2_awaddr;
    wire [7:0]  axim2_awlen;
    wire [2:0]  axim2_awsize;
    wire [1:0]  axim2_awburst;
    wire [1:0]  axim2_awlock;
    wire [3:0]  axim2_awcache;
    wire [2:0]  axim2_awprot;
    wire        axim2_awvalid;
    wire        axim2_awready;
    wire [31:0] axim2_wdata;
    wire [3:0]  axim2_wstrb;
    wire        axim2_wlast;
    wire        axim2_wvalid;
    wire        axim2_wready;
    wire [3:0]  axim2_bid;
    wire [1:0]  axim2_bresp;
    wire        axim2_bvalid;
    wire        axim2_bready;
    wire [3:0]  axim2_arid;
    wire [31:0] axim2_araddr;
    wire [7:0]  axim2_arlen;
    wire [2:0]  axim2_arsize;
    wire [1:0]  axim2_arburst;
    wire [1:0]  axim2_arlock;
    wire [3:0]  axim2_arcache;
    wire [2:0]  axim2_arprot;
    wire        axim2_arvalid;
    wire        axim2_arready;
    wire [3:0]  axim2_rid;
    wire [31:0] axim2_rdata;
    wire [1:0]  axim2_rresp;
    wire        axim2_rlast;
    wire        axim2_rvalid;
    wire        axim2_rready;
    
    // AXI Master 3 (Output of Arbiter 3)
    wire [3:0]  axim3_awid;
    wire [31:0] axim3_awaddr;
    wire [7:0]  axim3_awlen;
    wire [2:0]  axim3_awsize;
    wire [1:0]  axim3_awburst;
    wire [1:0]  axim3_awlock;
    wire [3:0]  axim3_awcache;
    wire [2:0]  axim3_awprot;
    wire        axim3_awvalid;
    wire        axim3_awready;
    wire [31:0] axim3_wdata;
    wire [3:0]  axim3_wstrb;
    wire        axim3_wlast;
    wire        axim3_wvalid;
    wire        axim3_wready;
    wire [3:0]  axim3_bid;
    wire [1:0]  axim3_bresp;
    wire        axim3_bvalid;
    wire        axim3_bready;
    wire [3:0]  axim3_arid;
    wire [31:0] axim3_araddr;
    wire [7:0]  axim3_arlen;
    wire [2:0]  axim3_arsize;
    wire [1:0]  axim3_arburst;
    wire [1:0]  axim3_arlock;
    wire [3:0]  axim3_arcache;
    wire [2:0]  axim3_arprot;
    wire        axim3_arvalid;
    wire        axim3_arready;
    wire [3:0]  axim3_rid;
    wire [31:0] axim3_rdata;
    wire [1:0]  axim3_rresp;
    wire        axim3_rlast;
    wire        axim3_rvalid;
    wire        axim3_rready;

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
    // AXI Master 4 (Output of Arbiter 4, combined with external UVM master)
    // =========================================================================
    wire [3:0]  axim4_awid;
    wire [31:0] axim4_awaddr;
    wire [7:0]  axim4_awlen;
    wire [2:0]  axim4_awsize;
    wire [1:0]  axim4_awburst;
    wire [1:0]  axim4_awlock;
    wire [3:0]  axim4_awcache;
    wire [2:0]  axim4_awprot;
    wire        axim4_awvalid;
    wire        axim4_awready;
    wire [31:0] axim4_wdata;
    wire [3:0]  axim4_wstrb;
    wire        axim4_wlast;
    wire        axim4_wvalid;
    wire        axim4_wready;
    wire [3:0]  axim4_bid;
    wire [1:0]  axim4_bresp;
    wire        axim4_bvalid;
    wire        axim4_bready;
    wire [3:0]  axim4_arid;
    wire [31:0] axim4_araddr;
    wire [7:0]  axim4_arlen;
    wire [2:0]  axim4_arsize;
    wire [1:0]  axim4_arburst;
    wire [1:0]  axim4_arlock;
    wire [3:0]  axim4_arcache;
    wire [2:0]  axim4_arprot;
    wire        axim4_arvalid;
    wire        axim4_arready;
    wire [3:0]  axim4_rid;
    wire [31:0] axim4_rdata;
    wire [1:0]  axim4_rresp;
    wire        axim4_rlast;
    wire        axim4_rvalid;
    wire        axim4_rready;

    // =========================================================================
    // AXI Slave 0 (SRAM)Flash Controller (0x2000_0000)
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
        
        .s_arid          (s2_arid),
        .s_araddr        (s2_araddr),
        .s_arlen         (s2_arlen),
        .s_arsize        (s2_arsize),
        .s_arburst       (s2_arburst),
        .s_arlock        (s2_arlock),
        .s_arcache      (s2_arcache),
        .s_arprot        (s2_arprot),
        .s_arvalid       (s2_arvalid),
        .s_arready       (s2_arready),
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

    // =========================================================================
    // APB Bridge and Peripherals
    // =========================================================================
    wire [31:0] apb_paddr;
    wire        apb_psel;
    wire        apb_penable;
    wire        apb_pwrite;
    wire [31:0] apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pready;
    wire [31:0] apb_prdata;
    wire        apb_pslverr;

    // =========================================================================
    // Instantiations
    // =========================================================================

    mips_core u_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .ext_int         ({5'd0, cpu_int}), // Map PIC interrupt to HW interrupt 0
        
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

    axi_arbiter_2x1 u_axi_arbiter (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m0_arid         (m0_arid),
        .m0_araddr       (m0_araddr),
        .m0_arlen        (m0_arlen),
        .m0_arsize       (m0_arsize),
        .m0_arburst      (m0_arburst),
        .m0_arlock       (m0_arlock),
        .m0_arcache      (m0_arcache),
        .m0_arprot       (m0_arprot),
        .m0_arvalid      (m0_arvalid),
        .m0_arready      (m0_arready),
        .m0_rid          (m0_rid),
        .m0_rdata        (m0_rdata),
        .m0_rresp        (m0_rresp),
        .m0_rlast        (m0_rlast),
        .m0_rvalid       (m0_rvalid),
        .m0_rready       (m0_rready),
        
        .m1_awid         (m1_awid),
        .m1_awaddr       (m1_awaddr),
        .m1_awlen        (m1_awlen),
        .m1_awsize       (m1_awsize),
        .m1_awburst      (m1_awburst),
        .m1_awlock       (m1_awlock),
        .m1_awcache      (m1_awcache),
        .m1_awprot       (m1_awprot),
        .m1_awvalid      (m1_awvalid),
        .m1_awready      (m1_awready),
        .m1_wdata        (m1_wdata),
        .m1_wstrb        (m1_wstrb),
        .m1_wlast        (m1_wlast),
        .m1_wvalid       (m1_wvalid),
        .m1_wready       (m1_wready),
        .m1_bid          (m1_bid),
        .m1_bresp        (m1_bresp),
        .m1_bvalid       (m1_bvalid),
        .m1_bready       (m1_bready),
        .m1_arid         (m1_arid),
        .m1_araddr       (m1_araddr),
        .m1_arlen        (m1_arlen),
        .m1_arsize       (m1_arsize),
        .m1_arburst      (m1_arburst),
        .m1_arlock       (m1_arlock),
        .m1_arcache      (m1_arcache),
        .m1_arprot       (m1_arprot),
        .m1_arvalid      (m1_arvalid),
        .m1_arready      (m1_arready),
        .m1_rid          (m1_rid),
        .m1_rdata        (m1_rdata),
        .m1_rresp        (m1_rresp),
        .m1_rlast        (m1_rlast),
        .m1_rvalid       (m1_rvalid),
        .m1_rready       (m1_rready),
        
        .s0_awid         (axim_awid),
        .s0_awaddr       (axim_awaddr),
        .s0_awlen        (axim_awlen),
        .s0_awsize       (axim_awsize),
        .s0_awburst      (axim_awburst),
        .s0_awlock       (axim_awlock),
        .s0_awcache      (axim_awcache),
        .s0_awprot       (axim_awprot),
        .s0_awvalid      (axim_awvalid),
        .s0_awready      (axim_awready),
        .s0_wdata        (axim_wdata),
        .s0_wstrb        (axim_wstrb),
        .s0_wlast        (axim_wlast),
        .s0_wvalid       (axim_wvalid),
        .s0_wready       (axim_wready),
        .s0_bid          (axim_bid),
        .s0_bresp        (axim_bresp),
        .s0_bvalid       (axim_bvalid),
        .s0_bready       (axim_bready),
        .s0_arid         (axim_arid),
        .s0_araddr       (axim_araddr),
        .s0_arlen        (axim_arlen),
        .s0_arsize       (axim_arsize),
        .s0_arburst      (axim_arburst),
        .s0_arlock       (axim_arlock),
        .s0_arcache      (axim_arcache),
        .s0_arprot       (axim_arprot),
        .s0_arvalid      (axim_arvalid),
        .s0_arready      (axim_arready),
        .s0_rid          (axim_rid),
        .s0_rdata        (axim_rdata),
        .s0_rresp        (axim_rresp),
        .s0_rlast        (axim_rlast),
        .s0_rvalid       (axim_rvalid),
        .s0_rready       (axim_rready)
    );
    axi_arbiter_2x1_full u_axi_arbiter_2 (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m0_arid         (axim_arid),
        .m0_araddr       (axim_araddr),
        .m0_arlen        (axim_arlen),
        .m0_arsize       (axim_arsize),
        .m0_arburst      (axim_arburst),
        .m0_arlock       (axim_arlock),
        .m0_arcache      (axim_arcache),
        .m0_arprot       (axim_arprot),
        .m0_arvalid      (axim_arvalid),
        .m0_arready      (axim_arready),
        .m0_rid          (axim_rid),
        .m0_rdata        (axim_rdata),
        .m0_rresp        (axim_rresp),
        .m0_rlast        (axim_rlast),
        .m0_rvalid       (axim_rvalid),
        .m0_rready       (axim_rready),
        
        .m0_awid         (axim_awid),
        .m0_awaddr       (axim_awaddr),
        .m0_awlen        (axim_awlen),
        .m0_awsize       (axim_awsize),
        .m0_awburst      (axim_awburst),
        .m0_awlock       (axim_awlock),
        .m0_awcache      (axim_awcache),
        .m0_awprot       (axim_awprot),
        .m0_awvalid      (axim_awvalid),
        .m0_awready      (axim_awready),
        .m0_wdata        (axim_wdata),
        .m0_wstrb        (axim_wstrb),
        .m0_wlast        (axim_wlast),
        .m0_wvalid       (axim_wvalid),
        .m0_wready       (axim_wready),
        .m0_bid          (axim_bid),
        .m0_bresp        (axim_bresp),
        .m0_bvalid       (axim_bvalid),
        .m0_bready       (axim_bready),
        
        .m1_arid         (m2_arid),
        .m1_araddr       (m2_araddr),
        .m1_arlen        (m2_arlen),
        .m1_arsize       (m2_arsize),
        .m1_arburst      (m2_arburst),
        .m1_arlock       (m2_arlock),
        .m1_arcache      (m2_arcache),
        .m1_arprot       (m2_arprot),
        .m1_arvalid      (m2_arvalid),
        .m1_arready      (m2_arready),
        .m1_rid          (m2_rid),
        .m1_rdata        (m2_rdata),
        .m1_rresp        (m2_rresp),
        .m1_rlast        (m2_rlast),
        .m1_rvalid       (m2_rvalid),
        .m1_rready       (m2_rready),
        
        .m1_awid         (m2_awid),
        .m1_awaddr       (m2_awaddr),
        .m1_awlen        (m2_awlen),
        .m1_awsize       (m2_awsize),
        .m1_awburst      (m2_awburst),
        .m1_awlock       (m2_awlock),
        .m1_awcache      (m2_awcache),
        .m1_awprot       (m2_awprot),
        .m1_awvalid      (m2_awvalid),
        .m1_awready      (m2_awready),
        .m1_wdata        (m2_wdata),
        .m1_wstrb        (m2_wstrb),
        .m1_wlast        (m2_wlast),
        .m1_wvalid       (m2_wvalid),
        .m1_wready       (m2_wready),
        .m1_bid          (m2_bid),
        .m1_bresp        (m2_bresp),
        .m1_bvalid       (m2_bvalid),
        .m1_bready       (m2_bready),
        
        .s0_awid         (axim2_awid),
        .s0_awaddr       (axim2_awaddr),
        .s0_awlen        (axim2_awlen),
        .s0_awsize       (axim2_awsize),
        .s0_awburst      (axim2_awburst),
        .s0_awlock       (axim2_awlock),
        .s0_awcache      (axim2_awcache),
        .s0_awprot       (axim2_awprot),
        .s0_awvalid      (axim2_awvalid),
        .s0_awready      (axim2_awready),
        .s0_wdata        (axim2_wdata),
        .s0_wstrb        (axim2_wstrb),
        .s0_wlast        (axim2_wlast),
        .s0_wvalid       (axim2_wvalid),
        .s0_wready       (axim2_wready),
        .s0_bid          (axim2_bid),
        .s0_bresp        (axim2_bresp),
        .s0_bvalid       (axim2_bvalid),
        .s0_bready       (axim2_bready),
        .s0_arid         (axim2_arid),
        .s0_araddr       (axim2_araddr),
        .s0_arlen        (axim2_arlen),
        .s0_arsize       (axim2_arsize),
        .s0_arburst      (axim2_arburst),
        .s0_arlock       (axim2_arlock),
        .s0_arcache      (axim2_arcache),
        .s0_arprot       (axim2_arprot),
        .s0_arvalid      (axim2_arvalid),
        .s0_arready      (axim2_arready),
        .s0_rid          (axim2_rid),
        .s0_rdata        (axim2_rdata),
        .s0_rresp        (axim2_rresp),
        .s0_rlast        (axim2_rlast),
        .s0_rvalid       (axim2_rvalid),
        .s0_rready       (axim2_rready)
    );

    axi_arbiter_2x1_full u_axi_arbiter_3 (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m0_arid         (axim2_arid),
        .m0_araddr       (axim2_araddr),
        .m0_arlen        (axim2_arlen),
        .m0_arsize       (axim2_arsize),
        .m0_arburst      (axim2_arburst),
        .m0_arlock       (axim2_arlock),
        .m0_arcache      (axim2_arcache),
        .m0_arprot       (axim2_arprot),
        .m0_arvalid      (axim2_arvalid),
        .m0_arready      (axim2_arready),
        .m0_rid          (axim2_rid),
        .m0_rdata        (axim2_rdata),
        .m0_rresp        (axim2_rresp),
        .m0_rlast        (axim2_rlast),
        .m0_rvalid       (axim2_rvalid),
        .m0_rready       (axim2_rready),
        
        .m0_awid         (axim2_awid),
        .m0_awaddr       (axim2_awaddr),
        .m0_awlen        (axim2_awlen),
        .m0_awsize       (axim2_awsize),
        .m0_awburst      (axim2_awburst),
        .m0_awlock       (axim2_awlock),
        .m0_awcache      (axim2_awcache),
        .m0_awprot       (axim2_awprot),
        .m0_awvalid      (axim2_awvalid),
        .m0_awready      (axim2_awready),
        .m0_wdata        (axim2_wdata),
        .m0_wstrb        (axim2_wstrb),
        .m0_wlast        (axim2_wlast),
        .m0_wvalid       (axim2_wvalid),
        .m0_wready       (axim2_wready),
        .m0_bid          (axim2_bid),
        .m0_bresp        (axim2_bresp),
        .m0_bvalid       (axim2_bvalid),
        .m0_bready       (axim2_bready),
        
        .m1_arid         (jtag_arid),
        .m1_araddr       (jtag_araddr),
        .m1_arlen        (jtag_arlen),
        .m1_arsize       (jtag_arsize),
        .m1_arburst      (jtag_arburst),
        .m1_arlock       (jtag_arlock),
        .m1_arcache      (jtag_arcache),
        .m1_arprot       (jtag_arprot),
        .m1_arvalid      (jtag_arvalid),
        .m1_arready      (jtag_arready),
        .m1_rid          (jtag_rid),
        .m1_rdata        (jtag_rdata),
        .m1_rresp        (jtag_rresp),
        .m1_rlast        (jtag_rlast),
        .m1_rvalid       (jtag_rvalid),
        .m1_rready       (jtag_rready),
        
        .m1_awid         (jtag_awid),
        .m1_awaddr       (jtag_awaddr),
        .m1_awlen        (jtag_awlen),
        .m1_awsize       (jtag_awsize),
        .m1_awburst      (jtag_awburst),
        .m1_awlock       (jtag_awlock),
        .m1_awcache      (jtag_awcache),
        .m1_awprot       (jtag_awprot),
        .m1_awvalid      (jtag_awvalid),
        .m1_awready      (jtag_awready),
        .m1_wdata        (jtag_wdata),
        .m1_wstrb        (jtag_wstrb),
        .m1_wlast        (jtag_wlast),
        .m1_wvalid       (jtag_wvalid),
        .m1_wready       (jtag_wready),
        .m1_bid          (jtag_bid),
        .m1_bresp        (jtag_bresp),
        .m1_bvalid       (jtag_bvalid),
        .m1_bready       (jtag_bready),
        
        .s0_awid         (axim3_awid),
        .s0_awaddr       (axim3_awaddr),
        .s0_awlen        (axim3_awlen),
        .s0_awsize       (axim3_awsize),
        .s0_awburst      (axim3_awburst),
        .s0_awlock       (axim3_awlock),
        .s0_awcache      (axim3_awcache),
        .s0_awprot       (axim3_awprot),
        .s0_awvalid      (axim3_awvalid),
        .s0_awready      (axim3_awready),
        .s0_wdata        (axim3_wdata),
        .s0_wstrb        (axim3_wstrb),
        .s0_wlast        (axim3_wlast),
        .s0_wvalid       (axim3_wvalid),
        .s0_wready       (axim3_wready),
        .s0_bid          (axim3_bid),
        .s0_bresp        (axim3_bresp),
        .s0_bvalid       (axim3_bvalid),
        .s0_bready       (axim3_bready),
        .s0_arid         (axim3_arid),
        .s0_araddr       (axim3_araddr),
        .s0_arlen        (axim3_arlen),
        .s0_arsize       (axim3_arsize),
        .s0_arburst      (axim3_arburst),
        .s0_arlock       (axim3_arlock),
        .s0_arcache      (axim3_arcache),
        .s0_arprot       (axim3_arprot),
        .s0_arvalid      (axim3_arvalid),
        .s0_arready      (axim3_arready),
        .s0_rid          (axim3_rid),
        .s0_rdata        (axim3_rdata),
        .s0_rresp        (axim3_rresp),
        .s0_rlast        (axim3_rlast),
        .s0_rvalid       (axim3_rvalid),
        .s0_rready       (axim3_rready)
    );

    axi_arbiter_2x1_full u_axi_arbiter_4 (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m0_arid         (axim3_arid),
        .m0_araddr       (axim3_araddr),
        .m0_arlen        (axim3_arlen),
        .m0_arsize       (axim3_arsize),
        .m0_arburst      (axim3_arburst),
        .m0_arlock       (axim3_arlock),
        .m0_arcache      (axim3_arcache),
        .m0_arprot       (axim3_arprot),
        .m0_arvalid      (axim3_arvalid),
        .m0_arready      (axim3_arready),
        .m0_rid          (axim3_rid),
        .m0_rdata        (axim3_rdata),
        .m0_rresp        (axim3_rresp),
        .m0_rlast        (axim3_rlast),
        .m0_rvalid       (axim3_rvalid),
        .m0_rready       (axim3_rready),
        
        .m0_awid         (axim3_awid),
        .m0_awaddr       (axim3_awaddr),
        .m0_awlen        (axim3_awlen),
        .m0_awsize       (axim3_awsize),
        .m0_awburst      (axim3_awburst),
        .m0_awlock       (axim3_awlock),
        .m0_awcache      (axim3_awcache),
        .m0_awprot       (axim3_awprot),
        .m0_awvalid      (axim3_awvalid),
        .m0_awready      (axim3_awready),
        .m0_wdata        (axim3_wdata),
        .m0_wstrb        (axim3_wstrb),
        .m0_wlast        (axim3_wlast),
        .m0_wvalid       (axim3_wvalid),
        .m0_wready       (axim3_wready),
        .m0_bid          (axim3_bid),
        .m0_bresp        (axim3_bresp),
        .m0_bvalid       (axim3_bvalid),
        .m0_bready       (axim3_bready),
        
        .m1_arid         (ext_arid),
        .m1_araddr       (ext_araddr),
        .m1_arlen        (ext_arlen),
        .m1_arsize       (ext_arsize),
        .m1_arburst      (ext_arburst),
        .m1_arlock       (ext_arlock),
        .m1_arcache      (ext_arcache),
        .m1_arprot       (ext_arprot),
        .m1_arvalid      (ext_arvalid),
        .m1_arready      (ext_arready),
        .m1_rid          (ext_rid),
        .m1_rdata        (ext_rdata),
        .m1_rresp        (ext_rresp),
        .m1_rlast        (ext_rlast),
        .m1_rvalid       (ext_rvalid),
        .m1_rready       (ext_rready),
        
        .m1_awid         (ext_awid),
        .m1_awaddr       (ext_awaddr),
        .m1_awlen        (ext_awlen),
        .m1_awsize       (ext_awsize),
        .m1_awburst      (ext_awburst),
        .m1_awlock       (ext_awlock),
        .m1_awcache      (ext_awcache),
        .m1_awprot       (ext_awprot),
        .m1_awvalid      (ext_awvalid),
        .m1_awready      (ext_awready),
        .m1_wdata        (ext_wdata),
        .m1_wstrb        (ext_wstrb),
        .m1_wlast        (ext_wlast),
        .m1_wvalid       (ext_wvalid),
        .m1_wready       (ext_wready),
        .m1_bid          (ext_bid),
        .m1_bresp        (ext_bresp),
        .m1_bvalid       (ext_bvalid),
        .m1_bready       (ext_bready),
        
        .s0_awid         (axim4_awid),
        .s0_awaddr       (axim4_awaddr),
        .s0_awlen        (axim4_awlen),
        .s0_awsize       (axim4_awsize),
        .s0_awburst      (axim4_awburst),
        .s0_awlock       (axim4_awlock),
        .s0_awcache      (axim4_awcache),
        .s0_awprot       (axim4_awprot),
        .s0_awvalid      (axim4_awvalid),
        .s0_awready      (axim4_awready),
        .s0_wdata        (axim4_wdata),
        .s0_wstrb        (axim4_wstrb),
        .s0_wlast        (axim4_wlast),
        .s0_wvalid       (axim4_wvalid),
        .s0_wready       (axim4_wready),
        .s0_bid          (axim4_bid),
        .s0_bresp        (axim4_bresp),
        .s0_bvalid       (axim4_bvalid),
        .s0_bready       (axim4_bready),
        .s0_arid         (axim4_arid),
        .s0_araddr       (axim4_araddr),
        .s0_arlen        (axim4_arlen),
        .s0_arsize       (axim4_arsize),
        .s0_arburst      (axim4_arburst),
        .s0_arlock       (axim4_arlock),
        .s0_arcache      (axim4_arcache),
        .s0_arprot       (axim4_arprot),
        .s0_arvalid      (axim4_arvalid),
        .s0_arready      (axim4_arready),
        .s0_rid          (axim4_rid),
        .s0_rdata        (axim4_rdata),
        .s0_rresp        (axim4_rresp),
        .s0_rlast        (axim4_rlast),
        .s0_rvalid       (axim4_rvalid),
        .s0_rready       (axim4_rready)
    );

    // 1x3 Decoder
    // Slave 0: Boot ROM / SRAM (0x0000_0000 - 0x1FFF_FFFF)
    // Slave 1: APB Peripherals (0x4000_0000 - 0x4FFF_FFFF)
    // Slave 2: SPI Flash       (0x2000_0000 - 0x3FFF_FFFF)
    
    axi_decoder_1x3 u_axi_decoder (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m_awid          (axim4_awid),
        .m_awaddr        (axim4_awaddr),
        .m_awlen         (axim4_awlen),
        .m_awsize        (axim4_awsize),
        .m_awburst       (axim4_awburst),
        .m_awlock        (axim4_awlock),
        .m_awcache       (axim4_awcache),
        .m_awprot        (axim4_awprot),
        .m_awvalid       (axim4_awvalid),
        .m_awready       (axim4_awready),
        .m_wdata         (axim4_wdata),
        .m_wstrb         (axim4_wstrb),
        .m_wlast         (axim4_wlast),
        .m_wvalid        (axim4_wvalid),
        .m_wready        (axim4_wready),
        .m_bid           (axim4_bid),
        .m_bresp         (axim4_bresp),
        .m_bvalid        (axim4_bvalid),
        .m_bready        (axim4_bready),
        .m_arid          (axim4_arid),
        .m_araddr        (axim4_araddr),
        .m_arlen         (axim4_arlen),
        .m_arsize        (axim4_arsize),
        .m_arburst       (axim4_arburst),
        .m_arlock        (axim4_arlock),
        .m_arcache       (axim4_arcache),
        .m_arprot        (axim4_arprot),
        .m_arvalid       (axim4_arvalid),
        .m_arready       (axim4_arready),
        .m_rid           (axim4_rid),
        .m_rdata         (axim4_rdata),
        .m_rresp         (axim4_rresp),
        .m_rlast         (axim4_rlast),
        .m_rvalid        (axim4_rvalid),
        .m_rready        (axim4_rready),
        
        .s0_awid         (s0_awid),
        .s0_awaddr       (s0_awaddr),
        .s0_awlen        (s0_awlen),
        .s0_awsize       (s0_awsize),
        .s0_awburst      (s0_awburst),
        .s0_awlock       (s0_awlock),
        .s0_awcache      (s0_awcache),
        .s0_awprot       (s0_awprot),
        .s0_awvalid      (s0_awvalid),
        .s0_awready      (s0_awready),
        .s0_wdata        (s0_wdata),
        .s0_wstrb        (s0_wstrb),
        .s0_wlast        (s0_wlast),
        .s0_wvalid       (s0_wvalid),
        .s0_wready       (s0_wready),
        .s0_bid          (s0_bid),
        .s0_bresp        (s0_bresp),
        .s0_bvalid       (s0_bvalid),
        .s0_bready       (s0_bready),
        .s0_arid         (s0_arid),
        .s0_araddr       (s0_araddr),
        .s0_arlen        (s0_arlen),
        .s0_arsize       (s0_arsize),
        .s0_arburst      (s0_arburst),
        .s0_arlock       (s0_arlock),
        .s0_arcache      (s0_arcache),
        .s0_arprot       (s0_arprot),
        .s0_arvalid      (s0_arvalid),
        .s0_arready      (s0_arready),
        .s0_rid          (s0_rid),
        .s0_rdata        (s0_rdata),
        .s0_rresp        (s0_rresp),
        .s0_rlast        (s0_rlast),
        .s0_rvalid       (s0_rvalid),
        .s0_rready       (s0_rready),
        
        .s1_awid         (s1_awid),
        .s1_awaddr       (s1_awaddr),
        .s1_awlen        (s1_awlen),
        .s1_awsize       (s1_awsize),
        .s1_awburst      (s1_awburst),
        .s1_awlock       (s1_awlock),
        .s1_awcache      (s1_awcache),
        .s1_awprot       (s1_awprot),
        .s1_awvalid      (s1_awvalid),
        .s1_awready      (s1_awready),
        .s1_wdata        (s1_wdata),
        .s1_wstrb        (s1_wstrb),
        .s1_wlast        (s1_wlast),
        .s1_wvalid       (s1_wvalid),
        .s1_wready       (s1_wready),
        .s1_bid          (s1_bid),
        .s1_bresp        (s1_bresp),
        .s1_bvalid       (s1_bvalid),
        .s1_bready       (s1_bready),
        .s1_arid         (s1_arid),
        .s1_araddr       (s1_araddr),
        .s1_arlen        (s1_arlen),
        .s1_arsize       (s1_arsize),
        .s1_arburst      (s1_arburst),
        .s1_arlock       (s1_arlock),
        .s1_arcache      (s1_arcache),
        .s1_arprot       (s1_arprot),
        .s1_arvalid      (s1_arvalid),
        .s1_arready      (s1_arready),
        .s1_rid          (s1_rid),
        .s1_rdata        (s1_rdata),
        .s1_rresp        (s1_rresp),
        .s1_rlast        (s1_rlast),
        .s1_rvalid       (s1_rvalid),
        .s1_rready       (s1_rready),
        
        .s2_awid         (s2_awid),
        .s2_awaddr       (s2_awaddr),
        .s2_awlen        (s2_awlen),
        .s2_awsize       (s2_awsize),
        .s2_awburst      (s2_awburst),
        .s2_awlock       (s2_awlock),
        .s2_awcache      (s2_awcache),
        .s2_awprot       (s2_awprot),
        .s2_awvalid      (s2_awvalid),
        .s2_awready      (s2_awready),
        .s2_wdata        (s2_wdata),
        .s2_wstrb        (s2_wstrb),
        .s2_wlast        (s2_wlast),
        .s2_wvalid       (s2_wvalid),
        .s2_wready       (s2_wready),
        .s2_bid          (s2_bid),
        .s2_bresp        (s2_bresp),
        .s2_bvalid       (s2_bvalid),
        .s2_bready       (s2_bready),
        .s2_arid         (s2_arid),
        .s2_araddr       (s2_araddr),
        .s2_arlen        (s2_arlen),
        .s2_arsize       (s2_arsize),
        .s2_arburst      (s2_arburst),
        .s2_arlock       (s2_arlock),
        .s2_arcache      (s2_arcache),
        .s2_arprot       (s2_arprot),
        .s2_arvalid      (s2_arvalid),
        .s2_arready      (s2_arready),
        .s2_rid          (s2_rid),
        .s2_rdata        (s2_rdata),
        .s2_rresp        (s2_rresp),
        .s2_rlast        (s2_rlast),
        .s2_rvalid       (s2_rvalid),
        .s2_rready       (s2_rready)
    );
    
    axi_ddr_model #(
        .MEM_DEPTH_WORDS (32768) // e.g. 128KB or keep default
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
    
    axi2apb_bridge u_axi2apb (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .s_awid          (s1_awid),
        .s_awaddr        (s1_awaddr),
        .s_awlen         (s1_awlen),
        .s_awsize        (s1_awsize),
        .s_awburst       (s1_awburst),
        .s_awlock        (s1_awlock),
        .s_awcache       (s1_awcache),
        .s_awprot        (s1_awprot),
        .s_awvalid       (s1_awvalid),
        .s_awready       (s1_awready),
        .s_wdata         (s1_wdata),
        .s_wstrb         (s1_wstrb),
        .s_wlast         (s1_wlast),
        .s_wvalid        (s1_wvalid),
        .s_wready        (s1_wready),
        .s_bid           (s1_bid),
        .s_bresp         (s1_bresp),
        .s_bvalid        (s1_bvalid),
        .s_bready        (s1_bready),
        .s_arid          (s1_arid),
        .s_araddr        (s1_araddr),
        .s_arlen         (s1_arlen),
        .s_arsize        (s1_arsize),
        .s_arburst       (s1_arburst),
        .s_arlock        (s1_arlock),
        .s_arcache       (s1_arcache),
        .s_arprot        (s1_arprot),
        .s_arvalid       (s1_arvalid),
        .s_arready       (s1_arready),
        .s_rid           (s1_rid),
        .s_rdata         (s1_rdata),
        .s_rresp         (s1_rresp),
        .s_rlast         (s1_rlast),
        .s_rvalid        (s1_rvalid),
        .s_rready        (s1_rready),
        
        .paddr           (apb_paddr),
        .psel            (apb_psel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .pstrb           (apb_pstrb),
        .pready          (apb_pready),
        .prdata          (apb_prdata),
        .pslverr         (apb_pslverr)
    );
    
    // APB Decoder
    wire uart_sel  = apb_psel & (apb_paddr[15:12] == 4'h0); // 0x4000_0000
    wire timer_sel = apb_psel & (apb_paddr[15:12] == 4'h1); // 0x4000_1000
    wire gpio_sel  = apb_psel & (apb_paddr[15:12] == 4'h2); // 0x4000_2000
    wire dma_sel   = apb_psel & (apb_paddr[15:12] == 4'h3); // 0x4000_3000
    wire pic_sel   = apb_psel & (apb_paddr[15:12] == 4'h4); // 0x4000_4000
    
    wire [31:0] uart_prdata, timer_prdata, gpio_prdata, dma_prdata, pic_prdata;
    wire uart_pready, timer_pready, gpio_pready, dma_pready, pic_pready;
    wire uart_pslverr, timer_pslverr, gpio_pslverr, dma_pslverr, pic_pslverr;
    
    assign apb_prdata  = uart_sel ? uart_prdata :
                         timer_sel ? timer_prdata :
                         gpio_sel ? gpio_prdata : 
                         dma_sel ? dma_prdata :
                         pic_sel ? pic_prdata : 32'd0;
    assign apb_pready  = uart_sel ? uart_pready :
                         timer_sel ? timer_pready :
                         gpio_sel ? gpio_pready : 
                         dma_sel ? dma_pready :
                         pic_sel ? pic_pready : 1'b1;
    assign apb_pslverr = uart_sel ? uart_pslverr :
                         timer_sel ? timer_pslverr :
                         gpio_sel ? gpio_pslverr : 
                         dma_sel ? dma_pslverr :
                         pic_sel ? pic_pslverr : 1'b0;

    
    apb_uart u_apb_uart (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .paddr           (apb_paddr),
        .psel            (uart_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .pstrb           (apb_pstrb),
        .pready          (uart_pready),
        .prdata          (uart_prdata),
        .pslverr         (uart_pslverr)
    );
    
    wire timer_int;
    apb_timer u_apb_timer (
        .pclk            (clk),
        .presetn         (rst_n),
        
        .paddr           (apb_paddr),
        .psel            (timer_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .prdata          (timer_prdata),
        .pready          (timer_pready),
        .pslverr         (timer_pslverr),
        
        .timer_int       (timer_int)
    );
    
    apb_gpio u_apb_gpio (
        .pclk            (clk),
        .presetn         (rst_n),
        
        .paddr           (apb_paddr[11:0]),
        .psel            (gpio_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .prdata          (gpio_prdata),
        .pready          (gpio_pready),
        .pslverr         (gpio_pslverr),
        
        .gpio_pins       (gpio_pins)
    );

    // =========================================================================
    // JTAG Debug Top
    // =========================================================================
    jtag_debug_top u_jtag_debug_top (
        .clk          (clk),
        .rst_n        (rst_n),
        .tck          (tck),
        .trst_n       (rst_n),
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

    wire dma_int;
    apb_axi_dma u_apb_dma (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .paddr           (apb_paddr[11:0]),
        .psel            (dma_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .prdata          (dma_prdata),
        .pready          (dma_pready),
        .pslverr         (dma_pslverr),
        
        .m_awid          (m2_awid),
        .m_awaddr        (m2_awaddr),
        .m_awlen         (m2_awlen),
        .m_awsize        (m2_awsize),
        .m_awburst       (m2_awburst),
        .m_awlock        (m2_awlock),
        .m_awcache       (m2_awcache),
        .m_awprot        (m2_awprot),
        .m_awvalid       (m2_awvalid),
        .m_awready       (m2_awready),
        .m_wdata         (m2_wdata),
        .m_wstrb         (m2_wstrb),
        .m_wlast         (m2_wlast),
        .m_wvalid        (m2_wvalid),
        .m_wready        (m2_wready),
        .m_bid           (m2_bid),
        .m_bresp         (m2_bresp),
        .m_bvalid        (m2_bvalid),
        .m_bready        (m2_bready),
        .m_arid          (m2_arid),
        .m_araddr        (m2_araddr),
        .m_arlen         (m2_arlen),
        .m_arsize        (m2_arsize),
        .m_arburst       (m2_arburst),
        .m_arlock        (m2_arlock),
        .m_arcache       (m2_arcache),
        .m_arprot        (m2_arprot),
        .m_arvalid       (m2_arvalid),
        .m_arready       (m2_arready),
        .m_rid           (m2_rid),
        .m_rdata         (m2_rdata),
        .m_rresp         (m2_rresp),
        .m_rlast         (m2_rlast),
        .m_rvalid        (m2_rvalid),
        .m_rready        (m2_rready),
        
        .dma_int         (dma_int)
    );

    // =========================================================================
    // Programmable Interrupt Controller (PIC)
    // =========================================================================

    wire uart_tx_int = 1'b0;
    wire uart_rx_int = 1'b0;
    wire [31:0] irq_sources = {28'd0, dma_int, timer_int, uart_tx_int, uart_rx_int};
    
    apb_pic u_apb_pic (
        .pclk            (clk),
        .presetn         (rst_n),
        .paddr           (apb_paddr[11:0]),
        .psel            (pic_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .pwdata          (apb_pwdata),
        .pready          (pic_pready),
        .prdata          (pic_prdata),
        .pslverr         (pic_pslverr),
        .irq_sources     (irq_sources),
        .cpu_int         (cpu_int)
    );

endmodule
