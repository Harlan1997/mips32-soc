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
        int unsigned beats;
        int unsigned window;
        `uvm_info("STRESS_SEQ", "Starting heavy AXI stress traffic...", UVM_LOW)

        forever begin
            tr = axi_transaction::type_id::create("tr");
            start_item(tr);

            tr.id    = $urandom_range(0, 15);
            tr.len   = $urandom_range(0, 7);
            tr.size  = 3'b010;
            tr.burst = 2'b01;
            beats = tr.len + 1;

            tr.data = new[beats];
            tr.strb = new[beats];
            tr.resp = new[beats];
            foreach (tr.data[i]) begin
                tr.data[i] = 32'h5A5A_0000 ^ $urandom();
                tr.strb[i] = 4'hF;
                tr.resp[i] = 2'b00;
            end

            if ($urandom_range(0, 99) < 50) begin
                tr.trans_type = AXI_READ;
                window = $urandom_range(0, 3);
                case (window)
                    0: tr.addr = 32'h0000_0000 + (($urandom_range(0, 16'h7F00) >> 2) << 2);
                    1: tr.addr = 32'hA000_0000 + (($urandom_range(0, 16'h7F00) >> 2) << 2);
                    2: tr.addr = 32'h1000_0000 + (($urandom_range(0, 16'h0F00) >> 2) << 2);
                    default: tr.addr = 32'hF000_0000 + (($urandom_range(0, 16'h0F00) >> 2) << 2);
                endcase
            end else begin
                tr.trans_type = AXI_WRITE;
                tr.addr = 32'hF000_0000 + (($urandom_range(0, 16'h0F00) >> 2) << 2);
                foreach (tr.data[i]) begin
                    if (tr.data[i] == 32'hDEAD_BEEF || tr.data[i] == 32'hDEAD_DEAD) begin
                        tr.data[i] = 32'h5AFE_0000 | i;
                    end
                end
            end

            finish_item(tr);

            // Wait random number of cycles before next transaction to create varied pressure
            #($urandom_range(0, 10) * 10);
        end
    endtask
endclass

`endif
