`timescale 1ns/1ps
module tb_uart_pad_wrapper;
    reg enable=0, tx_i=0, rts_i=0, dtr_i=0, rx=0, cts=1, dsr=1, dcd=1, ri=0;
    wire txp, rtsp, dtrp, rxo, ctso, dsro, dcdo, rio; integer errors=0;
    uart_pad_wrapper dut(.enable(enable),.uart_tx_i(tx_i),.uart_rts_n_i(rts_i),.uart_dtr_n_i(dtr_i),.uart_tx_pad(txp),.uart_rts_n_pad(rtsp),.uart_dtr_n_pad(dtrp),.uart_rx_pad(rx),.uart_cts_n_pad(cts),.uart_dsr_n_pad(dsr),.uart_dcd_n_pad(dcd),.uart_ri_n_pad(ri),.uart_rx_o(rxo),.uart_cts_n_o(ctso),.uart_dsr_n_o(dsro),.uart_dcd_n_o(dcdo),.uart_ri_n_o(rio));
    task check(input condition,input [255:0] name); begin if(!condition) begin $display("FAIL %0s",name);errors=errors+1;end end endtask
    initial begin
      #1; check(txp===1 && rtsp===1 && dtrp===1,"disabled outputs idle"); check(rxo===1 && ctso===0 && dsro===0 && dcdo===0 && rio===1,"disabled inputs safe");
      enable=1; tx_i=0; rts_i=0; dtr_i=0; rx=1; cts=0; dsr=0; dcd=0; ri=1; #1;
      check(txp===0 && rtsp===0 && dtrp===0,"enabled outputs driven"); check(rxo===1 && ctso===0 && dsro===0 && dcdo===0 && rio===1,"enabled inputs passed");
      if(errors==0)$display("REGRESSION_TEST_SUCCESS uart_pad_wrapper");else $display("REGRESSION_TEST_FAILED uart_pad_wrapper errors=%0d",errors); $finish;
    end
endmodule
