`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_if.sv"
`include "../agents/axi_master_if.sv"
`include "../checkers/axi_protocol_checker.sv"
`include "../tests/soc_base_test.sv"
`include "../tests/soc_bus_stress_test.sv"
`include "../tests/soc_unmapped_error_test.sv"
`include "../tests/soc_flash_write_error_test.sv"
`include "../tests/soc_fabric_contract_test.sv"
`include "../tests/soc_gpio_reg_model_test.sv"
`include "../tests/soc_sram_data_integrity_test.sv"
`include "../tests/soc_axi_id_sweep_test.sv"
`include "../tests/soc_axi_overlap_probe_test.sv"

module tb_top;
    logic clk;
    logic rst_n;
    
    // External GPIO and JTAG (stubbed for now)
    wire [31:0] gpio_pins;
    logic tck, tms, tdi, tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;

    // Instantiate UVM AXI Interfaces
    axi_if        axi_vif(clk, rst_n);        // Passive monitor for SoC SRAM AXI port
    axi_master_if axi_master_vif(clk, rst_n); // Active verification master

    wire [3:0]  mon_s0_awid;
    wire [31:0] mon_s0_awaddr;
    wire [7:0]  mon_s0_awlen;
    wire [2:0]  mon_s0_awsize;
    wire [1:0]  mon_s0_awburst;
    wire [1:0]  mon_s0_awlock;
    wire [3:0]  mon_s0_awcache;
    wire [2:0]  mon_s0_awprot;
    wire        mon_s0_awvalid;
    wire        mon_s0_awready;
    wire [31:0] mon_s0_wdata;
    wire [3:0]  mon_s0_wstrb;
    wire        mon_s0_wlast;
    wire        mon_s0_wvalid;
    wire        mon_s0_wready;
    wire [3:0]  mon_s0_bid;
    wire [1:0]  mon_s0_bresp;
    wire        mon_s0_bvalid;
    wire        mon_s0_bready;
    wire [3:0]  mon_s0_arid;
    wire [31:0] mon_s0_araddr;
    wire [7:0]  mon_s0_arlen;
    wire [2:0]  mon_s0_arsize;
    wire [1:0]  mon_s0_arburst;
    wire [1:0]  mon_s0_arlock;
    wire [3:0]  mon_s0_arcache;
    wire [2:0]  mon_s0_arprot;
    wire        mon_s0_arvalid;
    wire        mon_s0_arready;
    wire [3:0]  mon_s0_rid;
    wire [31:0] mon_s0_rdata;
    wire [1:0]  mon_s0_rresp;
    wire        mon_s0_rlast;
    wire        mon_s0_rvalid;
    wire        mon_s0_rready;
    wire        mailbox_valid;
    wire [31:0] mailbox_wdata;
    wire        ex_reg_write;
    wire [31:0] ex_pc;
    wire [2:0]  jtag_axi_state;

    initial begin
        tck = 0;
        tms = 1;
        tdi = 0;
    end

    // Clock Generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Reset Generation
    initial begin
        rst_n = 0;
        #50;
        rst_n = 1;
    end

    // JTAG TAP Coverage Stimulus
    task jtag_tick(input logic next_tms, input logic next_tdi);
        tms = next_tms;
        tdi = next_tdi;
        #5 tck = 1;
        #10 tck = 0;
        #5;
    endtask

    task jtag_write_ir(input logic [3:0] ir_val);
        // IDLE -> SEL_DR -> SEL_IR -> CAP_IR -> SHIFT_IR
        jtag_tick(1, 0); // SEL_DR
        jtag_tick(1, 0); // SEL_IR
        jtag_tick(0, 0); // CAP_IR
        jtag_tick(0, 0); // SHIFT_IR
        
        // Shift 4 bits (LSB first). On last bit, tms=1 to enter EXIT1_IR
        jtag_tick(0, ir_val[0]);
        jtag_tick(0, ir_val[1]);
        jtag_tick(0, ir_val[2]);
        jtag_tick(1, ir_val[3]); // EXIT1_IR
        
        jtag_tick(1, 0); // UPDATE_IR
        jtag_tick(0, 0); // RUN_TEST_IDLE
    endtask

    task jtag_write_dr_65b(input logic [64:0] dr_val);
        // IDLE -> SEL_DR -> CAP_DR -> SHIFT_DR
        jtag_tick(1, 0); // SEL_DR
        jtag_tick(0, 0); // CAP_DR
        jtag_tick(0, 0); // SHIFT_DR
        
        // Shift 65 bits
        for (int i=0; i<64; i++) begin
            jtag_tick(0, dr_val[i]);
        end
        // Last bit with tms=1 to enter EXIT1_DR
        jtag_tick(1, dr_val[64]); // EXIT1_DR
        
        jtag_tick(1, 0); // UPDATE_DR
        jtag_tick(0, 0); // RUN_TEST_IDLE
    endtask

    initial begin
        #100;
        // From RESET to IDLE
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // Traversing all branches for coverage
        // DR Branch exhaustive traverse
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(0, 1); // SHIFT_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(0, 0); // PAUSE_DR (stay)
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(0, 0); // SHIFT_DR (loop back)
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(1, 0); // UPDATE_DR
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // DR Additional Missing Transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR (covers CAPTURE_DR->EXIT1_DR)
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(1, 0); // UPDATE_DR (covers EXIT2_DR->UPDATE_DR)
        jtag_tick(1, 0); // SELECT_DR_SCAN (covers UPDATE_DR->SELECT_DR_SCAN)
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // IR Branch exhaustive traverse
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(0, 0); // CAPTURE_IR
        jtag_tick(0, 1); // SHIFT_IR
        jtag_tick(1, 0); // EXIT1_IR
        jtag_tick(0, 0); // PAUSE_IR
        jtag_tick(0, 0); // PAUSE_IR (stay)
        jtag_tick(1, 0); // EXIT2_IR
        jtag_tick(0, 0); // SHIFT_IR (loop back)
        jtag_tick(1, 0); // EXIT1_IR
        jtag_tick(1, 0); // UPDATE_IR
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // IR Additional Missing Transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(0, 0); // CAPTURE_IR
        jtag_tick(1, 0); // EXIT1_IR (covers CAPTURE_IR->EXIT1_IR)
        jtag_tick(0, 0); // PAUSE_IR
        jtag_tick(1, 0); // EXIT2_IR
        jtag_tick(1, 0); // UPDATE_IR (covers EXIT2_IR->UPDATE_IR)
        jtag_tick(1, 0); // SELECT_DR_SCAN (covers UPDATE_IR->SELECT_DR_SCAN)
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        jtag_tick(0, 0); // RUN_TEST_IDLE
        
        // Now trigger real AXI transactions via JTAG
        jtag_write_ir(4'h8); // IR_AXI_CMD
        // AXI Write: [64]=1(Write), [63:32]=Addr(0x4000_0010), [31:0]=Data(0x12345678)
        jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h12345678});
        #500; // wait for AXI FSM
        
        // AXI Read: [64]=0(Read), [63:32]=Addr(0x4000_0010), [31:0]=Dummy
        jtag_write_dr_65b({1'b0, 32'h4000_0010, 32'h00000000});
        #500; // wait for AXI FSM
        
        // Toggle boost for JTAG DR (AXI Writes with full bit flips)
        jtag_write_dr_65b({1'b1, 32'hFFFF_FFFF, 32'hFFFF_FFFF}); // Unmapped addr, will trigger DECERR but JTAG handles it
        #500;
        jtag_write_dr_65b({1'b1, 32'hAAAA_AAAA, 32'hAAAA_AAAA});
        #500;
        jtag_write_dr_65b({1'b1, 32'h5555_5555, 32'h5555_5555});
        #500;
        jtag_write_dr_65b({1'b0, 32'h0000_0000, 32'h0000_0000});
        #500;
        
        // Return to RESET
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(1, 0); // SELECT_IR_SCAN
        jtag_tick(1, 0); // TEST_LOGIC_RESET
        
        // --- Coverage for Asynchronous Resets (rst_n / trst_n) ---
        // AXI FSM Async Resets
        fork
            begin // Thread 1: Trigger JTAG AXI Write
                jtag_write_ir(4'h8); // IR_AXI_CMD
                jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h00000000});
            end
            begin // Thread 2: Intercept at ST_AW
                wait(jtag_axi_state == 3'd1); // ST_AW
                rst_n = 0; #5; rst_n = 1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(jtag_axi_state == 3'd2); // ST_W
                rst_n = 0; #5; rst_n = 1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b0, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(jtag_axi_state == 3'd4); // ST_AR
                rst_n = 0; #5; rst_n = 1;
            end
        join

        // TAP Controller Async Resets
        // We will just do a few common states that missed TEST_LOGIC_RESET transitions
        jtag_tick(1, 0); // SELECT_DR_SCAN
        rst_n = 0; #5; rst_n = 1;
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        rst_n = 0; #5; rst_n = 1;
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        rst_n = 0; #5; rst_n = 1;
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        rst_n = 0; #5; rst_n = 1;
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        rst_n = 0; #5; rst_n = 1;
        
        jtag_tick(1, 0); // SELECT_DR_SCAN
        jtag_tick(0, 0); // CAPTURE_DR
        jtag_tick(1, 0); // EXIT1_DR
        jtag_tick(0, 0); // PAUSE_DR
        jtag_tick(1, 0); // EXIT2_DR
        jtag_tick(1, 0); // UPDATE_DR
        rst_n = 0; #5; rst_n = 1;
        
        // Wait a bit before firmware continues
        #100;
    end

    // Instantiate verification SoC wrapper
    soc_verif_top u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (1'b0),
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo),
        
        // External UVM AXI Master
        .ext_awid    (axi_master_vif.awid),
        .ext_awaddr  (axi_master_vif.awaddr),
        .ext_awlen   (axi_master_vif.awlen),
        .ext_awsize  (axi_master_vif.awsize),
        .ext_awburst (axi_master_vif.awburst),
        .ext_awlock  (axi_master_vif.awlock),
        .ext_awcache (axi_master_vif.awcache),
        .ext_awprot  (axi_master_vif.awprot),
        .ext_awvalid (axi_master_vif.awvalid),
        .ext_awready (axi_master_vif.awready),
        .ext_wdata   (axi_master_vif.wdata),
        .ext_wstrb   (axi_master_vif.wstrb),
        .ext_wlast   (axi_master_vif.wlast),
        .ext_wvalid  (axi_master_vif.wvalid),
        .ext_wready  (axi_master_vif.wready),
        .ext_bid     (axi_master_vif.bid),
        .ext_bresp   (axi_master_vif.bresp),
        .ext_bvalid  (axi_master_vif.bvalid),
        .ext_bready  (axi_master_vif.bready),
        .ext_arid    (axi_master_vif.arid),
        .ext_araddr  (axi_master_vif.araddr),
        .ext_arlen   (axi_master_vif.arlen),
        .ext_arsize  (axi_master_vif.arsize),
        .ext_arburst (axi_master_vif.arburst),
        .ext_arlock  (axi_master_vif.arlock),
        .ext_arcache (axi_master_vif.arcache),
        .ext_arprot  (axi_master_vif.arprot),
        .ext_arvalid (axi_master_vif.arvalid),
        .ext_arready (axi_master_vif.arready),
        .ext_rid     (axi_master_vif.rid),
        .ext_rdata   (axi_master_vif.rdata),
        .ext_rresp   (axi_master_vif.rresp),
        .ext_rlast   (axi_master_vif.rlast),
        .ext_rvalid  (axi_master_vif.rvalid),
        .ext_rready  (axi_master_vif.rready),

        .s0_awid       (mon_s0_awid),
        .s0_awaddr     (mon_s0_awaddr),
        .s0_awlen      (mon_s0_awlen),
        .s0_awsize     (mon_s0_awsize),
        .s0_awburst    (mon_s0_awburst),
        .s0_awlock     (mon_s0_awlock),
        .s0_awcache    (mon_s0_awcache),
        .s0_awprot     (mon_s0_awprot),
        .s0_awvalid    (mon_s0_awvalid),
        .s0_awready    (mon_s0_awready),
        .s0_wdata      (mon_s0_wdata),
        .s0_wstrb      (mon_s0_wstrb),
        .s0_wlast      (mon_s0_wlast),
        .s0_wvalid     (mon_s0_wvalid),
        .s0_wready     (mon_s0_wready),
        .s0_bid        (mon_s0_bid),
        .s0_bresp      (mon_s0_bresp),
        .s0_bvalid     (mon_s0_bvalid),
        .s0_bready     (mon_s0_bready),
        .s0_arid       (mon_s0_arid),
        .s0_araddr     (mon_s0_araddr),
        .s0_arlen      (mon_s0_arlen),
        .s0_arsize     (mon_s0_arsize),
        .s0_arburst    (mon_s0_arburst),
        .s0_arlock     (mon_s0_arlock),
        .s0_arcache    (mon_s0_arcache),
        .s0_arprot     (mon_s0_arprot),
        .s0_arvalid    (mon_s0_arvalid),
        .s0_arready    (mon_s0_arready),
        .s0_rid        (mon_s0_rid),
        .s0_rdata      (mon_s0_rdata),
        .s0_rresp      (mon_s0_rresp),
        .s0_rlast      (mon_s0_rlast),
        .s0_rvalid     (mon_s0_rvalid),
        .s0_rready     (mon_s0_rready),

        .mailbox_valid (mailbox_valid),
        .mailbox_wdata (mailbox_wdata),
        .ex_reg_write  (ex_reg_write),
        .ex_pc         (ex_pc),
        .jtag_axi_state(jtag_axi_state)
    );

    // Mailbox Monitor for Regression Tests
    always @(posedge clk) begin
        if (mailbox_valid) begin
            if (mailbox_wdata == 32'hdeadbeef) begin
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (mailbox_wdata == 32'hdeaddead) begin
                $display("REGRESSION_TEST_FAILED");
                $finish;
            end
        end
    end



    // Debug PC Trace at end
    initial begin
        #5000000000; // wait 5 ms
        $display("START TRACING PCs to catch deadlock");
        for (int i=0; i<100; i++) begin
            @(posedge clk);
            if (ex_reg_write)
                $display("[%t] EX PC = %h", $time, ex_pc);
        end
        $finish;
    end

    // Bind SoC Master outputs -> UVM VIP inputs
    assign axi_vif.awid    = mon_s0_awid;
    assign axi_vif.awaddr  = mon_s0_awaddr;
    assign axi_vif.awlen   = mon_s0_awlen;
    assign axi_vif.awsize  = mon_s0_awsize;
    assign axi_vif.awburst = mon_s0_awburst;
    assign axi_vif.awlock  = mon_s0_awlock;
    assign axi_vif.awcache = mon_s0_awcache;
    assign axi_vif.awprot  = mon_s0_awprot;
    assign axi_vif.awvalid = mon_s0_awvalid;
    assign axi_vif.awready = mon_s0_awready;
    
    assign axi_vif.wid     = 4'd0; // s_wid removed in some AXI4, default to 0
    assign axi_vif.wdata   = mon_s0_wdata;
    assign axi_vif.wstrb   = mon_s0_wstrb;
    assign axi_vif.wlast   = mon_s0_wlast;
    assign axi_vif.wvalid  = mon_s0_wvalid;
    assign axi_vif.wready  = mon_s0_wready;
    
    assign axi_vif.bid     = mon_s0_bid;
    assign axi_vif.bresp   = mon_s0_bresp;
    assign axi_vif.bvalid  = mon_s0_bvalid;
    assign axi_vif.bready  = mon_s0_bready;
    
    assign axi_vif.arid    = mon_s0_arid;
    assign axi_vif.araddr  = mon_s0_araddr;
    assign axi_vif.arlen   = mon_s0_arlen;
    assign axi_vif.arsize  = mon_s0_arsize;
    assign axi_vif.arburst = mon_s0_arburst;
    assign axi_vif.arlock  = mon_s0_arlock;
    assign axi_vif.arcache = mon_s0_arcache;
    assign axi_vif.arprot  = mon_s0_arprot;
    assign axi_vif.arvalid = mon_s0_arvalid;
    assign axi_vif.arready = mon_s0_arready;
    
    assign axi_vif.rid     = mon_s0_rid;
    assign axi_vif.rdata   = mon_s0_rdata;
    assign axi_vif.rresp   = mon_s0_rresp;
    assign axi_vif.rlast   = mon_s0_rlast;
    assign axi_vif.rvalid  = mon_s0_rvalid;
    assign axi_vif.rready  = mon_s0_rready;

    axi_protocol_checker #(
        .CHECKER_NAME("ext_axi_master"),
        .REQUIRE_SINGLE_OUTSTANDING(1'b1),
        .REQUIRE_W_AFTER_AW(1'b1)
    ) u_ext_axi_protocol_checker (
        .clk     (clk),
        .rst_n   (rst_n),
        .awid    (axi_master_vif.awid),
        .awaddr  (axi_master_vif.awaddr),
        .awlen   (axi_master_vif.awlen),
        .awsize  (axi_master_vif.awsize),
        .awburst (axi_master_vif.awburst),
        .awlock  (axi_master_vif.awlock),
        .awcache (axi_master_vif.awcache),
        .awprot  (axi_master_vif.awprot),
        .awvalid (axi_master_vif.awvalid),
        .awready (axi_master_vif.awready),
        .wdata   (axi_master_vif.wdata),
        .wstrb   (axi_master_vif.wstrb),
        .wlast   (axi_master_vif.wlast),
        .wvalid  (axi_master_vif.wvalid),
        .wready  (axi_master_vif.wready),
        .bid     (axi_master_vif.bid),
        .bresp   (axi_master_vif.bresp),
        .bvalid  (axi_master_vif.bvalid),
        .bready  (axi_master_vif.bready),
        .arid    (axi_master_vif.arid),
        .araddr  (axi_master_vif.araddr),
        .arlen   (axi_master_vif.arlen),
        .arsize  (axi_master_vif.arsize),
        .arburst (axi_master_vif.arburst),
        .arlock  (axi_master_vif.arlock),
        .arcache (axi_master_vif.arcache),
        .arprot  (axi_master_vif.arprot),
        .arvalid (axi_master_vif.arvalid),
        .arready (axi_master_vif.arready),
        .rid     (axi_master_vif.rid),
        .rdata   (axi_master_vif.rdata),
        .rresp   (axi_master_vif.rresp),
        .rlast   (axi_master_vif.rlast),
        .rvalid  (axi_master_vif.rvalid),
        .rready  (axi_master_vif.rready)
    );

    axi_protocol_checker #(
        .CHECKER_NAME("sram_axi_monitor"),
        .REQUIRE_SINGLE_OUTSTANDING(1'b1),
        .REQUIRE_W_AFTER_AW(1'b1)
    ) u_sram_axi_protocol_checker (
        .clk     (clk),
        .rst_n   (rst_n),
        .awid    (axi_vif.awid),
        .awaddr  (axi_vif.awaddr),
        .awlen   (axi_vif.awlen),
        .awsize  (axi_vif.awsize),
        .awburst (axi_vif.awburst),
        .awlock  (axi_vif.awlock),
        .awcache (axi_vif.awcache),
        .awprot  (axi_vif.awprot),
        .awvalid (axi_vif.awvalid),
        .awready (axi_vif.awready),
        .wdata   (axi_vif.wdata),
        .wstrb   (axi_vif.wstrb),
        .wlast   (axi_vif.wlast),
        .wvalid  (axi_vif.wvalid),
        .wready  (axi_vif.wready),
        .bid     (axi_vif.bid),
        .bresp   (axi_vif.bresp),
        .bvalid  (axi_vif.bvalid),
        .bready  (axi_vif.bready),
        .arid    (axi_vif.arid),
        .araddr  (axi_vif.araddr),
        .arlen   (axi_vif.arlen),
        .arsize  (axi_vif.arsize),
        .arburst (axi_vif.arburst),
        .arlock  (axi_vif.arlock),
        .arcache (axi_vif.arcache),
        .arprot  (axi_vif.arprot),
        .arvalid (axi_vif.arvalid),
        .arready (axi_vif.arready),
        .rid     (axi_vif.rid),
        .rdata   (axi_vif.rdata),
        .rresp   (axi_vif.rresp),
        .rlast   (axi_vif.rlast),
        .rvalid  (axi_vif.rvalid),
        .rready  (axi_vif.rready)
    );

    initial begin
        uvm_config_db#(virtual axi_if)::set(null, "*env.m_axi_agent*", "vif", axi_vif);
        uvm_config_db#(virtual axi_master_if)::set(null, "*env.m_axi_master_agent*", "vif", axi_master_vif);
        
        $display("========================================");
        $display("  Starting MIPS32 SoC UVM Environment   ");
        $display("========================================");
        
        run_test("soc_base_test");
    end

    initial begin
        // Waveform dumping can be added here
    end

endmodule
