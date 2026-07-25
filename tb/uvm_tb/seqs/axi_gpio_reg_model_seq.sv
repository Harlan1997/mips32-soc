`ifndef AXI_GPIO_REG_MODEL_SEQ_SV
`define AXI_GPIO_REG_MODEL_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "soc_config.vh"
`include "../agents/axi_transaction.sv"

class axi_gpio_reg_model_seq extends uvm_sequence#(axi_transaction);
    `uvm_object_utils(axi_gpio_reg_model_seq)

    localparam logic [31:0] GPIO_DATA_ADDR = `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET;
    localparam logic [31:0] GPIO_DIR_ADDR  = `SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DIR_OFFSET;

    function new(string name = "axi_gpio_reg_model_seq");
        super.new(name);
    endfunction

    task do_write_word(string item_name, logic [31:0] addr, logic [31:0] data);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_WRITE;
        tr.id         = $urandom_range(0, 15);
        tr.addr       = addr;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.data[0]    = data;
        tr.strb[0]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("GPIO_REG", $sformatf("%s write addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
    endtask

    task do_read_word(string item_name, logic [31:0] addr, logic [31:0] expected, logic [31:0] mask);
        axi_transaction tr;

        tr = axi_transaction::type_id::create(item_name);
        start_item(tr);
        tr.trans_type = AXI_READ;
        tr.id         = $urandom_range(0, 15);
        tr.addr       = addr;
        tr.len        = 8'h00;
        tr.size       = 3'b010;
        tr.burst      = 2'b01;
        tr.data       = new[1];
        tr.strb       = new[1];
        tr.resp       = new[1];
        tr.strb[0]    = 4'hF;
        tr.resp[0]    = `SOC_AXI_RESP_OKAY;
        finish_item(tr);

        if (tr.resp[0] != `SOC_AXI_RESP_OKAY) begin
            `uvm_error("GPIO_REG", $sformatf("%s read addr=0x%08h resp=%0h expected OKAY",
                       item_name, addr, tr.resp[0]))
        end
        if ((tr.data[0] & mask) != (expected & mask)) begin
            `uvm_error("GPIO_REG", $sformatf("%s read addr=0x%08h data=0x%08h expected=0x%08h mask=0x%08h",
                       item_name, addr, tr.data[0], expected, mask))
        end
    endtask

    task body();
        logic [31:0] data_pattern;
        logic [31:0] dir_pattern;

        data_pattern = 32'hA5A5_3C3C;
        dir_pattern  = 32'hFFFF_FFFF;

        do_write_word("gpio_dir_write_all_outputs", GPIO_DIR_ADDR, dir_pattern);
        do_read_word ("gpio_dir_read_all_outputs",  GPIO_DIR_ADDR, dir_pattern, 32'hFFFF_FFFF);

        do_write_word("gpio_data_write_pattern", GPIO_DATA_ADDR, data_pattern);
        do_read_word ("gpio_data_read_pattern",  GPIO_DATA_ADDR, data_pattern, dir_pattern);

        data_pattern = 32'h5A5A_C3C3;
        dir_pattern  = 32'hFFFF_0000;

        do_write_word("gpio_dir_write_upper_outputs", GPIO_DIR_ADDR, dir_pattern);
        do_write_word("gpio_data_write_second_pattern", GPIO_DATA_ADDR, data_pattern);
        do_read_word ("gpio_dir_read_upper_outputs",  GPIO_DIR_ADDR, dir_pattern, 32'hFFFF_FFFF);
        do_read_word ("gpio_data_read_masked_pattern", GPIO_DATA_ADDR, data_pattern, dir_pattern);
    endtask
endclass

`endif
