import re

with open('/home/admin/iccode/rtl/mips_soc.v', 'r') as f:
    code = f.read()

# 1. Add m2_* wires for DMA AXI Master
m2_wires = """
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
"""

code = re.sub(r'(\s*// =========================================================================\n\s*// APB AXI4 Slave Interface \(S1\))', m2_wires + r'\1', code)

# 2. Add second arbiter
arbiter2 = """
    axi_arbiter_2x1 u_axi_arbiter_2 (
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
"""

code = re.sub(r'(\s*axi_decoder_1x2 u_axi_decoder \()', arbiter2 + r'\1', code)

# 3. Change axim_* to axim2_* in axi_decoder_1x2
code = re.sub(r'(\.m_\w+\s*)\(axim_(\w+)\)', r'\1(axim2_\2)', code)

# 4. Add DMA APB decoder logic
apb_decoder = """
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
"""

code = re.sub(r'\s*wire uart_sel  = apb_psel.*?dma_sel \? dma_pslverr : 1\'b0;', '', code, flags=re.DOTALL)
code = re.sub(r'(\s*wire uart_sel  = apb_psel.*?gpio_sel \? gpio_pslverr : 1\'b0;)', apb_decoder, code, flags=re.DOTALL)


# 5. Add DMA instantiation
dma_inst = """
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
"""

code = code.replace("endmodule", dma_inst + "\nendmodule")

with open('/home/admin/iccode/rtl/mips_soc.v', 'w') as f:
    f.write(code)
