// =============================================================================
// File Name: soc_peripheral_subsystem.v
// Design:    SoC peripheral subsystem integration
// =============================================================================

`include "soc_config.vh"

module soc_peripheral_subsystem #(
    parameter ENABLE_APB_FAULT_INJECTOR = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    inout  wire [31:0] gpio_pins,

    output wire        cpu_int,

    input  wire [3:0]  s_awid,
    input  wire [31:0] s_awaddr,
    input  wire [7:0]  s_awlen,
    input  wire [2:0]  s_awsize,
    input  wire [1:0]  s_awburst,
    input  wire [1:0]  s_awlock,
    input  wire [3:0]  s_awcache,
    input  wire [2:0]  s_awprot,
    input  wire        s_awvalid,
    output wire        s_awready,
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wlast,
    input  wire        s_wvalid,
    output wire        s_wready,
    output wire [3:0]  s_bid,
    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,
    input  wire [3:0]  s_arid,
    input  wire [31:0] s_araddr,
    input  wire [7:0]  s_arlen,
    input  wire [2:0]  s_arsize,
    input  wire [1:0]  s_arburst,
    input  wire [1:0]  s_arlock,
    input  wire [3:0]  s_arcache,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [3:0]  s_rid,
    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rlast,
    output wire        s_rvalid,
    input  wire        s_rready,

    output wire [3:0]  m_awid,
    output wire [31:0] m_awaddr,
    output wire [7:0]  m_awlen,
    output wire [2:0]  m_awsize,
    output wire [1:0]  m_awburst,
    output wire [1:0]  m_awlock,
    output wire [3:0]  m_awcache,
    output wire [2:0]  m_awprot,
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,
    input  wire [3:0]  m_bid,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready,
    output wire [3:0]  m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire [1:0]  m_arlock,
    output wire [3:0]  m_arcache,
    output wire [2:0]  m_arprot,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [3:0]  m_rid,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready
);

    wire [31:0] apb_paddr;
    wire        apb_psel;
    wire        apb_penable;
    wire        apb_pwrite;
    wire [31:0] apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pready;
    wire [31:0] apb_prdata;
    wire        apb_pslverr;

    axi2apb_bridge u_axi2apb (
        .clk             (clk),
        .rst_n           (rst_n),

        .s_awid          (s_awid),
        .s_awaddr        (s_awaddr),
        .s_awlen         (s_awlen),
        .s_awsize        (s_awsize),
        .s_awburst       (s_awburst),
        .s_awlock        (s_awlock),
        .s_awcache       (s_awcache),
        .s_awprot        (s_awprot),
        .s_awvalid       (s_awvalid),
        .s_awready       (s_awready),
        .s_wdata         (s_wdata),
        .s_wstrb         (s_wstrb),
        .s_wlast         (s_wlast),
        .s_wvalid        (s_wvalid),
        .s_wready        (s_wready),
        .s_bid           (s_bid),
        .s_bresp         (s_bresp),
        .s_bvalid        (s_bvalid),
        .s_bready        (s_bready),
        .s_arid          (s_arid),
        .s_araddr        (s_araddr),
        .s_arlen         (s_arlen),
        .s_arsize        (s_arsize),
        .s_arburst       (s_arburst),
        .s_arlock        (s_arlock),
        .s_arcache       (s_arcache),
        .s_arprot        (s_arprot),
        .s_arvalid       (s_arvalid),
        .s_arready       (s_arready),
        .s_rid           (s_rid),
        .s_rdata         (s_rdata),
        .s_rresp         (s_rresp),
        .s_rlast         (s_rlast),
        .s_rvalid        (s_rvalid),
        .s_rready        (s_rready),

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

    wire uart_sel  = apb_psel & (apb_paddr[15:12] == 4'h0); // 0x4000_0000
    wire timer_sel = apb_psel & (apb_paddr[15:12] == 4'h1); // 0x4000_1000
    wire gpio_sel  = apb_psel & (apb_paddr[15:12] == 4'h2); // 0x4000_2000
    wire dma_sel   = apb_psel & (apb_paddr[15:12] == 4'h3); // 0x4000_3000
    wire pic_sel   = apb_psel & (apb_paddr[15:12] == 4'h4); // 0x4000_4000
    wire fault_sel = ENABLE_APB_FAULT_INJECTOR & apb_psel & (apb_paddr[15:12] == 4'hF); // 0x4000_F000

    wire [31:0] uart_prdata, timer_prdata, gpio_prdata, dma_prdata, pic_prdata, fault_prdata;
    wire uart_pready, timer_pready, gpio_pready, dma_pready, pic_pready, fault_pready;
    wire uart_pslverr, timer_pslverr, gpio_pslverr, dma_pslverr, pic_pslverr, fault_pslverr;

    assign apb_prdata  = uart_sel ? uart_prdata :
                         timer_sel ? timer_prdata :
                         gpio_sel ? gpio_prdata :
                         dma_sel ? dma_prdata :
                         pic_sel ? pic_prdata :
                         fault_sel ? fault_prdata : 32'd0;
    assign apb_pready  = uart_sel ? uart_pready :
                         timer_sel ? timer_pready :
                         gpio_sel ? gpio_pready :
                         dma_sel ? dma_pready :
                         pic_sel ? pic_pready :
                         fault_sel ? fault_pready : 1'b1;
    assign apb_pslverr = uart_sel ? uart_pslverr :
                         timer_sel ? timer_pslverr :
                         gpio_sel ? gpio_pslverr :
                         dma_sel ? dma_pslverr :
                         pic_sel ? pic_pslverr :
                         fault_sel ? fault_pslverr : 1'b0;

    wire uart_tx_int;
    wire uart_rx_int;
`ifdef SOC_USE_UART_16550
    // v1 apb_uart was $write-based sim stub; v2 apb_uart_16550 is a real
    // controller. TX write @ 0x00 is API-compatible (firmware just writes
    // chars). Serial line is tied off; loopback disabled by default.
    wire uart_16550_irq;
    assign uart_tx_int = uart_16550_irq;
    assign uart_rx_int = 1'b0;
    apb_uart_16550 #(.TX_FIFO_DEPTH(16), .RX_FIFO_DEPTH(16)) u_apb_uart (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (uart_sel),
        .penable    (apb_penable),
        .pwrite     (apb_pwrite),
        .paddr      (apb_paddr[4:0]),
        .pstrb      (apb_pstrb),
        .pwdata     (apb_pwdata),
        .prdata     (uart_prdata),
        .pready     (uart_pready),
        .pslverr    (uart_pslverr),
        .uart_tx    (),
        .uart_rx    (1'b1),
        .uart_rts_n (),
        .uart_cts_n (1'b0),
        .uart_dtr_n (),
        .uart_dsr_n (1'b0),
        .uart_dcd_n (1'b0),
        .uart_ri_n  (1'b1),
        .irq        (uart_16550_irq)
    );
`else
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
        .pslverr         (uart_pslverr),
        .tx_int          (uart_tx_int),
        .rx_int          (uart_rx_int)
    );
`endif

    generate
    if (ENABLE_APB_FAULT_INJECTOR) begin : g_apb_fault_injector
        reg fault_wait;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                fault_wait <= 1'b0;
            end else if (fault_sel && apb_penable && !fault_wait) begin
                fault_wait <= 1'b1;
            end else begin
                fault_wait <= 1'b0;
            end
        end

        assign fault_prdata  = 32'hBAD0_0BAD;
        assign fault_pready  = fault_wait;
        assign fault_pslverr = fault_sel & apb_penable & fault_wait;
    end else begin : g_no_apb_fault_injector
        assign fault_prdata  = 32'd0;
        assign fault_pready  = 1'b1;
        assign fault_pslverr = 1'b0;
    end
    endgenerate

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

        .m_awid          (m_awid),
        .m_awaddr        (m_awaddr),
        .m_awlen         (m_awlen),
        .m_awsize        (m_awsize),
        .m_awburst       (m_awburst),
        .m_awlock        (m_awlock),
        .m_awcache       (m_awcache),
        .m_awprot        (m_awprot),
        .m_awvalid       (m_awvalid),
        .m_awready       (m_awready),
        .m_wdata         (m_wdata),
        .m_wstrb         (m_wstrb),
        .m_wlast         (m_wlast),
        .m_wvalid        (m_wvalid),
        .m_wready        (m_wready),
        .m_bid           (m_bid),
        .m_bresp         (m_bresp),
        .m_bvalid        (m_bvalid),
        .m_bready        (m_bready),
        .m_arid          (m_arid),
        .m_araddr        (m_araddr),
        .m_arlen         (m_arlen),
        .m_arsize        (m_arsize),
        .m_arburst       (m_arburst),
        .m_arlock        (m_arlock),
        .m_arcache       (m_arcache),
        .m_arprot        (m_arprot),
        .m_arvalid       (m_arvalid),
        .m_arready       (m_arready),
        .m_rid           (m_rid),
        .m_rdata         (m_rdata),
        .m_rresp         (m_rresp),
        .m_rlast         (m_rlast),
        .m_rvalid        (m_rvalid),
        .m_rready        (m_rready),

        .dma_int         (dma_int)
    );

    wire [31:0] irq_sources = {28'd0, dma_int, timer_int, uart_tx_int, uart_rx_int};

    // -----------------------------------------------------------------------
    // VIC cutover: apb_vic supersedes apb_pic. Registers 0x0/0x4/0x8 are
    // v1-compatible (STATUS/MASK/ACTIVE == RAW/ENABLE/MASKED). Extra v2
    // features (edge trigger, per-source priority, ACTIVE tracking, soft
    // trigger, VEC_ID) available at higher offsets. Fallback wrapper in
    // soc_config.vh: comment out SOC_USE_VIC to revert to apb_pic.
    // -----------------------------------------------------------------------
`ifdef SOC_USE_VIC
    wire [7:0] vic_vec_id_unused;
    wire [3:0] vic_vec_prio_unused;
    apb_vic #(.NUM_SOURCES(32)) u_apb_pic (
        .clk             (clk),
        .rst_n           (rst_n),
        .psel            (pic_sel),
        .penable         (apb_penable),
        .pwrite          (apb_pwrite),
        .paddr           (apb_paddr[11:0]),
        .pwdata          (apb_pwdata),
        .prdata          (pic_prdata),
        .pready          (pic_pready),
        .pslverr         (pic_pslverr),
        .src_in          (irq_sources),
        .irq             (cpu_int),
        .vec_id          (vic_vec_id_unused),
        .vec_prio        (vic_vec_prio_unused)
    );
`else
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
`endif

endmodule
