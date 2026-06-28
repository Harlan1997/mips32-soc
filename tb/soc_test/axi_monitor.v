module axi_monitor(
    input clk,
    input rst_n,
    input awvalid, input awready,
    input wvalid, input wready,
    input bvalid, input bready,
    input [31:0] awaddr,
    input [1:0] act_w_sel
);
    always @(posedge clk) begin
        if (!rst_n) begin
        end else begin
            if (awvalid || awready || wvalid || wready || bvalid || bready) begin
                $display("Time=%0t | AWV=%b AWR=%b WV=%b WR=%b BV=%b BR=%b ADDR=%h SEL=%b",
                         $time, awvalid, awready, wvalid, wready, bvalid, bready, awaddr, act_w_sel);
            end
        end
    end
endmodule
