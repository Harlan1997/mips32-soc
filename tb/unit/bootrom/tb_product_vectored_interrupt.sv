`timescale 1ns/1ps

// Product CP0 vector contract: an enabled software IP1 with Cause.IV=1 and
// IntCtl.VS=1 must enter EBase + 0x200 + 1*32, via the kseg0 direct map.
module tb_product_vectored_interrupt;
    reg clk;
    reg rst_n;
    reg tck;
    reg tms;
    reg tdi;
    reg spi_miso;
    wire tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire [31:0] gpio_pins;

    integer cycles;
    reg reset_seen;
    reg vector_pc_seen;
    reg vector_pa_seen;
    reg cp0_state_seen;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate

    mips_soc u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo)
    );

    always #5 clk = ~clk;

    task fail;
        input [255:0] message;
        begin
            $display("ERROR: %0s", message);
            $display("REGRESSION_TEST_FAILED product_vectored_interrupt");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_seen = 1'b0;
            vector_pc_seen = 1'b0;
            vector_pa_seen = 1'b0;
            cp0_state_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0220)
                vector_pc_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr == 32'h8000_0220 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr == 32'h0000_0220)
                vector_pa_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1] == 1'b1 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[23] == 1'b1 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] == 5'h00 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_intctl_vs == 5'd1)
                cp0_state_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC)
                fail("interrupt was not accepted before the firmware failure mailbox");

            if (reset_seen && vector_pc_seen && vector_pa_seen && cp0_state_seen) begin
                $display("REGRESSION_TEST_SUCCESS product_vectored_interrupt");
                $finish;
            end

            if (cycles > 3000) begin
                $display("DEBUG: pc=%h if_va=%h inst_pa=%h status=%h cause=%h intctl=%h intr=%b offset=%h",
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.intctl_val,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.intr_req,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.cp0_vint_offset);
                if (!reset_seen) fail("reset PC was not observed in Boot ROM");
                if (!cp0_state_seen) fail("CP0 did not accept an IV-enabled interrupt");
                if (!vector_pc_seen) fail("CPU did not fetch the IP1 vectored interrupt PC");
                fail("vectored interrupt fetch did not use the kseg0 direct map");
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        spi_miso = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
