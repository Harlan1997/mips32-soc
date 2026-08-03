// =============================================================================
// File Name: soc_peripheral_subsystem.v
// Design:    SoC peripheral subsystem integration
// =============================================================================

`include "soc_config.vh"

module soc_peripheral_subsystem #(
    parameter ENABLE_APB_FAULT_INJECTOR = 1'b0,
    parameter ENABLE_QSPI_SHARED_ARB = 1'b0,
    parameter ENABLE_QSPI_QUAD = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,

    inout  wire [31:0] gpio_pins,

    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire        uart_cts_n,
    output wire        uart_rts_n,
    input  wire        uart_dsr_n,
    output wire        uart_dtr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    output wire        cpu_int,
    output wire        wdt_reset,

    input  wire        qspi_timeout_sticky,
    input  wire        qspi_controller_present,
    input  wire        ddr4_controller_present,
    input  wire        ddr4_init_done,
    input  wire        ddr4_training_done,
    input  wire        ddr4_fatal_error,
    input  wire [15:0] ddr4_error_code,
    input  wire        spi_miso,
    input  wire        qspi_cmd_grant,
    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire [3:0]  qspi_io_i,
    output wire [3:0]  qspi_io_o,
    output wire [3:0]  qspi_io_oe,
    output wire        qspi_active,
    output wire        qspi_cmd_req,

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

    // The watchdog remains in the always-on domain. All bridge/peripheral
    // state is reset by the one-cycle watchdog request below.
    wire        periph_rst_n = rst_n & ~wdt_reset;

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
        .rst_n           (periph_rst_n),

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
    wire qspi_sel  = apb_psel & (apb_paddr[15:12] == 4'h5); // 0x4000_5000
    wire ddr4_status_sel = apb_psel & (apb_paddr[15:12] == 4'h6); // 0x4000_6000
    wire wdt_sel   = apb_psel & (apb_paddr[15:12] == 4'h7); // 0x4000_7000
    wire boot_status_sel = apb_psel & (apb_paddr[15:12] == 4'h8); // 0x4000_8000
    wire fault_sel = ENABLE_APB_FAULT_INJECTOR & apb_psel & (apb_paddr[15:12] == 4'hF); // 0x4000_F000

    wire [31:0] uart_prdata, timer_prdata, gpio_prdata, dma_prdata, pic_prdata, qspi_prdata, ddr4_status_prdata, wdt_prdata, boot_status_prdata, fault_prdata;
    wire uart_pready, timer_pready, gpio_pready, dma_pready, pic_pready, qspi_pready, ddr4_status_pready, wdt_pready, boot_status_pready, fault_pready;
    wire uart_pslverr, timer_pslverr, gpio_pslverr, dma_pslverr, pic_pslverr, qspi_pslverr, ddr4_status_pslverr, wdt_pslverr, boot_status_pslverr, fault_pslverr;

    assign apb_prdata  = uart_sel ? uart_prdata :
                         timer_sel ? timer_prdata :
                         gpio_sel ? gpio_prdata :
                         dma_sel ? dma_prdata :
                         pic_sel ? pic_prdata :
                         qspi_sel ? qspi_prdata :
                         ddr4_status_sel ? ddr4_status_prdata :
                         wdt_sel ? wdt_prdata :
                         boot_status_sel ? boot_status_prdata :
                         fault_sel ? fault_prdata : 32'd0;
    assign apb_pready  = uart_sel ? uart_pready :
                         timer_sel ? timer_pready :
                         gpio_sel ? gpio_pready :
                         dma_sel ? dma_pready :
                         pic_sel ? pic_pready :
                         qspi_sel ? qspi_pready :
                         ddr4_status_sel ? ddr4_status_pready :
                         wdt_sel ? wdt_pready :
                         boot_status_sel ? boot_status_pready :
                         fault_sel ? fault_pready : 1'b1;
    assign apb_pslverr = uart_sel ? uart_pslverr :
                         timer_sel ? timer_pslverr :
                         gpio_sel ? gpio_pslverr :
                         dma_sel ? dma_pslverr :
                         pic_sel ? pic_pslverr :
                         qspi_sel ? qspi_pslverr :
                         ddr4_status_sel ? ddr4_status_pslverr :
                         wdt_sel ? wdt_pslverr :
                         boot_status_sel ? boot_status_pslverr :
                         fault_sel ? fault_pslverr : 1'b0;

    wire uart_tx_int;
    wire uart_rx_int;
    // UART: apb_uart_16550 (real PC16550D). v1 apb_uart deleted after
    // signoff #19 validated the cutover. Serial line tied off in DUT;
    // loopback available via MCR[4] for verification.
    wire uart_16550_irq;
    wire uart_16550_rx_irq;
    wire uart_16550_tx_irq;
    // Preserve the established PIC bit1 aggregate IRQ contract while exposing
    // the RX-specific source on bit0 for product firmware.
    assign uart_tx_int = uart_16550_irq;
    assign uart_rx_int = uart_16550_rx_irq;
    apb_uart_16550 #(.TX_FIFO_DEPTH(16), .RX_FIFO_DEPTH(16)) u_apb_uart (
        .clk        (clk),
        .rst_n      (periph_rst_n),
        .psel       (uart_sel),
        .penable    (apb_penable),
        .pwrite     (apb_pwrite),
        .paddr      (apb_paddr[4:0]),
        .pstrb      (apb_pstrb),
        .pwdata     (apb_pwdata),
        .prdata     (uart_prdata),
        .pready     (uart_pready),
        .pslverr    (uart_pslverr),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .uart_rts_n (uart_rts_n),
        .uart_cts_n (uart_cts_n),
        .uart_dtr_n (uart_dtr_n),
        .uart_dsr_n (uart_dsr_n),
        .uart_dcd_n (uart_dcd_n),
        .uart_ri_n  (uart_ri_n),
        .irq        (uart_16550_irq),
        .rx_irq     (uart_16550_rx_irq),
        .tx_irq     (uart_16550_tx_irq)
    );

    generate
    if (ENABLE_APB_FAULT_INJECTOR) begin : g_apb_fault_injector
        reg fault_wait;

        always @(posedge clk or negedge periph_rst_n) begin
            if (!periph_rst_n) begin
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
        .presetn         (periph_rst_n),

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

    // Watchdog is the always-on APB block. Its expiry pulse feeds the SoC
    // reset aggregation in mips_soc_impl; the sticky STATUS bit survives the
    // resulting one-cycle reset of the bridge and other peripherals.
    apb_wdt u_apb_wdt (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (wdt_sel),
        .penable    (apb_penable),
        .pwrite     (apb_pwrite),
        .paddr      (apb_paddr[4:0]),
        .pwdata     (apb_pwdata),
        .prdata     (wdt_prdata),
        .pready     (wdt_pready),
        .pslverr    (wdt_pslverr),
        .wdt_reset  (wdt_reset)
    );

    // Boot status is also always-on: raw rst_n represents POR/external reset,
    // while wdt_reset is recorded as a sticky cause without clearing state.
    apb_boot_status u_apb_boot_status (
        .clk        (clk),
        .rst_n      (rst_n),
        .wdt_reset  (wdt_reset),
        .psel       (boot_status_sel),
        .penable    (apb_penable),
        .pwrite     (apb_pwrite),
        .paddr      (apb_paddr[4:0]),
        .pwdata     (apb_pwdata),
        .prdata     (boot_status_prdata),
        .pready     (boot_status_pready),
        .pslverr    (boot_status_pslverr)
    );

    apb_ddr4_status u_apb_ddr4_status (
        .clk(clk), .rst_n(rst_n), .controller_present(ddr4_controller_present),
        .init_done(ddr4_init_done), .training_done(ddr4_training_done),
        .fatal_error(ddr4_fatal_error), .error_code(ddr4_error_code),
        .psel(ddr4_status_sel), .penable(apb_penable), .pwrite(apb_pwrite),
        .paddr(apb_paddr[4:0]), .pwdata(apb_pwdata), .prdata(ddr4_status_prdata),
        .pready(ddr4_status_pready), .pslverr(ddr4_status_pslverr)
    );

    wire qspi_irq;
    qspi_apb_integration #(
        .ENABLE_SHARED_ARB (ENABLE_QSPI_SHARED_ARB),
        .ENABLE_QUAD_IO    (ENABLE_QSPI_QUAD)
    ) u_qspi_apb_integration (
        .clk                  (clk),
        .rst_n                (periph_rst_n),
        .controller_present   (qspi_controller_present),
        .xip_timeout_sticky   (qspi_timeout_sticky),
        .psel                 (qspi_sel),
        .penable              (apb_penable),
        .pwrite               (apb_pwrite),
        .paddr                (apb_paddr),
        .pstrb                (apb_pstrb),
        .pwdata               (apb_pwdata),
        .prdata               (qspi_prdata),
        .pready               (qspi_pready),
        .pslverr              (qspi_pslverr),
        .spi_sclk             (spi_sclk),
        .spi_cs_n             (spi_cs_n),
        .spi_mosi             (spi_mosi),
        .spi_miso             (spi_miso),
        .qspi_io_i            (qspi_io_i),
        .qspi_io_o            (qspi_io_o),
        .qspi_io_oe           (qspi_io_oe),
        .shared_grant         (qspi_cmd_grant),
        .active               (qspi_active),
        .request              (qspi_cmd_req),
        .irq                  (qspi_irq)
    );

    apb_gpio u_apb_gpio (
        .pclk            (clk),
        .presetn         (periph_rst_n),

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

    // DMA v2 (attempting integration — debug pass)
    wire [3:0] dma_ch_int;
    wire       dma_int = |dma_ch_int;
    assign m_awlock  = 2'h0;
    assign m_awcache = 4'h0;
    assign m_awprot  = 3'h0;
    assign m_arlock  = 2'h0;
    assign m_arcache = 4'h0;
    assign m_arprot  = 3'h0;

    apb_axi_dma #(.N_CHANNELS(4)) u_apb_dma (
        .clk             (clk),
        .rst_n           (periph_rst_n),

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
        .m_arvalid       (m_arvalid),
        .m_arready       (m_arready),
        .m_rid           (m_rid),
        .m_rdata         (m_rdata),
        .m_rresp         (m_rresp),
        .m_rlast         (m_rlast),
        .m_rvalid        (m_rvalid),
        .m_rready        (m_rready),

        .ch_int          (dma_ch_int)
    );

    wire [31:0] irq_sources = {27'd0, qspi_irq, dma_int, timer_int, uart_tx_int, uart_rx_int};

    // -----------------------------------------------------------------------
    // Interrupt controller: apb_vic. Registers 0x0/0x4/0x8 v1-compatible
    // (STATUS/MASK/ACTIVE == RAW/ENABLE/MASKED). Extra features (edge
    // trigger, priority, nesting, VEC_ID) at higher offsets. v1 apb_pic
    // was deleted after signoff #12 validated this cutover.
    // -----------------------------------------------------------------------
    wire [7:0] vic_vec_id_unused;
    wire [3:0] vic_vec_prio_unused;
    apb_vic #(.NUM_SOURCES(32)) u_apb_pic (
        .clk             (clk),
        .rst_n           (periph_rst_n),
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

endmodule
