`ifndef SOC_LEGACY_OBSERVATION_IF_SV
`define SOC_LEGACY_OBSERVATION_IF_SV

interface soc_legacy_observation_if(input logic clk, input logic rst_n);
    logic        mailbox_valid;
    logic [31:0] mailbox_wdata;
    logic [31:0] trace_pc;
    logic        cp0_except_req;
    logic [4:0]  cp0_except_code;
    logic        cp0_intr_req;
    logic        cp0_exl;
    logic        cp0_eret;
    logic        uart_tx_valid;
    logic [7:0]  uart_tx_data;
    logic        core_global_stall;
    logic [3:0]  dcache_state;
    logic [3:0]  dcache_next_state;
    logic [31:0] dcache_req_buf_addr;
    logic        dcache_req_buf_we;
    logic        dcache_uncacheable;
    logic        dcache_awvalid;
    logic        dcache_wvalid;
    logic        dcache_bready;

    modport producer (
        output mailbox_valid,
        output mailbox_wdata,
        output trace_pc,
        output cp0_except_req,
        output cp0_except_code,
        output cp0_intr_req,
        output cp0_exl,
        output cp0_eret,
        output uart_tx_valid,
        output uart_tx_data,
        output core_global_stall,
        output dcache_state,
        output dcache_next_state,
        output dcache_req_buf_addr,
        output dcache_req_buf_we,
        output dcache_uncacheable,
        output dcache_awvalid,
        output dcache_wvalid,
        output dcache_bready
    );

    modport consumer (
        input mailbox_valid,
        input mailbox_wdata,
        input trace_pc,
        input cp0_except_req,
        input cp0_except_code,
        input cp0_intr_req,
        input cp0_exl,
        input cp0_eret,
        input uart_tx_valid,
        input uart_tx_data,
        input core_global_stall,
        input dcache_state,
        input dcache_next_state,
        input dcache_req_buf_addr,
        input dcache_req_buf_we,
        input dcache_uncacheable,
        input dcache_awvalid,
        input dcache_wvalid,
        input dcache_bready
    );
endinterface

`endif
