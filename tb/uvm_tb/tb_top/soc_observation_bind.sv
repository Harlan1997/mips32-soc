`ifndef SOC_OBSERVATION_BIND_SV
`define SOC_OBSERVATION_BIND_SV

module soc_observation_bind (
    soc_observation_if.producer obs_if,

    input logic [31:0] retire_schema,
    input logic        retire_valid,
    input logic [31:0] retire_pc,
    input logic [31:0] retire_instr,
    input logic [31:0] retire_next_pc,
    input logic        retire_gpr_we,
    input logic [4:0]  retire_gpr_addr,
    input logic [31:0] retire_gpr_data,
    input logic        retire_cp0_we,
    input logic [4:0]  retire_cp0_addr,
    input logic [2:0]  retire_cp0_sel,
    input logic [31:0] retire_cp0_data,
    input logic [1023:0] retire_fpr_state,
    input logic [31:0] retire_fcsr_state,
    input logic        retire_mem_valid,
    input logic        retire_mem_read,
    input logic        retire_mem_write,
    input logic [31:0] retire_mem_addr,
    input logic [31:0] retire_mem_wdata,
    input logic [3:0]  retire_mem_be,
    input logic [31:0] retire_mem_rdata,
    input logic        retire_except,
    input logic [4:0]  retire_except_code,
    input logic        retire_bd,
    input logic        retire_eret,

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

    assign obs_if.retire_schema      = retire_schema;
    assign obs_if.retire_valid       = retire_valid;
    assign obs_if.retire_pc          = retire_pc;
    assign obs_if.retire_instr       = retire_instr;
    assign obs_if.retire_next_pc     = retire_next_pc;
    assign obs_if.retire_gpr_we      = retire_gpr_we;
    assign obs_if.retire_gpr_addr    = retire_gpr_addr;
    assign obs_if.retire_gpr_data    = retire_gpr_data;
    assign obs_if.retire_cp0_we      = retire_cp0_we;
    assign obs_if.retire_cp0_addr    = retire_cp0_addr;
    assign obs_if.retire_cp0_sel     = retire_cp0_sel;
    assign obs_if.retire_cp0_data    = retire_cp0_data;
    assign obs_if.retire_fpr_state   = retire_fpr_state;
    assign obs_if.retire_fcsr_state  = retire_fcsr_state;
    assign obs_if.retire_mem_valid   = retire_mem_valid;
    assign obs_if.retire_mem_read    = retire_mem_read;
    assign obs_if.retire_mem_write   = retire_mem_write;
    assign obs_if.retire_mem_addr    = retire_mem_addr;
    assign obs_if.retire_mem_wdata   = retire_mem_wdata;
    assign obs_if.retire_mem_be      = retire_mem_be;
    assign obs_if.retire_mem_rdata   = retire_mem_rdata;
    assign obs_if.retire_except      = retire_except;
    assign obs_if.retire_except_code = retire_except_code;
    assign obs_if.retire_bd          = retire_bd;
    assign obs_if.retire_eret         = retire_eret;
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
