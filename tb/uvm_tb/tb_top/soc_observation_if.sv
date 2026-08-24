`ifndef SOC_OBSERVATION_IF_SV
`define SOC_OBSERVATION_IF_SV

interface soc_observation_if(input logic clk, input logic rst_n);
    logic [31:0] retire_schema;
    logic        retire_valid;
    logic [31:0] retire_pc;
    logic [31:0] retire_instr;
    logic [31:0] retire_next_pc;
    logic        retire_gpr_we;
    logic [4:0]  retire_gpr_addr;
    logic [31:0] retire_gpr_data;
    logic        retire_cp0_we;
    logic [4:0]  retire_cp0_addr;
    logic [2:0]  retire_cp0_sel;
    logic [31:0] retire_cp0_data;
    logic        retire_mem_valid, retire_mem_read, retire_mem_write;
    logic [31:0] retire_mem_addr, retire_mem_wdata, retire_mem_rdata;
    logic [3:0]  retire_mem_be;
    logic        retire_except;
    logic [4:0]  retire_except_code;
    logic        retire_bd, retire_eret;
    logic        mailbox_valid;
    logic [31:0] mailbox_wdata;
    logic        ex_reg_write;
    logic [31:0] ex_pc;
    logic [2:0]  jtag_axi_state;
    logic        cpu_cp0_except_req;
    logic [4:0]  cpu_cp0_except_code;
    logic        cpu_cp0_intr_req;
    logic        cpu_cp0_eret;
    logic        cpu_cp0_exl;
    logic [31:0] cpu_cp0_epc;

    modport producer (
        output retire_schema, output retire_valid, output retire_pc,
        output retire_instr, output retire_next_pc, output retire_gpr_we,
        output retire_gpr_addr, output retire_gpr_data, output retire_cp0_we,
        output retire_cp0_addr, output retire_cp0_sel, output retire_cp0_data,
        output retire_mem_valid, output retire_mem_read, output retire_mem_write,
        output retire_mem_addr, output retire_mem_wdata, output retire_mem_rdata,
        output retire_mem_be, output retire_except, output retire_except_code,
        output retire_bd, output retire_eret,
        output mailbox_valid,
        output mailbox_wdata,
        output ex_reg_write,
        output ex_pc,
        output jtag_axi_state,
        output cpu_cp0_except_req,
        output cpu_cp0_except_code,
        output cpu_cp0_intr_req,
        output cpu_cp0_eret,
        output cpu_cp0_exl,
        output cpu_cp0_epc
    );

    modport consumer (
        input retire_schema, input retire_valid, input retire_pc,
        input retire_instr, input retire_next_pc, input retire_gpr_we,
        input retire_gpr_addr, input retire_gpr_data, input retire_cp0_we,
        input retire_cp0_addr, input retire_cp0_sel, input retire_cp0_data,
        input retire_mem_valid, input retire_mem_read, input retire_mem_write,
        input retire_mem_addr, input retire_mem_wdata, input retire_mem_rdata,
        input retire_mem_be, input retire_except, input retire_except_code,
        input retire_bd, input retire_eret,
        input mailbox_valid,
        input mailbox_wdata,
        input ex_reg_write,
        input ex_pc,
        input jtag_axi_state,
        input cpu_cp0_except_req,
        input cpu_cp0_except_code,
        input cpu_cp0_intr_req,
        input cpu_cp0_eret,
        input cpu_cp0_exl,
        input cpu_cp0_epc
    );
endinterface

`endif
