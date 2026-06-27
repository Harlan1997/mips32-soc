// =============================================================================
// File Name: mips_soc.v
// Design:    MIPS32 Minimum SoC Top (CPU + Caches + AXI Arbiter + SRAM)
// Author:    Antigravity
// =============================================================================

module mips_soc (
    input  wire clk,
    input  wire rst_n,
    
    // External GPIO Pins
    inout  wire [31:0] gpio_pins
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
    // APB Master Interface
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


    axi_decoder_1x2 u_axi_decoder (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .m_awid          (axim2_awid),
        .m_awaddr        (axim2_awaddr),
        .m_awlen         (axim2_awlen),
        .m_awsize        (axim2_awsize),
        .m_awburst       (axim2_awburst),
        .m_awlock        (axim2_awlock),
        .m_awcache       (axim2_awcache),
        .m_awprot        (axim2_awprot),
        .m_awvalid       (axim2_awvalid),
        .m_awready       (axim2_awready),
        .m_wdata         (axim2_wdata),
        .m_wstrb         (axim2_wstrb),
        .m_wlast         (axim2_wlast),
        .m_wvalid        (axim2_wvalid),
        .m_wready        (axim2_wready),
        .m_bid           (axim2_bid),
        .m_bresp         (axim2_bresp),
        .m_bvalid        (axim2_bvalid),
        .m_bready        (axim2_bready),
        .m_arid          (axim2_arid),
        .m_araddr        (axim2_araddr),
        .m_arlen         (axim2_arlen),
        .m_arsize        (axim2_arsize),
        .m_arburst       (axim2_arburst),
        .m_arlock        (axim2_arlock),
        .m_arcache       (axim2_arcache),
        .m_arprot        (axim2_arprot),
        .m_arvalid       (axim2_arvalid),
        .m_arready       (axim2_arready),
        .m_rid           (axim2_rid),
        .m_rdata         (axim2_rdata),
        .m_rresp         (axim2_rresp),
        .m_rlast         (axim2_rlast),
        .m_rvalid        (axim2_rvalid),
        .m_rready        (axim2_rready),
        
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
        .s1_rready       (s1_rready)
    );
    
    axi_sram #(
        .MEM_DEPTH_WORDS (16384) // 64KB
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
    
    wire [31:0] uart_prdata, timer_prdata, gpio_prdata, dma_prdata;
    wire uart_pready, timer_pready, gpio_pready, dma_pready;
    wire uart_pslverr, timer_pslverr, gpio_pslverr, dma_pslverr;
    
    assign apb_prdata  = uart_sel ? uart_prdata :
                         timer_sel ? timer_prdata :
                         gpio_sel ? gpio_prdata : 
                         dma_sel ? dma_prdata : 32'd0;
    assign apb_pready  = uart_sel ? uart_pready :
                         timer_sel ? timer_pready :
                         gpio_sel ? gpio_pready : 
                         dma_sel ? dma_pready : 1'b1;
    assign apb_pslverr = uart_sel ? uart_pslverr :
                         timer_sel ? timer_pslverr :
                         gpio_sel ? gpio_pslverr : 
                         dma_sel ? dma_pslverr : 1'b0;

    
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

endmodule
