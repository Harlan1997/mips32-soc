// Dual-core opt-in CPU wrapper.
// Core 0 remains owned by soc_core_subsystem.  This block owns core 1 and
// arbitrates its instruction/data read channels onto one AXI master slot;
// data writes have their own AXI write channel.  The arbiter holds the read
// owner until the complete AXI response, so cache refill state cannot change
// while a response is in flight.
module dual_core_axi_subsystem (
    input wire clk, input wire rst_n,
    input wire [5:0] ext_int,
    input wire tlb_inv_en, input wire [18:0] tlb_inv_vpn2,
    input wire [7:0] tlb_inv_asid, input wire [1:0] tlb_inv_scope,
    input wire [5:0] tlb_inv_wired_floor,
    input wire sim_exception_req, input wire [4:0] sim_exception_code,
    output wire coh_store_valid, output wire [31:0] coh_store_addr,
    input wire coh_snoop_valid, input wire [31:0] coh_snoop_addr,
    output wire [3:0] ext_awid, output wire [31:0] ext_awaddr,
    output wire [7:0] ext_awlen, output wire [2:0] ext_awsize,
    output wire [1:0] ext_awburst, output wire [1:0] ext_awlock,
    output wire [3:0] ext_awcache, output wire [2:0] ext_awprot,
    output wire ext_awvalid, input wire ext_awready,
    output wire [31:0] ext_wdata, output wire [3:0] ext_wstrb,
    output wire ext_wlast, output wire ext_wvalid, input wire ext_wready,
    input wire [3:0] ext_bid, input wire [1:0] ext_bresp,
    input wire ext_bvalid, output wire ext_bready,
    output wire [3:0] ext_arid, output wire [31:0] ext_araddr,
    output wire [7:0] ext_arlen, output wire [2:0] ext_arsize,
    output wire [1:0] ext_arburst, output wire [1:0] ext_arlock,
    output wire [3:0] ext_arcache, output wire [2:0] ext_arprot,
    output wire ext_arvalid, input wire ext_arready,
    input wire [3:0] ext_rid, input wire [31:0] ext_rdata,
    input wire [1:0] ext_rresp, input wire ext_rlast,
    input wire ext_rvalid, output wire ext_rready,
    output wire debug_stall, output wire debug_flush
);
    wire [3:0] iawid, iawcache, idata_bid, darid, did;
    wire [3:0] iarid, icache;
    wire [31:0] iawaddr, iwdata, iaddr, daddr, dwdata, idata_rdata, drdata;
    wire [7:0] iawlen, ilen, dlen;
    wire [2:0] iawsize, iawprot, isize, dsize;
    wire [1:0] iawburst, iawlock, iburst, ilock, dburst, dlock, idata_rresp, drresp;
    wire [3:0] iwstrb;
    wire [2:0] iprot, dprot;
    wire iawvalid, iwlast, iwvalid, ibready;
    wire iarvalid, iarready, irvalid, irready, irlast;
    wire dawvalid, dwlast, dwvalid, darvalid, darready, drvalid, drready;
    wire [3:0] dawid, dawcache, darcache;
    wire [31:0] dawaddr, ddata;
    wire [7:0] dawlen;
    wire [2:0] dawsize, dawprot;
    wire [1:0] dawburst, dawlock;
    wire [3:0] dstrb;
    wire dbready;
    wire [1:0] ibresp, dbresp;
    wire [3:0] irid, drid;
    wire [31:0] irdata, drdata_wire;
    wire iaddr_ok, idata_ok, ibus_error, icache_error;
    wire daddr_ok, ddata_ok, dbus_error, dcache_error;
    wire [31:0] icpu_rdata, dcpu_rdata;
    reg rd_busy, rd_owner;

    function [31:0] core1_ipi_alias;
        input [31:0] addr;
        begin
            if ((addr[31:12] == 20'h4000a) && (addr[11:6] == 6'd0))
                core1_ipi_alias = addr + 32'h0000_1000;
            else
                core1_ipi_alias = addr;
        end
    endfunction

    mips_core #(.ENABLE_COHERENCY(1'b1)) u_core1 (
        .clk(clk), .rst_n(rst_n), .ext_int(ext_int),
        .tlb_inv_en(tlb_inv_en), .tlb_inv_vpn2(tlb_inv_vpn2),
        .tlb_inv_asid(tlb_inv_asid), .tlb_inv_scope(tlb_inv_scope),
        .tlb_inv_wired_floor(tlb_inv_wired_floor),
        .sim_exception_req(sim_exception_req), .sim_exception_code(sim_exception_code),
        .coh_store_valid(coh_store_valid), .coh_store_addr(coh_store_addr),
        .coh_snoop_valid(coh_snoop_valid), .coh_snoop_addr(coh_snoop_addr),
        .scheduler_enable(1'b0), .scheduler_timer_tick(1'b0),
        .scheduler_ipi_resched(1'b0), .scheduler_yield_req(1'b0),
        .scheduler_active_mask(4'b0001),
        .hardware_walker_enable(1'b0), .hardware_walker_ptbr(32'd0),
        .ptw_mem_valid(), .ptw_mem_addr(), .ptw_mem_ready(1'b0),
        .ptw_mem_rdata(32'd0), .ptw_mem_error(1'b0),
        .ptw_fault_valid(), .ptw_fault_code(),
        .inst_awid(iawid), .inst_awaddr(iawaddr), .inst_awlen(iawlen),
        .inst_awsize(iawsize), .inst_awburst(iawburst), .inst_awlock(iawlock),
        .inst_awcache(iawcache), .inst_awprot(iawprot), .inst_awvalid(iawvalid),
        .inst_awready(1'b0), .inst_wdata(iwdata), .inst_wstrb(iwstrb),
        .inst_wlast(iwlast), .inst_wvalid(iwvalid), .inst_wready(1'b0),
        .inst_bid(4'd0), .inst_bresp(2'd0), .inst_bvalid(1'b0), .inst_bready(ibready),
        .inst_arid(iarid), .inst_araddr(iaddr), .inst_arlen(ilen),
        .inst_arsize(isize), .inst_arburst(iburst), .inst_arlock(ilock),
        .inst_arcache(icache), .inst_arprot(iprot), .inst_arvalid(iarvalid),
        .inst_arready(iarready), .inst_rid(irid), .inst_rdata(irdata),
        .inst_rresp(ibresp), .inst_rlast(irlast), .inst_rvalid(irvalid),
        .inst_rready(irready),
        .data_awid(dawid), .data_awaddr(dawaddr), .data_awlen(dawlen),
        .data_awsize(dawsize), .data_awburst(dawburst), .data_awlock(dawlock),
        .data_awcache(dawcache), .data_awprot(dawprot), .data_awvalid(dawvalid),
        .data_awready(ext_awready), .data_wdata(ddata), .data_wstrb(dstrb),
        .data_wlast(dwlast), .data_wvalid(dwvalid), .data_wready(ext_wready),
        .data_bid(ext_bid), .data_bresp(ext_bresp), .data_bvalid(ext_bvalid),
        .data_bready(dbready), .data_arid(darid), .data_araddr(daddr),
        .data_arlen(dlen), .data_arsize(dsize), .data_arburst(dburst),
        .data_arlock(dlock), .data_arcache(darcache), .data_arprot(dprot),
        .data_arvalid(darvalid), .data_arready(darready), .data_rid(drid),
        .data_rdata(dcpu_rdata), .data_rresp(dbresp), .data_rlast(),
        .data_rvalid(drvalid), .data_rready(drready),
        .debug_stall(debug_stall), .debug_flush(debug_flush)
    );

    assign ext_awid = dawid; assign ext_awaddr = core1_ipi_alias(dawaddr); assign ext_awlen = dawlen;
    assign ext_awsize = dawsize; assign ext_awburst = dawburst; assign ext_awlock = dlock;
    assign ext_awcache = dawcache; assign ext_awprot = dawprot; assign ext_awvalid = dawvalid;
    assign ext_wdata = ddata; assign ext_wstrb = dstrb; assign ext_wlast = dwlast;
    assign ext_wvalid = dwvalid; assign ext_bready = dbready;
    // Before AR handshake, select the D-side request whenever it is pending;
    // after handshake, keep the registered owner for response routing.
    wire rd_req_owner = (!rd_busy && darvalid) ? 1'b1 : rd_owner;
    assign ext_arid = (rd_req_owner == 1'b0) ? iarid : darid;
    assign ext_araddr = (rd_req_owner == 1'b0) ? iaddr : core1_ipi_alias(daddr);
    assign ext_arlen = (rd_req_owner == 1'b0) ? ilen : dlen;
    assign ext_arsize = (rd_req_owner == 1'b0) ? isize : dsize;
    assign ext_arburst = (rd_req_owner == 1'b0) ? iburst : dburst;
    assign ext_arlock = (rd_req_owner == 1'b0) ? ilock : dlock;
    assign ext_arcache = (rd_req_owner == 1'b0) ? icache : darcache;
    assign ext_arprot = (rd_req_owner == 1'b0) ? iprot : dprot;
    assign ext_arvalid = rd_busy ? 1'b0 : (darvalid | iarvalid);
    assign iarready = !rd_busy && !darvalid && ext_arready;
    assign darready = !rd_busy && darvalid && ext_arready;
    assign irid = ext_rid; assign irdata = ext_rdata; assign ibresp = ext_rresp;
    assign irlast = ext_rlast; assign irvalid = ext_rvalid && (rd_owner == 1'b0);
    assign drid = ext_rid; assign dcpu_rdata = ext_rdata; assign dbresp = ext_rresp;
    assign drvalid = ext_rvalid && (rd_owner == 1'b1);
    assign ext_rready = (rd_owner == 1'b0) ? irready : drready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rd_busy <= 1'b0; rd_owner <= 1'b0; end
        else begin
            if (!rd_busy && ext_arvalid && ext_arready) begin
                rd_busy <= 1'b1;
                rd_owner <= darvalid ? 1'b1 : 1'b0;
            end else if (rd_busy && ext_rvalid && ext_rready && ext_rlast) begin
                rd_busy <= 1'b0;
            end
        end
    end
endmodule
