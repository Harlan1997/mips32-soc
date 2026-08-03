// Vendor-neutral UART pad boundary. Disabled outputs are safe idle and inputs inactive.
module uart_pad_wrapper (
    input wire enable, input wire uart_tx_i, input wire uart_rts_n_i, input wire uart_dtr_n_i,
    output wire uart_tx_pad, output wire uart_rts_n_pad, output wire uart_dtr_n_pad,
    input wire uart_rx_pad, input wire uart_cts_n_pad, input wire uart_dsr_n_pad,
    input wire uart_dcd_n_pad, input wire uart_ri_n_pad,
    output wire uart_rx_o, output wire uart_cts_n_o, output wire uart_dsr_n_o,
    output wire uart_dcd_n_o, output wire uart_ri_n_o
);
    assign uart_tx_pad = enable ? uart_tx_i : 1'b1;
    assign uart_rts_n_pad = enable ? uart_rts_n_i : 1'b1;
    assign uart_dtr_n_pad = enable ? uart_dtr_n_i : 1'b1;
    assign uart_rx_o = enable ? uart_rx_pad : 1'b1;
    assign uart_cts_n_o = enable ? uart_cts_n_pad : 1'b0;
    assign uart_dsr_n_o = enable ? uart_dsr_n_pad : 1'b0;
    assign uart_dcd_n_o = enable ? uart_dcd_n_pad : 1'b0;
    assign uart_ri_n_o = enable ? uart_ri_n_pad : 1'b1;
endmodule
