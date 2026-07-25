`ifndef SOC_OBSERVATION_IF_SV
`define SOC_OBSERVATION_IF_SV

interface soc_observation_if(input logic clk, input logic rst_n);
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
