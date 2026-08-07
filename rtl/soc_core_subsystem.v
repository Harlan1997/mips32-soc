// =============================================================================
// File Name: soc_core_subsystem.v
// Design:    SoC CPU/cache subsystem integration
// =============================================================================

module soc_core_subsystem #(
    parameter ENABLE_COHERENCY = 1'b0,
    parameter ENABLE_VEIC = 1'b0,
    parameter ENABLE_HARDWARE_WALKER = 1'b0,
    parameter [31:0] HARDWARE_WALKER_PTBR = 32'd0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_int,
    input  wire [7:0]  external_vec_id,
    input  wire        tlb_inv_en,
    input  wire [18:0] tlb_inv_vpn2,
    input  wire [7:0]  tlb_inv_asid,
    input  wire [1:0]  tlb_inv_scope,
    input  wire [5:0]  tlb_inv_wired_floor,
    output wire        coh_store_valid,
    output wire [31:0] coh_store_addr,
    input  wire        coh_snoop_valid,
    input  wire [31:0] coh_snoop_addr,

    output wire [3:0]  inst_awid,
    output wire [31:0] inst_awaddr,
    output wire [7:0]  inst_awlen,
    output wire [2:0]  inst_awsize,
    output wire [1:0]  inst_awburst,
    output wire [1:0]  inst_awlock,
    output wire [3:0]  inst_awcache,
    output wire [2:0]  inst_awprot,
    output wire        inst_awvalid,
    input  wire        inst_awready,
    output wire [31:0] inst_wdata,
    output wire [3:0]  inst_wstrb,
    output wire        inst_wlast,
    output wire        inst_wvalid,
    input  wire        inst_wready,
    input  wire [3:0]  inst_bid,
    input  wire [1:0]  inst_bresp,
    input  wire        inst_bvalid,
    output wire        inst_bready,
    output wire [3:0]  inst_arid,
    output wire [31:0] inst_araddr,
    output wire [7:0]  inst_arlen,
    output wire [2:0]  inst_arsize,
    output wire [1:0]  inst_arburst,
    output wire [1:0]  inst_arlock,
    output wire [3:0]  inst_arcache,
    output wire [2:0]  inst_arprot,
    output wire        inst_arvalid,
    input  wire        inst_arready,
    input  wire [3:0]  inst_rid,
    input  wire [31:0] inst_rdata,
    input  wire [1:0]  inst_rresp,
    input  wire        inst_rlast,
    input  wire        inst_rvalid,
    output wire        inst_rready,

    output wire [3:0]  data_awid,
    output wire [31:0] data_awaddr,
    output wire [7:0]  data_awlen,
    output wire [2:0]  data_awsize,
    output wire [1:0]  data_awburst,
    output wire [1:0]  data_awlock,
    output wire [3:0]  data_awcache,
    output wire [2:0]  data_awprot,
    output wire        data_awvalid,
    input  wire        data_awready,
    output wire [31:0] data_wdata,
    output wire [3:0]  data_wstrb,
    output wire        data_wlast,
    output wire        data_wvalid,
    input  wire        data_wready,
    input  wire [3:0]  data_bid,
    input  wire [1:0]  data_bresp,
    input  wire        data_bvalid,
    output wire        data_bready,
    output wire [3:0]  data_arid,
    output wire [31:0] data_araddr,
    output wire [7:0]  data_arlen,
    output wire [2:0]  data_arsize,
    output wire [1:0]  data_arburst,
    output wire [1:0]  data_arlock,
    output wire [3:0]  data_arcache,
    output wire [2:0]  data_arprot,
    output wire        data_arvalid,
    input  wire        data_arready,
    input  wire [3:0]  data_rid,
    input  wire [31:0] data_rdata,
    input  wire [1:0]  data_rresp,
    input  wire        data_rlast,
    input  wire        data_rvalid,
    output wire        data_rready,

    output wire        debug_stall,
    output wire        debug_flush
);

    // The walker is an opt-in client of the D-side AXI read channel.  CPU
    // walker activity stalls the pipeline, so this single outstanding bridge
    // cannot overlap a cache read and does not need an extra fabric master.
    wire core_ptw_mem_valid;
    wire [31:0] core_ptw_mem_addr;
    wire core_ptw_mem_ready;
    wire [31:0] core_ptw_mem_rdata;
    wire core_ptw_mem_error;
    wire core_ptw_fault_valid;
    wire [2:0] core_ptw_fault_code;
    reg ptw_axi_busy;
    wire ptw_axi_response = ptw_axi_busy && data_rvalid && data_rlast;

    wire [3:0] core_data_awid;
    wire [31:0] core_data_awaddr;
    wire [7:0] core_data_awlen;
    wire [2:0] core_data_awsize;
    wire [1:0] core_data_awburst;
    wire [1:0] core_data_awlock;
    wire [3:0] core_data_awcache;
    wire [2:0] core_data_awprot;
    wire core_data_awvalid, core_data_awready;
    wire [31:0] core_data_wdata;
    wire [3:0] core_data_wstrb;
    wire core_data_wlast, core_data_wvalid, core_data_wready;
    wire [3:0] core_data_bid;
    wire [1:0] core_data_bresp;
    wire core_data_bvalid, core_data_bready;
    wire [3:0] core_data_arid;
    wire [31:0] core_data_araddr;
    wire [7:0] core_data_arlen;
    wire [2:0] core_data_arsize;
    wire [1:0] core_data_arburst;
    wire [1:0] core_data_arlock;
    wire [3:0] core_data_arcache;
    wire [2:0] core_data_arprot;
    wire core_data_arvalid, core_data_arready;
    wire [3:0] core_data_rid;
    wire [31:0] core_data_rdata;
    wire [1:0] core_data_rresp;
    wire core_data_rlast, core_data_rvalid, core_data_rready;

    mips_core #(.ENABLE_COHERENCY(ENABLE_COHERENCY), .ENABLE_VEIC(ENABLE_VEIC)) u_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .ext_int         ({5'd0, cpu_int}),
        .tlb_inv_en      (tlb_inv_en),
        .tlb_inv_vpn2    (tlb_inv_vpn2),
        .tlb_inv_asid    (tlb_inv_asid),
        .tlb_inv_scope   (tlb_inv_scope),
        .tlb_inv_wired_floor(tlb_inv_wired_floor),
        .sim_exception_req(1'b0),
        .sim_exception_code(5'd0),
        .external_vec_id(external_vec_id),
        .coh_store_valid(coh_store_valid),
        .coh_store_addr(coh_store_addr),
        .coh_snoop_valid(coh_snoop_valid),
        .coh_snoop_addr(coh_snoop_addr),
        .scheduler_enable(1'b0),
        .scheduler_timer_tick(1'b0),
        .scheduler_ipi_resched(1'b0),
        .scheduler_yield_req(1'b0),
        .scheduler_active_mask(4'b0001),
        .hardware_walker_enable(ENABLE_HARDWARE_WALKER), .hardware_walker_ptbr(HARDWARE_WALKER_PTBR),
        .ptw_mem_valid(core_ptw_mem_valid), .ptw_mem_addr(core_ptw_mem_addr), .ptw_mem_ready(core_ptw_mem_ready),
        .ptw_mem_rdata(core_ptw_mem_rdata), .ptw_mem_error(core_ptw_mem_error),
        .ptw_fault_valid(core_ptw_fault_valid), .ptw_fault_code(core_ptw_fault_code),

        .inst_awid       (inst_awid),
        .inst_awaddr     (inst_awaddr),
        .inst_awlen      (inst_awlen),
        .inst_awsize     (inst_awsize),
        .inst_awburst    (inst_awburst),
        .inst_awlock     (inst_awlock),
        .inst_awcache    (inst_awcache),
        .inst_awprot     (inst_awprot),
        .inst_awvalid    (inst_awvalid),
        .inst_awready    (inst_awready),
        .inst_wdata      (inst_wdata),
        .inst_wstrb      (inst_wstrb),
        .inst_wlast      (inst_wlast),
        .inst_wvalid     (inst_wvalid),
        .inst_wready     (inst_wready),
        .inst_bid        (inst_bid),
        .inst_bresp      (inst_bresp),
        .inst_bvalid     (inst_bvalid),
        .inst_bready     (inst_bready),
        .inst_arid       (inst_arid),
        .inst_araddr     (inst_araddr),
        .inst_arlen      (inst_arlen),
        .inst_arsize     (inst_arsize),
        .inst_arburst    (inst_arburst),
        .inst_arlock     (inst_arlock),
        .inst_arcache    (inst_arcache),
        .inst_arprot     (inst_arprot),
        .inst_arvalid    (inst_arvalid),
        .inst_arready    (inst_arready),
        .inst_rid        (inst_rid),
        .inst_rdata      (inst_rdata),
        .inst_rresp      (inst_rresp),
        .inst_rlast      (inst_rlast),
        .inst_rvalid     (inst_rvalid),
        .inst_rready     (inst_rready),

        .data_awid       (core_data_awid), .data_awaddr(core_data_awaddr), .data_awlen(core_data_awlen),
        .data_awsize     (core_data_awsize), .data_awburst(core_data_awburst), .data_awlock(core_data_awlock),
        .data_awcache    (core_data_awcache), .data_awprot(core_data_awprot), .data_awvalid(core_data_awvalid),
        .data_awready    (core_data_awready), .data_wdata(core_data_wdata), .data_wstrb(core_data_wstrb),
        .data_wlast      (core_data_wlast), .data_wvalid(core_data_wvalid), .data_wready(core_data_wready),
        .data_bid        (core_data_bid), .data_bresp(core_data_bresp), .data_bvalid(core_data_bvalid),
        .data_bready     (core_data_bready), .data_arid(core_data_arid), .data_araddr(core_data_araddr),
        .data_arlen      (core_data_arlen), .data_arsize(core_data_arsize), .data_arburst(core_data_arburst),
        .data_arlock     (core_data_arlock), .data_arcache(core_data_arcache), .data_arprot(core_data_arprot),
        .data_arvalid    (core_data_arvalid), .data_arready(core_data_arready), .data_rid(core_data_rid),
        .data_rdata      (core_data_rdata), .data_rresp(core_data_rresp), .data_rlast(core_data_rlast),
        .data_rvalid     (core_data_rvalid), .data_rready(core_data_rready),

        .debug_stall     (debug_stall),
        .debug_flush     (debug_flush)
    );

    assign data_awid = core_data_awid; assign data_awaddr = core_data_awaddr;
    assign data_awlen = core_data_awlen; assign data_awsize = core_data_awsize;
    assign data_awburst = core_data_awburst; assign data_awlock = core_data_awlock;
    assign data_awcache = core_data_awcache; assign data_awprot = core_data_awprot;
    assign data_awvalid = core_data_awvalid; assign core_data_awready = data_awready;
    assign data_wdata = core_data_wdata; assign data_wstrb = core_data_wstrb;
    assign data_wlast = core_data_wlast; assign data_wvalid = core_data_wvalid;
    assign core_data_wready = data_wready; assign core_data_bid = data_bid;
    assign core_data_bresp = data_bresp; assign core_data_bvalid = data_bvalid;
    assign data_bready = core_data_bready; assign data_arid = core_ptw_mem_valid ? 4'd0 : core_data_arid;
    assign data_araddr = core_ptw_mem_valid ? core_ptw_mem_addr : core_data_araddr;
    assign data_arlen = core_ptw_mem_valid ? 8'd0 : core_data_arlen;
    assign data_arsize = core_ptw_mem_valid ? 3'd2 : core_data_arsize;
    assign data_arburst = core_ptw_mem_valid ? 2'd1 : core_data_arburst;
    assign data_arlock = core_ptw_mem_valid ? 2'd0 : core_data_arlock;
    assign data_arcache = core_ptw_mem_valid ? 4'd0 : core_data_arcache;
    assign data_arprot = core_ptw_mem_valid ? 3'b010 : core_data_arprot;
    assign data_arvalid = core_ptw_mem_valid && !ptw_axi_busy ? 1'b1 : core_data_arvalid && !ptw_axi_busy;
    assign core_data_arready = !ptw_axi_busy && !core_ptw_mem_valid && data_arready;
    assign core_data_rid = data_rid; assign core_data_rdata = data_rdata;
    assign core_data_rresp = data_rresp; assign core_data_rlast = data_rlast;
    assign core_data_rvalid = data_rvalid && !ptw_axi_busy;
    assign data_rready = ptw_axi_busy ? 1'b1 : core_data_rready;
    assign core_ptw_mem_ready = ptw_axi_response;
    assign core_ptw_mem_rdata = data_rdata;
    assign core_ptw_mem_error = data_rresp != 2'b00;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ptw_axi_busy <= 1'b0;
        else if (!ptw_axi_busy && ENABLE_HARDWARE_WALKER && core_ptw_mem_valid && data_arready)
            ptw_axi_busy <= 1'b1;
        else if (ptw_axi_response)
            ptw_axi_busy <= 1'b0;
    end

endmodule
