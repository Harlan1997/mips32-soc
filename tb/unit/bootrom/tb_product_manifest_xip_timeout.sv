`timescale 1ns/1ps

// The low timeout is a deterministic configuration stimulus for the real
// hardware guard. It does not force internal controller state or alter MISO.
`include "tb_product_manifest_handoff.sv"

module tb_product_manifest_xip_timeout;
    tb_product_manifest_handoff #(
        .SPI_READ_TIMEOUT_CYCLES (4),
        .EXPECT_XIP_TIMEOUT      (1)
    ) u_timeout_test ();
endmodule
