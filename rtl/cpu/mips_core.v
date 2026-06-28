// =============================================================================
// File Name: mips_core.v
// Design:    MIPS32 CPU Core with L1 Caches
// Author:    Antigravity
// =============================================================================

module mips_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  ext_int,
    
    // AXI4 Master Interface (Instruction Cache)
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
    
    // AXI4 Master Interface (Data Cache)
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
    
    // Debug interface
    output wire        debug_stall,
    output wire        debug_flush
);

    // CPU to I-Cache Interface
    wire        cpu_inst_req;
    wire [31:0] cpu_inst_addr;
    wire        cpu_inst_addr_ok;
    wire        cpu_inst_data_ok;
    wire [31:0] cpu_inst_rdata;
    
    // CPU to D-Cache Interface
    wire        cpu_data_req;
    wire        cpu_data_we;
    wire [31:0] cpu_data_addr;
    wire [31:0] cpu_data_wdata;
    wire [3:0]  cpu_data_be;
    wire        cpu_data_addr_ok;
    wire        cpu_data_data_ok;
    wire [31:0] cpu_data_rdata;
    
    // Instantiating the CPU Pipeline
    mips_cpu u_cpu (
        .clk             (clk),
        .rst_n           (rst_n),
        
        .inst_req        (cpu_inst_req),
        .inst_addr       (cpu_inst_addr),
        .inst_addr_ok    (cpu_inst_addr_ok),
        .inst_data_ok    (cpu_inst_data_ok),
        .inst_rdata      (cpu_inst_rdata),
        
        .data_req        (cpu_data_req),
        .data_we         (cpu_data_we),
        .data_addr       (cpu_data_addr),
        .ext_int         (ext_int),
        .data_wdata      (cpu_data_wdata),
        .data_be         (cpu_data_be),
        .data_addr_ok    (cpu_data_addr_ok),
        .data_data_ok    (cpu_data_data_ok),
        .data_rdata      (cpu_data_rdata),
        
        .debug_stall     (debug_stall),
        .debug_flush     (debug_flush)
    );
    
    // Instantiating the I-Cache
    // Note: I-Cache is read-only, so we tie off the AW/W/B channels
    assign inst_awid    = 4'd0;
    assign inst_awaddr  = 32'd0;
    assign inst_awlen   = 8'd0;
    assign inst_awsize  = 3'd0;
    assign inst_awburst = 2'd0;
    assign inst_awlock  = 2'd0;
    assign inst_awcache = 4'd0;
    assign inst_awprot  = 3'd0;
    assign inst_awvalid = 1'b0;
    
    assign inst_wdata   = 32'd0;
    assign inst_wstrb   = 4'd0;
    assign inst_wlast   = 1'b0;
    assign inst_wvalid  = 1'b0;
    
    assign inst_bready  = 1'b0;
    
    icache u_icache (
        .clk          (clk),
        .rst_n        (rst_n),
        
        .cpu_req      (cpu_inst_req),
        .cpu_addr     (cpu_inst_addr),
        .cpu_rdata    (cpu_inst_rdata),
        .cpu_addr_ok  (cpu_inst_addr_ok),
        .cpu_data_ok  (cpu_inst_data_ok),
        
        .arid         (inst_arid),
        .araddr       (inst_araddr),
        .arlen        (inst_arlen),
        .arsize       (inst_arsize),
        .arburst      (inst_arburst),
        .arlock       (inst_arlock),
        .arcache      (inst_arcache),
        .arprot       (inst_arprot),
        .arvalid      (inst_arvalid),
        .arready      (inst_arready),
        
        .rid          (inst_rid),
        .rdata        (inst_rdata),
        .rresp        (inst_rresp),
        .rlast        (inst_rlast),
        .rvalid       (inst_rvalid),
        .rready       (inst_rready)
    );
    
    // Instantiating the D-Cache
    dcache u_dcache (
        .clk          (clk),
        .rst_n        (rst_n),
        
        .cpu_req      (cpu_data_req),
        .cpu_we       (cpu_data_we),
        .cpu_addr     (cpu_data_addr),
        .cpu_wdata    (cpu_data_wdata),
        .cpu_be       (cpu_data_be),
        .cpu_rdata    (cpu_data_rdata),
        .cpu_addr_ok  (cpu_data_addr_ok),
        .cpu_data_ok  (cpu_data_data_ok),
        
        .awid         (data_awid),
        .awaddr       (data_awaddr),
        .awlen        (data_awlen),
        .awsize       (data_awsize),
        .awburst      (data_awburst),
        .awlock       (data_awlock),
        .awcache      (data_awcache),
        .awprot       (data_awprot),
        .awvalid      (data_awvalid),
        .awready      (data_awready),
        
        .wdata        (data_wdata),
        .wstrb        (data_wstrb),
        .wlast        (data_wlast),
        .wvalid       (data_wvalid),
        .wready       (data_wready),
        
        .bid          (data_bid),
        .bresp        (data_bresp),
        .bvalid       (data_bvalid),
        .bready       (data_bready),
        
        .arid         (data_arid),
        .araddr       (data_araddr),
        .arlen        (data_arlen),
        .arsize       (data_arsize),
        .arburst      (data_arburst),
        .arlock       (data_arlock),
        .arcache      (data_arcache),
        .arprot       (data_arprot),
        .arvalid      (data_arvalid),
        .arready      (data_arready),
        
        .rid          (data_rid),
        .rdata        (data_rdata),
        .rresp        (data_rresp),
        .rlast        (data_rlast),
        .rvalid       (data_rvalid),
        .rready       (data_rready)
    );

endmodule
