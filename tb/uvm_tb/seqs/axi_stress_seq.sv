`ifndef AXI_STRESS_SEQ_SV
`define AXI_STRESS_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_transaction.sv"

class axi_stress_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_stress_seq)

    function new(string name = "axi_stress_seq");
        super.new(name);
    endfunction

    task body();
        axi_transaction tr;
        `uvm_info("STRESS_SEQ", "Starting heavy AXI stress traffic...", UVM_LOW)
        
        forever begin
            tr = axi_transaction::type_id::create("tr");
            start_item(tr);
            
            if(!tr.randomize() with {
                trans_type dist {AXI_READ := 50, AXI_WRITE := 50};
                addr >= 32'h00004000; // Avoid overwriting firmware code (0x0-0x3fff)
                addr <= 32'h00010000; // Constrain to SRAM region
                addr[1:0] == 2'b00;   // Word aligned
                len inside {[0:15]};  // Bursts up to 16 beats
                size == 3'b010;       // 4 bytes per beat
                burst == 2'b01;       // INCR burst
                
                foreach(data[i]) data[i] != 32'hdeadbeef; // Don't trigger mailbox success
                foreach(data[i]) data[i] != 32'hdeaddead; // Don't trigger mailbox fail
            }) `uvm_fatal("SEQ", "Randomization failed")
            
            finish_item(tr);
            
            // Wait random number of cycles before next transaction to create varied pressure
            #($urandom_range(0, 10) * 10);
        end
    endtask
endclass

`endif
