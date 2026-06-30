`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "axi_transaction.sv"

class axi_driver extends uvm_driver #(axi_transaction);
    `uvm_component_utils(axi_driver)

    virtual axi_if vif;
    
    // Memory array for slave mode emulation
    logic [7:0] mem[longint];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF",{"virtual interface must be set for: ",get_full_name(),".vif"});
            
        // Load firmware into mem
        load_firmware();
    endfunction

    function void load_firmware();
        int fd;
        string line;
        int addr = 32'h00000000; // Boot address (aliased)
        logic [31:0] word;
        
        fd = $fopen("firmware.hex", "r");
        if (fd) begin
            while (!$feof(fd)) begin
                if ($fscanf(fd, "%h\n", word) == 1) begin
                    mem[{addr[31:2], 2'b00}] = word[7:0];
                    mem[{addr[31:2], 2'b01}] = word[15:8];
                    mem[{addr[31:2], 2'b10}] = word[23:16];
                    mem[{addr[31:2], 2'b11}] = word[31:24];
                    addr += 4;
                end
            end
            $fclose(fd);
            `uvm_info("DRIVER", "Firmware loaded successfully.", UVM_LOW)
        end else begin
            `uvm_warning("DRIVER", "Failed to open firmware.hex")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.awready <= 0;
        vif.wready <= 0;
        vif.bvalid <= 0;
        vif.bresp <= 0;
        vif.bid <= 0;
        vif.arready <= 0;
        vif.rvalid <= 0;
        vif.rdata <= 0;
        vif.rresp <= 0;
        vif.rlast <= 0;
        vif.rid <= 0;
        
        wait(vif.rst_n);
        
        fork
            handle_write_channels();
            handle_read_channels();
        join
    endtask

    task handle_write_channels();
        axi_transaction req = new();
        logic [31:0] waddr;
        logic [31:0] saved_awaddr;
        forever begin
            // Wait for AW channel
            vif.cb.awready <= 1'b1;
            @(vif.cb);
            while(vif.cb.awvalid !== 1'b1) @(vif.cb);
            
            saved_awaddr = vif.cb.awaddr;
            
            // Randomize delays locally for slave response
            req.len.rand_mode(0);
            req.len = vif.cb.awlen;
            $display("[%t] AXI VIP: Received AWVALID for AWADDR=%h, AWLEN=%d", $time, saved_awaddr, req.len);
            if(!req.randomize()) `uvm_fatal("DRV", "Randomize failed");
            
            // AW Channel
            repeat(req.aw_delay) @(vif.cb);
            vif.cb.awready <= 1'b1;
            @(vif.cb);
            vif.cb.awready <= 1'b0;
            
            // W Channel
            for(int i=0; i<=req.len; i++) begin
                repeat(req.w_delay[i]) @(vif.cb);
                vif.cb.wready <= 1'b1;
                @(vif.cb);
                while(vif.cb.wvalid !== 1'b1) @(vif.cb);
                $display("[%t] AXI VIP: Received WVALID, WLAST=%b", $time, vif.cb.wlast);
                
                waddr = (saved_awaddr + (i * 4)) & 32'h1FFFFFFF;
                if (vif.cb.wstrb[0]) mem[{waddr[31:2], 2'b00}] = vif.cb.wdata[7:0];
                if (vif.cb.wstrb[1]) mem[{waddr[31:2], 2'b01}] = vif.cb.wdata[15:8];
                if (vif.cb.wstrb[2]) mem[{waddr[31:2], 2'b10}] = vif.cb.wdata[23:16];
                if (vif.cb.wstrb[3]) mem[{waddr[31:2], 2'b11}] = vif.cb.wdata[31:24];
                
                vif.cb.wready <= 1'b0;
            end
            
            // B Channel
            repeat(req.b_delay) @(vif.cb);
            vif.cb.bvalid <= 1'b1;
            
            // Error Injection for non-CPU/DMA masters to hit Arbiter error FSMs
            if (vif.cb.awid >= 4 && $urandom_range(0, 9) < 2) begin
                vif.cb.bresp <= 2'b10; // SLVERR (20% chance)
            end else begin
                vif.cb.bresp <= 2'b00; // OKAY
            end
            
            vif.cb.bid    <= vif.cb.awid;
            @(vif.cb);
            while(vif.cb.bready !== 1'b1) begin
                $display("[%t] AXI VIP: Waiting for BREADY... vif.cb.bready=%b", $time, vif.cb.bready);
                @(vif.cb);
            end
            $display("[%t] AXI VIP: BREADY Handshake Complete", $time);
            vif.cb.bvalid <= 1'b0;
        end
    endtask
    
    task handle_read_channels();
        axi_transaction req = new();
        logic [31:0] saved_arid;
        logic [31:0] saved_araddr;
        logic [3:0]  saved_arlen;
        
        forever begin
            while(vif.cb.arvalid !== 1'b1) @(vif.cb);
            
            saved_arid = vif.cb.arid;
            saved_araddr = vif.cb.araddr;
            saved_arlen = vif.cb.arlen;
            
            req.len.rand_mode(0);
            req.len = saved_arlen;
            if(!req.randomize()) `uvm_fatal("DRV", "Randomize failed");
            
            // Acknowledge AR
            repeat(req.ar_delay) @(vif.cb);
            vif.cb.arready <= 1'b1;
            @(vif.cb);
            vif.cb.arready <= 1'b0;
            
            // Drive R Channel
            for(int i=0; i<=saved_arlen; i++) begin
                logic [31:0] raddr = (saved_araddr + (i * 4)) & 32'h1FFFFFFF;
                
                repeat(req.r_delay[i]) @(vif.cb);
                
                vif.cb.rvalid <= 1'b1;
                
                if (saved_arid >= 4 && $urandom_range(0, 9) < 2) begin
                    vif.cb.rresp <= 2'b10; // SLVERR
                end else begin
                    vif.cb.rresp <= 2'b00; 
                end
                
                vif.cb.rid    <= saved_arid;
                vif.cb.rlast  <= (i == saved_arlen) ? 1'b1 : 1'b0;
                
                vif.cb.rdata[7:0]   <= mem.exists({raddr[31:2], 2'b00}) ? mem[{raddr[31:2], 2'b00}] : 8'd0;
                vif.cb.rdata[15:8]  <= mem.exists({raddr[31:2], 2'b01}) ? mem[{raddr[31:2], 2'b01}] : 8'd0;
                vif.cb.rdata[23:16] <= mem.exists({raddr[31:2], 2'b10}) ? mem[{raddr[31:2], 2'b10}] : 8'd0;
                vif.cb.rdata[31:24] <= mem.exists({raddr[31:2], 2'b11}) ? mem[{raddr[31:2], 2'b11}] : 8'd0;
                
                @(vif.cb);
                while(vif.cb.rready !== 1'b1) @(vif.cb);
            end
            
            vif.cb.rvalid <= 1'b0;
            vif.cb.rlast  <= 1'b0;
        end
    endtask

endclass

`endif
