`ifndef AXI_MASTER_IF_SV
`define AXI_MASTER_IF_SV

interface axi_master_if(input clk, input rst_n);
    logic [3:0]  awid;
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic [1:0]  awlock;
    logic [3:0]  awcache;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;

    logic [3:0]  wid;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;

    logic [3:0]  bid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [3:0]  arid;
    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic [1:0]  arlock;
    logic [3:0]  arcache;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;

    logic [3:0]  rid;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    clocking mcb @(posedge clk);
        default input #1step output #1ns;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        input  awready;

        output wid, wdata, wstrb, wlast, wvalid;
        input  wready;

        input  bid, bresp, bvalid;
        output bready;

        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        input  arready;

        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid, awready;
        input wid, wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking
endinterface

`endif
