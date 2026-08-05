`timescale 1ns/1ps
module tb_apb_ddr4_status;
    reg clk=0, rst_n=0, controller_present=0, init_done=0, training_done=0, fatal_error=0;
    reg [15:0] error_code=0; reg psel=0, penable=0, pwrite=0; reg [4:0] paddr=0; reg [31:0] pwdata=0;
    wire [31:0] prdata; wire pready, pslverr; integer errors=0;
    always #5 clk=~clk;
    apb_ddr4_status #(.ENABLE_ERROR_INJECT(1'b1)) dut(.*);
    task write(input [4:0] a,input [31:0] d); begin @(negedge clk); paddr=a;pwdata=d;psel=1;pwrite=1; @(negedge clk);penable=1; @(negedge clk);psel=0;penable=0;pwrite=0; end endtask
    task read(input [4:0] a,input [31:0] e); begin @(negedge clk);paddr=a;psel=1; @(negedge clk);penable=1;#1;if(!pready||pslverr||prdata!==e) begin $display("FAIL addr=%h got=%h exp=%h",a,prdata,e);errors=errors+1;end @(negedge clk);psel=0;penable=0; end endtask
    initial begin
        repeat(2) @(posedge clk); rst_n=1; controller_present=1; read(5'h00,32'h4444_5201); read(5'h04,32'h0000_0001);
        init_done=1; training_done=1; read(5'h04,32'h0000_0007);
        fatal_error=1; error_code=16'h0002; @(posedge clk); read(5'h08,32'h0004_0002); write(5'h0c,32'h1); read(5'h08,32'h0);
        fatal_error=0; repeat(2) @(posedge clk); fatal_error=1; error_code=16'h0004; @(posedge clk); read(5'h08,32'h0004_0004);
        fatal_error=0; write(5'h0c,32'h2); @(posedge clk); read(5'h08,32'h0004_0004);
        write(5'h0c,32'h5); read(5'h08,32'h0);
        if(errors==0)$display("REGRESSION_TEST_SUCCESS apb_ddr4_status");else $display("REGRESSION_TEST_FAILED apb_ddr4_status errors=%0d",errors);$finish;
    end
endmodule
