// CPU-facing opt-in wrapper for the L1 line-port cache.
//
// Cacheable data requests use l1_cache_nb plus the AXI line bridge. Uncached
// accesses and unsupported CACHE maintenance remain on the legacy dcache.
// The opt-in line cache owns its two address-scoped invalidate operations after
// line traffic drains, keeping APB/flash and unsupported tag/writeback traffic
// out of the line cache.
module l1_cache_nb_cpu_axi #(
    parameter ENABLE_LEGACY_ADDR_HEURISTIC = 1'b1,
    parameter ENABLE_COHERENCY = 1'b0,
    parameter ENABLE_L1 = (`SOC_L1_NONBLOCKING_ENABLE != 0),
    parameter ENABLE_MULTI_OUTSTANDING = 1'b0
) (
    input wire clk, input wire rst_n,
    input wire cpu_req, input wire [3:0] cpu_id,
    input wire cpu_we, input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata, input wire [3:0] cpu_be,
    input wire cpu_uncacheable, output wire [31:0] cpu_rdata,
    output wire cpu_addr_ok, output wire cpu_data_ok,
    output wire cpu_bus_error, output wire cpu_cache_error,
    output wire [3:0] cpu_response_id,
    input wire cache_op_valid, input wire [4:0] cache_op,
    input wire [31:0] cache_op_addr, output wire cache_op_ready,
    output wire cache_op_done, output wire cache_op_error,
    input wire [31:0] cache_tag_wdata, output wire [31:0] cache_tag_rdata,
    output wire [3:0] awid, output wire [31:0] awaddr,
    output wire [7:0] awlen, output wire [2:0] awsize,
    output wire [1:0] awburst, output wire [1:0] awlock,
    output wire [3:0] awcache, output wire [2:0] awprot,
    output wire awvalid, input wire awready, output wire [31:0] wdata,
    output wire [3:0] wstrb, output wire wlast, output wire wvalid,
    input wire wready, input wire [3:0] bid, input wire [1:0] bresp,
    input wire bvalid, output wire bready, output wire [3:0] arid,
    output wire [31:0] araddr, output wire [7:0] arlen,
    output wire [2:0] arsize, output wire [1:0] arburst,
    output wire [1:0] arlock, output wire [3:0] arcache,
    output wire [2:0] arprot, output wire arvalid, input wire arready,
    input wire [3:0] rid, input wire [31:0] rdata, input wire [1:0] rresp,
    input wire rlast, input wire rvalid, output wire rready,
    output wire coh_store_valid, output wire [31:0] coh_store_addr,
    input wire coh_snoop_valid, input wire [31:0] coh_snoop_addr
);
    // Preserve the debug/testbench hierarchy used by the blocking cache
    // while the opt-in adapter is active.  These are observation aliases;
    // functional ownership remains in the instantiated legacy cache.
    // The legacy observation interface intentionally exposes the low four
    // state bits. Keep the aliases at that width so opt-in elaboration does
    // not create a truncation warning; functional state remains owned by the
    // instantiated dcache.
    wire [3:0] state;
    wire [3:0] next_state;
    wire [31:0] req_buf_addr;
    wire req_buf_we;
    wire uncacheable;
    // A cache operation is independent of the data request in the CPU MEM
    // contract.  Keep it exclusively on the legacy cache until maintenance
    // has an explicit nonblocking completion contract.
    reg legacy_active, l1_active, l1_response_seen;
    reg legacy_aw_seen;
    reg [2:0] l1_outstanding;
    reg legacy_req_we_q;
    reg [31:0] legacy_req_addr_q, legacy_req_wdata_q;
    reg [3:0] legacy_req_be_q;
    reg legacy_req_uncacheable_q;
    wire legacy_wready;
    // The integrated prototype L1 is backed by the on-chip SRAM window. Keep
    // peripheral, flash, DDR and unmapped physical addresses on the legacy
    // path until their cacheability/ordering contracts are explicit.
    wire l1_address_supported = (cpu_addr[31:16] == 16'h0000) ||
                                 ((`SOC_L1_NONBLOCKING_DDR_ENABLE != 0) &&
                                  (cpu_addr >= `SOC_DDR_BASE) &&
                                  (cpu_addr < (`SOC_DDR_BASE + `SOC_DDR_SIZE)));
    // Cacheable loads and stores must share one data-cache copy. Sending
    // stores to the legacy cache while loads use the opt-in L1 creates two
    // independent cache states and makes a store followed by a load stale.
    // Only uncached traffic and the legacy-disabled configuration remain on
    // the blocking cache.
    wire legacy_data_req = cpu_req &&
                           (cpu_uncacheable || !ENABLE_L1 || !l1_address_supported);
    wire legacy_cpu_req = legacy_active || legacy_data_req;
    wire legacy_cpu_we = legacy_active ? legacy_req_we_q : cpu_we;
    wire [31:0] legacy_cpu_addr = legacy_active ? legacy_req_addr_q : cpu_addr;
    wire [31:0] legacy_cpu_wdata = legacy_active ? legacy_req_wdata_q : cpu_wdata;
    wire [3:0] legacy_cpu_be = legacy_active ? legacy_req_be_q : cpu_be;
    wire legacy_cpu_uncacheable = legacy_active ? legacy_req_uncacheable_q : cpu_uncacheable;
    wire l1_req = cpu_req && ENABLE_L1 && l1_address_supported && !cpu_uncacheable &&
                  !cache_op_valid &&
                  !legacy_active &&
                  (cpu_we ? ((l1_outstanding == 0) && !l1_active) :
                   (ENABLE_MULTI_OUTSTANDING || !l1_active));
    wire l1_path_request = cpu_req && ENABLE_L1 && l1_address_supported && !cpu_uncacheable &&
                           !cache_op_valid;

    // The opt-in line cache owns the address-scoped invalidate and writeback
    // operations whose completion is reported after the line writeback drains.
    wire cache_op_addr_supported = (cache_op_addr[31:16] == 16'h0000) ||
                                   ((`SOC_L1_NONBLOCKING_DDR_ENABLE != 0) &&
                                    (cache_op_addr >= `SOC_DDR_BASE) &&
                                    (cache_op_addr < (`SOC_DDR_BASE + `SOC_DDR_SIZE)));
    wire l1_maintenance_supported = ENABLE_L1 && cache_op_addr_supported &&
                                    ((cache_op == 5'b00001) ||
                                     (cache_op == 5'b10101) ||
                                     (cache_op == 5'b11001) ||
                                     (cache_op == 5'b11101) ||
                                     (cache_op == 5'b00101) ||
                                     (cache_op == 5'b01001));

    wire [31:0] legacy_rdata;
    wire legacy_addr_ok, legacy_data_ok, legacy_bus_error, legacy_cache_error;
    wire legacy_cache_op_ready, legacy_cache_op_done, legacy_cache_op_error;
    wire [31:0] legacy_tag_rdata;
    wire [3:0] l_awid, l_arid, l_wstrb, l_awcache, l_arcache;
    wire [31:0] l_awaddr, l_wdata, l_araddr;
    wire [7:0] l_awlen, l_arlen;
    wire [2:0] l_awsize, l_arsize, l_awprot, l_arprot;
    wire [1:0] l_awburst, l_awlock, l_arburst, l_arlock;
    wire l_awvalid, l_wlast, l_wvalid, l_bready, l_arvalid, l_rready;
    wire [3:0] n_awid, n_arid, n_wstrb, n_awcache, n_arcache;
    wire [31:0] n_awaddr, n_wdata, n_araddr;
    wire [7:0] n_awlen, n_arlen;
    wire [2:0] n_awsize, n_arsize, n_awprot, n_arprot;
    wire [1:0] n_awburst, n_awlock, n_arburst, n_arlock;
    wire n_awvalid, n_wlast, n_wvalid, n_bready, n_arvalid, n_rready;

    wire n_cpu_ready, n_rsp_valid;
    wire [3:0] n_rsp_id;
    wire [31:0] n_rsp_data;
    wire n_rsp_error;
    wire n_cache_maint_ready, n_cache_maint_done, n_cache_maint_error;
    wire [31:0] n_cache_tag_rdata;
    wire n_mem_req_valid, n_mem_req_we, n_mem_req_ready;
    wire [31:0] n_mem_req_addr;
    wire [255:0] n_mem_req_wdata;
    wire n_mem_rsp_valid, n_mem_rsp_error;
    wire [31:0] n_mem_rsp_addr;
    wire [255:0] n_mem_rsp_data;
    wire [3:0] n_mshr_occ, n_wb_occ;
    wire l1_bridge_active = n_awvalid || n_wvalid || n_bready ||
                            n_arvalid || n_rready || n_mem_req_valid;
    // Maintenance remains owned by the legacy dcache, but cannot be issued
    // while the opt-in L1 has live line traffic, a queued response, or an
    // allocated request. Forwarding raw cache_op_valid to the L1 invalidate
    // sideband would otherwise discard an in-flight refill/MSHR.
    wire maintenance_issue = cache_op_valid && !l1_maintenance_supported &&
                              !l1_bridge_active &&
                              !n_rsp_valid && !l1_active &&
                              (l1_outstanding == 0);
    wire l1_maintenance_issue = cache_op_valid && l1_maintenance_supported &&
                                 n_cache_maint_ready && !l1_bridge_active &&
                                 !n_rsp_valid && !l1_active &&
                                 (l1_outstanding == 0);

    dcache #(
        .ENABLE_LEGACY_ADDR_HEURISTIC(ENABLE_LEGACY_ADDR_HEURISTIC),
        .ENABLE_COHERENCY(ENABLE_COHERENCY)
    ) u_legacy_dcache (
        .clk(clk), .rst_n(rst_n), .cpu_req(legacy_cpu_req), .cpu_we(legacy_cpu_we),
        .cpu_addr(legacy_cpu_addr), .cpu_wdata(legacy_cpu_wdata), .cpu_be(legacy_cpu_be),
        .cpu_uncacheable(legacy_cpu_uncacheable), .cpu_rdata(legacy_rdata),
        .cpu_addr_ok(legacy_addr_ok), .cpu_data_ok(legacy_data_ok),
        .cpu_bus_error(legacy_bus_error), .cpu_cache_error(legacy_cache_error),
        .sim_parity_inject_valid(1'b0), .sim_parity_inject_tag(1'b0),
        .sim_parity_inject_data(1'b0), .sim_parity_inject_way(2'b0),
        .sim_parity_inject_index(6'b0),
        .cache_op_valid(maintenance_issue), .cache_op(cache_op),
        .cache_op_addr(cache_op_addr), .cache_op_ready(legacy_cache_op_ready),
        .cache_op_done(legacy_cache_op_done), .cache_op_error(legacy_cache_op_error),
        .cache_tag_wdata(cache_tag_wdata), .cache_tag_rdata(legacy_tag_rdata),
        .awid(l_awid), .awaddr(l_awaddr), .awlen(l_awlen), .awsize(l_awsize),
        .awburst(l_awburst), .awlock(l_awlock), .awcache(l_awcache),
        .awprot(l_awprot), .awvalid(l_awvalid), .awready(awready),
        .wdata(l_wdata), .wstrb(l_wstrb), .wlast(l_wlast), .wvalid(l_wvalid),
        .wready(legacy_wready), .bid(bid), .bresp(bresp), .bvalid(bvalid),
        .bready(l_bready), .arid(l_arid), .araddr(l_araddr), .arlen(l_arlen),
        .arsize(l_arsize), .arburst(l_arburst), .arlock(l_arlock),
        .arcache(l_arcache), .arprot(l_arprot), .arvalid(l_arvalid),
        .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(l_rready),
        .coh_store_valid(coh_store_valid), .coh_store_addr(coh_store_addr),
        .coh_snoop_valid(coh_snoop_valid), .coh_snoop_addr(coh_snoop_addr)
    );

    assign state          = u_legacy_dcache.state;
    assign next_state     = u_legacy_dcache.next_state;
    assign req_buf_addr   = u_legacy_dcache.req_buf_addr;
    assign req_buf_we     = u_legacy_dcache.req_buf_we;
    assign uncacheable    = u_legacy_dcache.uncacheable;

    // CPU completion and downstream line traffic have different lifetimes:
    // a dirty eviction can still be in AW/W/B after the CPU load/store has
    // received its response. Keep the AXI mux owned by the line bridge for
    // that entire interval.
    // A completed CPU response does not imply that a dirty eviction has
    // drained. Keep the line bridge as the AXI owner until its own traffic is
    // idle; legacy traffic waits and is then selected on the next cycle.
    // A completed L1 response has priority over a newly presented legacy
    // request. Otherwise a legacy store can seize the AXI/data owner while a
    // tagged load response is waiting, leaving the ROB head unready forever.
    wire legacy_sel = !l1_bridge_active && !n_rsp_valid &&
                      (legacy_active ||
                       ((!l1_active) && (l1_outstanding == 0) &&
                        (maintenance_issue || legacy_data_req)));
    // AXI permits AW and W to arrive independently.  The legacy dcache
    // presents both valid bits for a new store, but it must not consume W
    // merely because the crossbar is ready for an older write from this
    // master. Hold W at this adapter boundary until this AW has handshaken.
    assign legacy_wready = legacy_aw_seen ? wready : 1'b0;
    wire l1_sel = !legacy_sel && (l1_active || l1_req || l1_bridge_active);
    wire legacy_wait = legacy_data_req && !legacy_sel;
    wire l1_rsp_fire = n_rsp_valid && !legacy_sel;
    wire legacy_for_current = legacy_sel && !l1_path_request;

    // The standalone block gate uses four sets to force replacement quickly.
    // The CPU adapter keeps enough direct-mapped sets for the SoC smoke
    // scratch walk; replacement remains covered by the dedicated WB gate.
    l1_cache_nb #(.SETS(256)) u_l1 (
        .clk(clk), .rst_n(rst_n), .cpu_valid(l1_req), .cpu_we(cpu_we),
        .cpu_id(cpu_id), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_be(cpu_be), .cache_maint_invalidate(l1_maintenance_issue),
        .cache_maint_op(cache_op), .cache_maint_addr(cache_op_addr),
        .cache_tag_wdata(cache_tag_wdata), .cache_tag_rdata(n_cache_tag_rdata),
        .cache_maint_ready(n_cache_maint_ready),
        .cache_maint_done(n_cache_maint_done),
        .cache_maint_error(n_cache_maint_error),
        .cpu_ready(n_cpu_ready), .rsp_valid(n_rsp_valid),
        .rsp_id(n_rsp_id), .rsp_rdata(n_rsp_data), .rsp_error(n_rsp_error),
        .rsp_ready(!legacy_sel), .mem_req_valid(n_mem_req_valid),
        .mem_req_we(n_mem_req_we), .mem_req_addr(n_mem_req_addr),
        .mem_req_wdata(n_mem_req_wdata), .mem_req_ready(n_mem_req_ready),
        .mem_rsp_valid(n_mem_rsp_valid), .mem_rsp_addr(n_mem_rsp_addr),
        .mem_rsp_data(n_mem_rsp_data), .mem_rsp_error(n_mem_rsp_error),
        .mshr_occupancy(n_mshr_occ), .wb_occupancy(n_wb_occ)
    );

    l1_cache_nb_axi_bridge u_bridge (
        .clk(clk), .rst_n(rst_n), .line_req_valid(n_mem_req_valid),
        .line_req_we(n_mem_req_we), .line_req_addr(n_mem_req_addr),
        .line_req_wdata(n_mem_req_wdata), .line_req_ready(n_mem_req_ready),
        .line_rsp_valid(n_mem_rsp_valid), .line_rsp_addr(n_mem_rsp_addr),
        .line_rsp_data(n_mem_rsp_data), .line_rsp_error(n_mem_rsp_error),
        .awid(n_awid), .awaddr(n_awaddr), .awlen(n_awlen), .awsize(n_awsize),
        .awburst(n_awburst), .awlock(n_awlock), .awcache(n_awcache),
        .awprot(n_awprot), .awvalid(n_awvalid), .awready(awready),
        .wdata(n_wdata), .wstrb(n_wstrb), .wlast(n_wlast), .wvalid(n_wvalid),
        .wready(wready), .bid(bid), .bresp(bresp), .bvalid(bvalid),
        .bready(n_bready), .arid(n_arid), .araddr(n_araddr), .arlen(n_arlen),
        .arsize(n_arsize), .arburst(n_arburst), .arlock(n_arlock),
        .arcache(n_arcache), .arprot(n_arprot), .arvalid(n_arvalid),
        .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(n_rready)
    );


    assign cpu_rdata       = legacy_for_current ? legacy_rdata : n_rsp_data;
    assign cpu_addr_ok     = l1_path_request ? (l1_req && n_cpu_ready) :
                              (legacy_for_current ? legacy_addr_ok :
                               (legacy_wait ? 1'b0 :
                                (ENABLE_MULTI_OUTSTANDING ? n_cpu_ready :
                                 (l1_active ? 1'b0 : n_cpu_ready))));
    // A tagged L1 response is an independent completion event and must stay
    // visible even when the current MEM instruction is a legacy store. The
    // address channel remains blocked by legacy_wait, so the store cannot
    // consume the response as its own transaction.
    assign cpu_data_ok     = legacy_for_current ? legacy_data_ok : n_rsp_valid;
    assign cpu_bus_error   = legacy_for_current ? legacy_bus_error : n_rsp_error;
    assign cpu_cache_error = legacy_for_current ? legacy_cache_error : n_rsp_error;
    assign cpu_response_id = legacy_for_current ? 4'd0 : n_rsp_id;
    assign cache_op_ready  = l1_maintenance_supported ? n_cache_maint_ready :
                              legacy_cache_op_ready;
    assign cache_op_done   = l1_maintenance_supported ? n_cache_maint_done :
                              legacy_cache_op_done;
    assign cache_op_error  = l1_maintenance_supported ? n_cache_maint_error :
                              legacy_cache_op_error;
    assign cache_tag_rdata = l1_maintenance_supported ? n_cache_tag_rdata :
                             legacy_tag_rdata;

    assign awid    = legacy_sel ? l_awid : n_awid;
    assign awaddr  = legacy_sel ? l_awaddr : n_awaddr;
    assign awlen   = legacy_sel ? l_awlen : n_awlen;
    assign awsize  = legacy_sel ? l_awsize : n_awsize;
    assign awburst = legacy_sel ? l_awburst : n_awburst;
    assign awlock  = legacy_sel ? l_awlock : n_awlock;
    assign awcache = legacy_sel ? l_awcache : n_awcache;
    assign awprot  = legacy_sel ? l_awprot : n_awprot;
    assign awvalid = legacy_sel ? l_awvalid : (l1_sel ? n_awvalid : 1'b0);
    assign wdata   = legacy_sel ? l_wdata : n_wdata;
    assign wstrb   = legacy_sel ? l_wstrb : n_wstrb;
    assign wlast   = legacy_sel ? l_wlast : n_wlast;
    assign wvalid  = legacy_sel ? (legacy_aw_seen && l_wvalid) :
                     (l1_sel ? n_wvalid : 1'b0);
    assign bready  = legacy_sel ? l_bready : (l1_sel ? n_bready : 1'b0);
    assign arid    = legacy_sel ? l_arid : n_arid;
    assign araddr  = legacy_sel ? l_araddr : n_araddr;
    assign arlen   = legacy_sel ? l_arlen : n_arlen;
    assign arsize  = legacy_sel ? l_arsize : n_arsize;
    assign arburst = legacy_sel ? l_arburst : n_arburst;
    assign arlock  = legacy_sel ? l_arlock : n_arlock;
    assign arcache = legacy_sel ? l_arcache : n_arcache;
    assign arprot  = legacy_sel ? l_arprot : n_arprot;
    assign arvalid = legacy_sel ? l_arvalid : (l1_sel ? n_arvalid : 1'b0);
    assign rready  = legacy_sel ? l_rready : (l1_sel ? n_rready : 1'b0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            legacy_active <= 1'b0;
            legacy_aw_seen <= 1'b0;
            legacy_req_we_q <= 1'b0;
            legacy_req_addr_q <= 32'd0;
            legacy_req_wdata_q <= 32'd0;
            legacy_req_be_q <= 4'd0;
            legacy_req_uncacheable_q <= 1'b0;
            l1_active     <= 1'b0;
            l1_response_seen <= 1'b0;
            l1_outstanding <= 3'd0;
        end else begin
            if ((legacy_data_req && legacy_addr_ok) ||
                (maintenance_issue && legacy_cache_op_ready))
                legacy_active <= 1'b1;
            if (legacy_data_req && legacy_addr_ok) begin
                legacy_req_we_q <= cpu_we;
                legacy_req_addr_q <= cpu_addr;
                legacy_req_wdata_q <= cpu_wdata;
                legacy_req_be_q <= cpu_be;
                legacy_req_uncacheable_q <= cpu_uncacheable;
            end
            // Start a fresh W ownership window for every accepted legacy
            // request. This prevents an earlier cache writeback's AW/W
            // ownership from authorizing W for a later uncached request.
            if ((legacy_data_req && legacy_addr_ok) ||
                (maintenance_issue && legacy_cache_op_ready))
                legacy_aw_seen <= 1'b0;
            else if (legacy_active && (legacy_data_ok || legacy_cache_op_done))
                legacy_active <= 1'b0;
            if (awvalid && awready)
                legacy_aw_seen <= 1'b1;
            if (wvalid && wready && wlast)
                legacy_aw_seen <= 1'b0;
            // Record ownership from the muxed channel that actually reaches
            // the fabric. The legacy source can remain valid while the L1
            // owner changes during the same cycle; using l_awvalid here can
            // leave W permanently gated after a valid AW handshake.
            if (l1_req && n_cpu_ready)
                begin
                    if (ENABLE_MULTI_OUTSTANDING)
                        l1_outstanding <= l1_outstanding + 1'b1;
                    else begin
                        l1_active <= 1'b1;
                        l1_response_seen <= 1'b0;
                    end
                end
            if (l1_rsp_fire) begin
                if (ENABLE_MULTI_OUTSTANDING)
                    l1_outstanding <= l1_outstanding - 1'b1;
                else if (l1_active)
                    l1_response_seen <= 1'b1;
            end
            // Keep the L1 owner until the CPU-facing response has actually
            // been consumed.  A response can remain at the head of the L1
            // FIFO while the legacy path is otherwise idle; releasing the
            // owner merely because the bridge is idle would make legacy_sel
            // deassert rsp_ready and replay that same response forever.
            if (l1_active && l1_response_seen && l1_rsp_fire &&
                !(l1_req && n_cpu_ready)) begin
                l1_active <= 1'b0;
                l1_response_seen <= 1'b0;
            end
        end
    end

endmodule
