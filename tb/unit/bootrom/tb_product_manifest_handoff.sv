`timescale 1ns/1ps
`include "soc_config.vh"

// Product boot evidence: the processor starts in Boot ROM, reads a manifest
// through the production SPI XIP pins, validates/copies the payload, then
// transfers to its kseg0 entry. The responder is a serial flash device, not
// the verification-only AXI flash-image model.
module tb_product_manifest_handoff;
    localparam integer FLASH_BYTES = 65536;
    localparam [31:0] HANDOFF_MARKER = 32'h4841_4E44;

    reg clk;
    reg rst_n;
    reg tck;
    reg tms;
    reg tdi;
    reg [7:0] flash_mem [0:FLASH_BYTES-1];
    integer flash_read_addr;
    reg serial_read_active;
    wire [15:0] spi_stream_bit =
        ({8'd0, u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.burst_beat} << 5) +
        u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.bit_cnt;
    wire [15:0] spi_stream_addr = flash_read_addr + (spi_stream_bit >> 3);
    wire spi_miso = (serial_read_active &&
                     u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.state == 4'd3) ?
                    flash_mem[spi_stream_addr % FLASH_BYTES][7 - (spi_stream_bit & 7)] : 1'b0;
    wire tdo;
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire [31:0] gpio_pins;

    integer cycles;
    integer flash_index;
    integer spi_input_bits;
    integer expect_boot_failure;
    reg [255:0] expect_failure_name;
    reg [31:0] spi_shift;
    reg reset_seen;
    reg header_read_seen;
    reg payload_read_seen;
    reg spi_protocol_error;
    reg handoff_seen;
    reg stage1_entry_seen;
    reg pass_mailbox_seen;
    reg fail_mailbox_seen;
    // Aggregate gate run directories exceed the historical 128-character
    // simulation-image buffer. Keep the external flash path intact so a
    // failed $readmemh cannot turn a negative test into an all-FF false pass.
    reg [4095:0] flash_hex;

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
            $display("REGRESSION_TEST_FAILED product_manifest_handoff");
            $finish;
        end
    endtask

    // Command/address are sampled from the physical SPI pins. The MISO value
    // follows the controller's serial word/bit progress so AXI response gaps
    // do not create fictitious flash clock edges.
    always @(negedge spi_cs_n) begin
        spi_input_bits = 0;
        spi_shift = 32'd0;
        flash_read_addr = 0;
        serial_read_active = 1'b0;
    end

    always @(posedge spi_sclk) begin
        if (!spi_cs_n && spi_input_bits < 32) begin
            spi_shift = {spi_shift[30:0], spi_mosi};
            if (spi_input_bits == 31) begin
                if (spi_shift[31:24] != 8'h03)
                    spi_protocol_error = 1'b1;
                flash_read_addr = spi_shift[23:0];
                serial_read_active = 1'b1;
                if ($test$plusargs("BOOT_DEBUG"))
                    $display("DEBUG: SPI read command=%h address=%h", spi_shift[31:24],
                             spi_shift[23:0]);
                if (spi_shift[23:0] == 24'd0)
                    header_read_seen = 1'b1;
                if (spi_shift[23:0] >= 24'd64)
                    payload_read_seen = 1'b1;
            end
            spi_input_bits = spi_input_bits + 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_seen = 1'b0;
            header_read_seen = 1'b0;
            payload_read_seen = 1'b0;
            spi_protocol_error = 1'b0;
            handoff_seen = 1'b0;
            stage1_entry_seen = 1'b0;
            pass_mailbox_seen = 1'b0;
            fail_mailbox_seen = 1'b0;
        end else begin
            cycles = cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_1000)
                stage1_entry_seen = 1'b1;

            if ($test$plusargs("BOOT_DEBUG") && u_soc.u_impl.s2_rvalid &&
                u_soc.u_impl.s2_rready)
                $display("DEBUG: XIP response data=%h last=%b", u_soc.u_impl.s2_rdata,
                         u_soc.u_impl.s2_rlast);

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF8 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == HANDOFF_MARKER)
                    handoff_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_BEEF)
                        pass_mailbox_seen = 1'b1;
                    else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_DEAD)
                        fail_mailbox_seen = 1'b1;
                    else
                        fail("boot firmware wrote an unexpected mailbox value");
                end
            end

            if (pass_mailbox_seen) begin
                if (expect_boot_failure != 0)
                    fail("bad image reached the stage-1 success mailbox");
                if (!reset_seen)
                    fail("reset PC was not observed in Boot ROM");
                if (!header_read_seen || !payload_read_seen)
                    fail("manifest and payload were not both read through SPI XIP");
                if (spi_protocol_error)
                    fail("SPI XIP command was not standard read 03");
                if (!handoff_seen || !stage1_entry_seen)
                    fail("valid image did not reach the handoff marker and kseg0 entry");
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] ||
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2])
                    fail("BEV or ERL remained set after handoff");
                $display("REGRESSION_TEST_SUCCESS product_manifest_handoff_valid");
                $finish;
            end

            if (fail_mailbox_seen) begin
                if (expect_boot_failure == 0)
                    fail("valid image was rejected by Boot ROM");
                if (handoff_seen || stage1_entry_seen)
                    fail("bad image executed after a manifest failure");
                $display("REGRESSION_TEST_SUCCESS product_manifest_handoff_%0s", expect_failure_name);
                $finish;
            end

            if (cycles > 30000) begin
                $display("DEBUG: timeout pc=%h data_req=%b data_we=%h mem_vaddr=%h status=%h stage0=%h stage1=%h",
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr,
                         u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status,
                         u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[1024],
                         u_soc.u_impl.u_memory_subsystem.u_axi_sram.ram[1025]);
                fail("product manifest boot did not reach a terminal mailbox");
            end
        end
    end

    initial begin
        for (flash_index = 0; flash_index < FLASH_BYTES; flash_index = flash_index + 1)
            flash_mem[flash_index] = 8'hFF;
        if (!$value$plusargs("SPI_FLASH_HEX=%s", flash_hex))
            fail("SPI_FLASH_HEX is required");
        $readmemh(flash_hex, flash_mem);
        // The fixed fixture always carries version 1, except for the explicit
        // bad-version image (2). Reject the all-FF initializer so a failed
        // file load cannot masquerade as a bad-manifest test pass.
        if (flash_mem[4] != 8'h01 && flash_mem[4] != 8'h02)
            fail("SPI flash image was not loaded");
        expect_boot_failure = $test$plusargs("EXPECT_BOOT_FAILURE");
        expect_failure_name = "bad_crc";
        void'($value$plusargs("EXPECT_FAILURE_NAME=%s", expect_failure_name));
        clk = 1'b0;
        rst_n = 1'b0;
        tck = 1'b0;
        tms = 1'b1;
        tdi = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end
endmodule
