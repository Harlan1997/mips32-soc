`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../tests/soc_base_test.sv"
`include "../tests/soc_bus_stress_test.sv"
`include "../agents/axi_if.sv"

module tb_top;
    logic clk;
    logic rst_n;
    
    // External GPIO and JTAG (stubbed for now)
    wire [31:0] gpio_pins;
    logic tck, tms, tdi, tdo;
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
        jtag_write_dr_65b({1'b1, 32'hFFFF_FFFF, 32'hFFFF_FFFF}); // Unmapped addr, will trigger SLVERR but JTAG handles it
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
                wait(u_soc.u_jtag_debug_top.axi_state == 3'd1); // ST_AW
                rst_n = 0; #5; rst_n = 1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b1, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(u_soc.u_jtag_debug_top.axi_state == 3'd2); // ST_W
                rst_n = 0; #5; rst_n = 1;
            end
        join
        
        fork
            begin
                jtag_write_ir(4'h8);
                jtag_write_dr_65b({1'b0, 32'h4000_0010, 32'h00000000});
            end
            begin
                wait(u_soc.u_jtag_debug_top.axi_state == 3'd4); // ST_AR
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

    // Instantiate SoC
    mips_soc u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
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
        .ext_awlock  (2'b00),
        .ext_awcache (4'b0000),
        .ext_awprot  (3'b000),
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
        .ext_arlock  (2'b00),
        .ext_arcache (4'b0000),
        .ext_arprot  (3'b000),
        .ext_arvalid (axi_master_vif.arvalid),
        .ext_arready (axi_master_vif.arready),
        .ext_rid     (axi_master_vif.rid),
        .ext_rdata   (axi_master_vif.rdata),
        .ext_rresp   (axi_master_vif.rresp),
        .ext_rlast   (axi_master_vif.rlast),
        .ext_rvalid  (axi_master_vif.rvalid),
        .ext_rready  (axi_master_vif.rready)
    );

    // Mailbox Monitor for Regression Tests
    always @(posedge clk) begin
        if (u_soc.u_core.u_cpu.data_req && u_soc.u_core.u_cpu.data_we && u_soc.u_core.u_cpu.data_addr == 32'ha000fffc) begin
            if (u_soc.u_core.u_cpu.data_wdata == 32'hdeadbeef) begin
                $display("REGRESSION_TEST_SUCCESS");
                $finish;
            end else if (u_soc.u_core.u_cpu.data_wdata == 32'hdeaddead) begin
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
            if (u_soc.u_core.u_cpu.ex_reg_write)
                $display("[%t] EX PC = %h", $time, u_soc.u_core.u_cpu.ex_pc_plus_8 - 8);
        end
        $finish;
    end

    // Instantiate UVM AXI Interfaces
    axi_if axi_vif(clk, rst_n); // Slave for memory
    axi_if axi_master_vif(clk, rst_n); // Master for injection

    // Bind SoC Master outputs -> UVM VIP inputs
    assign axi_vif.awid    = u_soc.s0_awid;
    assign axi_vif.awaddr  = u_soc.s0_awaddr;
    assign axi_vif.awlen   = u_soc.s0_awlen;
    assign axi_vif.awsize  = u_soc.s0_awsize;
    assign axi_vif.awburst = u_soc.s0_awburst;
    assign axi_vif.awvalid = u_soc.s0_awvalid;
    
    assign axi_vif.wid     = 4'd0; // s_wid removed in some AXI4, default to 0
    assign axi_vif.wdata   = u_soc.s0_wdata;
    assign axi_vif.wstrb   = u_soc.s0_wstrb;
    assign axi_vif.wlast   = u_soc.s0_wlast;
    assign axi_vif.wvalid  = u_soc.s0_wvalid;
    
    assign axi_vif.bready  = u_soc.s0_bready;
    
    assign axi_vif.arid    = u_soc.s0_arid;
    assign axi_vif.araddr  = u_soc.s0_araddr;
    assign axi_vif.arlen   = u_soc.s0_arlen;
    assign axi_vif.arsize  = u_soc.s0_arsize;
    assign axi_vif.arburst = u_soc.s0_arburst;
    assign axi_vif.arvalid = u_soc.s0_arvalid;
    
    assign axi_vif.rready  = u_soc.s0_rready;

    // Force UVM VIP outputs -> SoC Slave inputs (Overrides internal axi_sram!)
    /*
    initial begin
        force u_soc.s0_awready = axi_vif.awready;
        force u_soc.s0_wready  = axi_vif.wready;
        force u_soc.s0_bvalid  = axi_vif.bvalid;
        force u_soc.s0_bresp   = axi_vif.bresp;
        force u_soc.s0_bid     = axi_vif.bid;
        
        force u_soc.s0_arready = axi_vif.arready;
        force u_soc.s0_rvalid  = axi_vif.rvalid;
        force u_soc.s0_rdata   = axi_vif.rdata;
        force u_soc.s0_rresp   = axi_vif.rresp;
        force u_soc.s0_rlast   = axi_vif.rlast;
        force u_soc.s0_rid     = axi_vif.rid;
    end
    */

    initial begin
        uvm_config_db#(virtual axi_if)::set(null, "*env.m_axi_agent*", "vif", axi_vif);
        uvm_config_db#(virtual axi_if)::set(null, "*env.m_axi_master_agent*", "vif", axi_master_vif);
        
        $display("========================================");
        $display("  Starting MIPS32 SoC UVM Environment   ");
        $display("========================================");
        
        run_test("soc_base_test");
    end

    initial begin
        // Waveform dumping can be added here
    end

endmodule
