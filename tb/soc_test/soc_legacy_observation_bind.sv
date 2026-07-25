`ifndef SOC_LEGACY_OBSERVATION_BIND_SV
`define SOC_LEGACY_OBSERVATION_BIND_SV

module soc_legacy_observation_bind (
    soc_legacy_observation_if.producer obs_if,

    input logic        mailbox_valid,
    input logic [31:0] mailbox_wdata,
    input logic [31:0] trace_pc,
    input logic        cp0_except_req,
    input logic [4:0]  cp0_except_code,
    input logic        cp0_intr_req,
    input logic        cp0_exl,
    input logic        cp0_eret,
    input logic        uart_tx_valid,
    input logic [7:0]  uart_tx_data,
    input logic        core_global_stall,
    input logic [3:0]  dcache_state,
    input logic [3:0]  dcache_next_state,
    input logic [31:0] dcache_req_buf_addr,
    input logic        dcache_req_buf_we,
    input logic        dcache_uncacheable,
    input logic        dcache_awvalid,
    input logic        dcache_wvalid,
    input logic        dcache_bready
);

    assign obs_if.mailbox_valid       = mailbox_valid;
    assign obs_if.mailbox_wdata       = mailbox_wdata;
    assign obs_if.trace_pc            = trace_pc;
    assign obs_if.cp0_except_req      = cp0_except_req;
    assign obs_if.cp0_except_code     = cp0_except_code;
    assign obs_if.cp0_intr_req        = cp0_intr_req;
    assign obs_if.cp0_exl             = cp0_exl;
    assign obs_if.cp0_eret            = cp0_eret;
    assign obs_if.uart_tx_valid       = uart_tx_valid;
    assign obs_if.uart_tx_data        = uart_tx_data;
    assign obs_if.core_global_stall   = core_global_stall;
    assign obs_if.dcache_state        = dcache_state;
    assign obs_if.dcache_next_state   = dcache_next_state;
    assign obs_if.dcache_req_buf_addr = dcache_req_buf_addr;
    assign obs_if.dcache_req_buf_we   = dcache_req_buf_we;
    assign obs_if.dcache_uncacheable  = dcache_uncacheable;
    assign obs_if.dcache_awvalid      = dcache_awvalid;
    assign obs_if.dcache_wvalid       = dcache_wvalid;
    assign obs_if.dcache_bready       = dcache_bready;

endmodule

`endif
