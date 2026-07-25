`ifndef SOC_OBSERVATION_BIND_SV
`define SOC_OBSERVATION_BIND_SV

module soc_observation_bind (
    soc_observation_if.producer obs_if,

    input logic        mailbox_valid,
    input logic [31:0] mailbox_wdata,
    input logic        ex_reg_write,
    input logic [31:0] ex_pc,
    input logic [2:0]  jtag_axi_state,
    input logic        cpu_cp0_except_req,
    input logic [4:0]  cpu_cp0_except_code,
    input logic        cpu_cp0_intr_req,
    input logic        cpu_cp0_eret,
    input logic        cpu_cp0_exl,
    input logic [31:0] cpu_cp0_epc
);

    assign obs_if.mailbox_valid       = mailbox_valid;
    assign obs_if.mailbox_wdata       = mailbox_wdata;
    assign obs_if.ex_reg_write        = ex_reg_write;
    assign obs_if.ex_pc               = ex_pc;
    assign obs_if.jtag_axi_state      = jtag_axi_state;
    assign obs_if.cpu_cp0_except_req  = cpu_cp0_except_req;
    assign obs_if.cpu_cp0_except_code = cpu_cp0_except_code;
    assign obs_if.cpu_cp0_intr_req    = cpu_cp0_intr_req;
    assign obs_if.cpu_cp0_eret        = cpu_cp0_eret;
    assign obs_if.cpu_cp0_exl         = cpu_cp0_exl;
    assign obs_if.cpu_cp0_epc         = cpu_cp0_epc;

endmodule

`endif
