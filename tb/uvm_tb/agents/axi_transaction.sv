`ifndef AXI_TRANSACTION_SV
`define AXI_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

typedef enum {AXI_READ, AXI_WRITE} axi_trans_type_e;

class axi_transaction extends uvm_sequence_item;
    
    rand axi_trans_type_e trans_type;
    
    // Address Channel
    rand logic [3:0]  id;
    rand logic [31:0] addr;
    rand logic [3:0]  len;
    rand logic [2:0]  size;
    rand logic [1:0]  burst;

    // Data payload
    rand logic [31:0] data[];
    rand logic [3:0]  strb[];

    // Response
    rand logic [1:0]  resp[];

    // Delay variables (useful for slave driver backpressure)
    rand int unsigned aw_delay;
    rand int unsigned w_delay[];
    rand int unsigned b_delay;
    rand int unsigned ar_delay;
    rand int unsigned r_delay[];

    `uvm_object_utils_begin(axi_transaction)
        `uvm_field_enum(axi_trans_type_e, trans_type, UVM_ALL_ON)
        `uvm_field_int(id, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(len, UVM_ALL_ON)
        `uvm_field_int(size, UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON)
        `uvm_field_array_int(strb, UVM_ALL_ON)
        `uvm_field_array_int(resp, UVM_ALL_ON)
        `uvm_field_int(aw_delay, UVM_ALL_ON)
        `uvm_field_array_int(w_delay, UVM_ALL_ON)
        `uvm_field_int(b_delay, UVM_ALL_ON)
        `uvm_field_int(ar_delay, UVM_ALL_ON)
        `uvm_field_array_int(r_delay, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint delay_c {
        aw_delay dist {0 := 70, [1:10] := 20, [50:150] := 10};
        b_delay  dist {0 := 80, [1:10] := 20};
        ar_delay dist {0 := 70, [1:10] := 20, [50:150] := 10};
    }
    
    constraint w_r_delay_c {
        w_delay.size() == len + 1;
        r_delay.size() == len + 1;
        foreach(w_delay[i]) {
            w_delay[i] dist {0 := 80, [1:10] := 20};
        }
        foreach(r_delay[i]) {
            if (i == 0) {
                // First read beat: simulate CAS latency + occasional refresh stall
                r_delay[i] dist {[5:20] := 70, [50:200] := 30};
            } else {
                // Subsequent read beats: occasional bubbles
                r_delay[i] dist {0 := 80, [1:5] := 20};
            }
        }
    }

    constraint array_sizes {
        data.size() == len + 1;
        strb.size() == len + 1;
        resp.size() == len + 1;
    }

    function new(string name = "axi_transaction");
        super.new(name);
    endfunction

endclass

`endif
