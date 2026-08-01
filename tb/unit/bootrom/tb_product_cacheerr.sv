`timescale 1ns/1ps
`include "soc_config.vh"

// Product CacheErr evidence: a cached D-side APB refill error reaches the
// architectural CacheErr vector, is handled once through ERL/ErrorEPC, and
// returns to the instruction after the faulting access.
module tb_product_cacheerr;
    localparam [31:0] FAULT_PC = 32'hBFC0_00D0;
    localparam [31:0] HANDLER_MARK = 32'hCACE_0001;

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
    wire uart_tx, uart_rts_n, uart_dtr_n;
    wire uart_rx = 1'b1;
    wire uart_cts_n = 1'b1;
    wire uart_dsr_n = 1'b1;
    wire uart_dcd_n = 1'b1;
    wire uart_ri_n = 1'b1;
    wire [31:0] gpio_pins;

    integer cycles;
    integer cacheerr_vector_count;
    reg cacheerr_vector_active;
    reg reset_seen;
    reg apb_refill_seen;
    reg apb_error_seen;
    reg cacheerr_vector_seen;
    reg cause_seen;
    reg erl_error_epc_seen;
    reg handler_marker_seen;
    reg eret_clear_seen;
    reg mailbox_seen;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gpio_pull
            pullup(gpio_pins[i]);
        end
    endgenerate

    mips_soc #(
        .ENABLE_APB_FAULT_INJECTOR (1'b1)
    ) u_soc (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_pins (gpio_pins),
        .uart_rx   (uart_rx),
        .uart_tx   (uart_tx),
        .uart_cts_n(uart_cts_n),
        .uart_rts_n(uart_rts_n),
        .uart_dsr_n(uart_dsr_n),
        .uart_dtr_n(uart_dtr_n),
        .uart_dcd_n(uart_dcd_n),
        .uart_ri_n (uart_ri_n),
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
            $display("REGRESSION_TEST_FAILED product_cacheerr");
            $finish;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            cacheerr_vector_count = 0;
            cacheerr_vector_active = 1'b0;
            reset_seen = 1'b0;
            apb_refill_seen = 1'b0;
            apb_error_seen = 1'b0;
            cacheerr_vector_seen = 1'b0;
            cause_seen = 1'b0;
            erl_error_epc_seen = 1'b0;
            handler_marker_seen = 1'b0;
            eret_clear_seen = 1'b0;
            mailbox_seen = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;

            if (u_soc.u_impl.s1_arvalid && u_soc.u_impl.s1_arready &&
                u_soc.u_impl.s1_araddr == 32'h4000_F000)
                apb_refill_seen = 1'b1;
            if (u_soc.u_impl.s1_rvalid && u_soc.u_impl.s1_rready &&
                u_soc.u_impl.s1_rresp == 2'b10)
                apb_error_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0100 &&
                !cacheerr_vector_active) begin
                cacheerr_vector_seen = 1'b1;
                cacheerr_vector_count = cacheerr_vector_count + 1;
                if (cacheerr_vector_count > 1)
                    fail("CacheErr handler was entered more than once");
            end
            cacheerr_vector_active =
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0100);

            if (cacheerr_vector_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] == 5'h1E)
                cause_seen = 1'b1;

            if (cacheerr_vector_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b1 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[1] == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_errorepc == FAULT_PC)
                erl_error_epc_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF0) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== HANDLER_MARK)
                    fail("CacheErr handler marker was incorrect");
                handler_marker_seen = 1'b1;
            end

            if (handler_marker_seen &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2] == 1'b0)
                eret_clear_seen = 1'b1;

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata !== 32'hDEAD_BEEF)
                    fail("product CacheErr firmware reported failure");
                mailbox_seen = 1'b1;
            end

            if (mailbox_seen && !u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (!reset_seen) fail("reset PC was not observed");
                if (!apb_refill_seen) fail("cached refill did not reach the APB fault window");
                if (!apb_error_seen) fail("APB fault did not become an AXI SLVERR");
                if (!cacheerr_vector_seen || cacheerr_vector_count != 1)
                    fail("CacheErr vector was not taken exactly once");
                if (!cause_seen) fail("Cause.ExcCode was not CacheErr (30)");
                if (!erl_error_epc_seen) fail("ERL/ErrorEPC precise state was not captured");
                if (!handler_marker_seen) fail("CacheErr recovery handler did not run");
                if (!eret_clear_seen) fail("ERET did not clear ERL");
                $display("REGRESSION_TEST_SUCCESS product_cacheerr");
                $finish;
            end

            if (cycles > 12000)
                fail("product CacheErr recovery firmware timed out");
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
