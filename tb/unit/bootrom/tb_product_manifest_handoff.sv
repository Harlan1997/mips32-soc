`timescale 1ns/1ps
`include "soc_config.vh"

// Product boot evidence: the processor starts in Boot ROM, reads a manifest
// through the production SPI XIP pins, validates/copies the payload, then
// transfers to its kseg0 entry. The responder is a serial flash device, not
// the verification-only AXI flash-image model.
module tb_product_manifest_handoff #(
    parameter integer SPI_READ_TIMEOUT_CYCLES = 512,
    parameter integer EXPECT_XIP_TIMEOUT = 0,
`ifdef TB_QSPI_QUAD
    parameter ENABLE_QSPI_QUAD = 1'b1
`else
    parameter ENABLE_QSPI_QUAD = 1'b0
`endif
);
    localparam integer FLASH_BYTES = 65536;
    localparam [31:0] HANDOFF_MARKER = 32'h4841_4E44;
    localparam [31:0] XIP_TIMEOUT_MARKER = 32'hDEAD_B007;
    localparam [31:0] RUNTIME_EXCEPTION_MARKER = 32'hACCE_5511;

    reg clk;
    reg rst_n;
    reg tck;
    reg tms;
    reg tdi;
    reg [7:0] flash_mem [0:FLASH_BYTES-1];
    integer flash_read_addr;
    reg serial_read_active;
    wire [3:0] qspi_io;
    wire spi_miso;
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

    generate
        if (ENABLE_QSPI_QUAD) begin : g_quad_flash
            qspi_flash_quad_behavioral #(.MEM_BYTES(FLASH_BYTES)) flash_quad (
                .clk      (clk),
                .rst_n    (rst_n),
                .spi_sclk (spi_sclk),
                .spi_cs_n (spi_cs_n),
                .spi_io   (qspi_io)
            );

            reg [4095:0] quad_flash_hex;
            initial begin
                if (!$value$plusargs("SPI_FLASH_HEX=%s", quad_flash_hex))
                    fail("SPI_FLASH_HEX is required for quad flash");
                $readmemh(quad_flash_hex, flash_quad.mem);
            end
        end else begin : g_x1_flash
            wire [15:0] spi_stream_bit =
                ({8'd0, u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.burst_beat} << 5) +
                u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.bit_cnt;
            wire [15:0] spi_stream_addr = flash_read_addr + (spi_stream_bit >> 3);
            assign spi_miso = (serial_read_active &&
                               u_soc.u_impl.u_memory_subsystem.g_spi_flash_controller.u_axi_spi_flash.state == 4'd3) ?
                              flash_mem[spi_stream_addr % FLASH_BYTES][7 - (spi_stream_bit & 7)] : 1'b0;
        end
    endgenerate

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
    reg kseg0_pa_seen;
    reg kseg0_data_seen;
    reg kseg0_data_second_seen;
    reg kseg0_data_read_seen;
    reg kseg0_layout_rodata_read_seen;
    reg kseg0_layout_data_read_seen;
    reg [3:0] kseg0_layout_bss_write_mask;
    reg kseg0_layout_bss_zero_read_seen;
    reg kseg0_layout_bss_readback_seen;
    reg kseg0_layout_stack_write_seen;
    reg kseg0_layout_stack_read_seen;
    reg [19:0] kseg0_depth_write_mask;
    reg [19:0] kseg0_depth_read_mask;
    reg kseg0_depth_stack_write_seen;
    reg kseg0_depth_stack_read_seen;
    reg runtime_abi_entry_seen;
    reg runtime_abi_handler_seen;
    reg runtime_abi_vector_seen;
    reg runtime_abi_reloc_seen;
    reg runtime_abi_data_seen;
    reg [3:0] runtime_abi_bss_write_mask;
    reg runtime_abi_bss_read_seen;
    reg [1:0] runtime_abi_heap_write_mask;
    reg [1:0] runtime_abi_heap_read_mask;
    reg runtime_abi_stack_write_seen;
    reg runtime_abi_stack_read_seen;
    reg runtime_abi_exception_seen;
    reg pass_mailbox_seen;
    reg fail_mailbox_seen;
    reg xip_timeout_mailbox_seen;
    reg boot_status_stage_seen;
    reg boot_status_failure_seen;
    reg [31:0] boot_status_stage_value;
    reg [31:0] boot_status_failure_value;
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

    mips_soc #(
        .SPI_READ_TIMEOUT_CYCLES (SPI_READ_TIMEOUT_CYCLES),
        .ENABLE_QSPI_QUAD       (ENABLE_QSPI_QUAD)
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
        .qspi_io   (qspi_io),
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
    // do not create fictitious flash clock edges. The quad monitor observes
    // the same x1 command/address phase on lane 0 and lets the endpoint drive
    // data nibbles on all four lanes.
    generate
        if (ENABLE_QSPI_QUAD) begin : g_quad_monitor
            reg [5:0] quad_input_bits;
            reg [31:0] quad_shift;

            always @(negedge spi_cs_n) begin
                quad_input_bits = 0;
                quad_shift = 32'd0;
            end

            always @(posedge spi_sclk) begin
                if (!spi_cs_n && quad_input_bits < 32) begin
                    quad_shift = {quad_shift[30:0], qspi_io[0]};
                    if (quad_input_bits == 31) begin
                        if (quad_shift[31:24] != 8'h6b)
                            spi_protocol_error = 1'b1;
                        if (quad_shift[23:0] == 24'd0)
                            header_read_seen = 1'b1;
                        if (quad_shift[23:0] >= 24'd64)
                            payload_read_seen = 1'b1;
                    end
                    quad_input_bits = quad_input_bits + 1'b1;
                end
            end
        end else begin : g_x1_monitor
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
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles = 0;
            reset_seen = 1'b0;
            header_read_seen = 1'b0;
            payload_read_seen = 1'b0;
            spi_protocol_error = 1'b0;
            handoff_seen = 1'b0;
            stage1_entry_seen = 1'b0;
            kseg0_pa_seen = 1'b0;
            kseg0_data_seen = 1'b0;
            kseg0_data_second_seen = 1'b0;
            kseg0_data_read_seen = 1'b0;
            kseg0_layout_rodata_read_seen = 1'b0;
            kseg0_layout_data_read_seen = 1'b0;
            kseg0_layout_bss_write_mask = 4'd0;
            kseg0_layout_bss_zero_read_seen = 1'b0;
            kseg0_layout_bss_readback_seen = 1'b0;
            kseg0_layout_stack_write_seen = 1'b0;
            kseg0_layout_stack_read_seen = 1'b0;
            kseg0_depth_write_mask = 20'd0;
            kseg0_depth_read_mask = 20'd0;
            kseg0_depth_stack_write_seen = 1'b0;
            kseg0_depth_stack_read_seen = 1'b0;
            runtime_abi_entry_seen = 1'b0;
            runtime_abi_handler_seen = 1'b0;
            runtime_abi_vector_seen = 1'b0;
            runtime_abi_reloc_seen = 1'b0;
            runtime_abi_data_seen = 1'b0;
            runtime_abi_bss_write_mask = 4'd0;
            runtime_abi_bss_read_seen = 1'b0;
            runtime_abi_heap_write_mask = 2'd0;
            runtime_abi_heap_read_mask = 2'd0;
            runtime_abi_stack_write_seen = 1'b0;
            runtime_abi_stack_read_seen = 1'b0;
            runtime_abi_exception_seen = 1'b0;
            pass_mailbox_seen = 1'b0;
            fail_mailbox_seen = 1'b0;
            xip_timeout_mailbox_seen = 1'b0;
            boot_status_stage_seen = 1'b0;
            boot_status_failure_seen = 1'b0;
            boot_status_stage_value = 32'd0;
            boot_status_failure_value = 32'd0;
        end else begin
            cycles = cycles + 1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'hBFC0_0000)
                reset_seen = 1'b1;
            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_1000)
                stage1_entry_seen = 1'b1;
            if ($test$plusargs("EXPECT_KSEG0_RUNTIME_ABI") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_1100)
                runtime_abi_entry_seen = 1'b1;
            if ($test$plusargs("EXPECT_KSEG0_RUNTIME_ABI") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_if_stage.pc == 32'h8000_0180)
                runtime_abi_vector_seen = 1'b1;
            if ($test$plusargs("EXPECT_KSEG0_RUNTIME") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.if_vaddr == 32'h8000_1000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.inst_addr == 32'h0000_1000)
                kseg0_pa_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_DATA") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_7000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hCAFE_BABE)
                kseg0_data_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_DATA") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7004 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_7004 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'h1357_9BDF)
                kseg0_data_second_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_DATA") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7004 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_7004)
                kseg0_data_read_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_LAYOUT") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1100 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_1100)
                kseg0_layout_rodata_read_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_LAYOUT") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we == 1'b0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1110 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_1110)
                kseg0_layout_data_read_seen = 1'b1;

            if ($test$plusargs("EXPECT_KSEG0_LAYOUT") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= 32'h8000_1120 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr <= 32'h8000_112C &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr ==
                    (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr & 32'h1FFF_FFFF) &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr[1:0] == 2'b00) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                    kseg0_layout_bss_write_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_1120) >> 2] = 1'b1;
                else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1120 &&
                         !kseg0_layout_bss_zero_read_seen)
                    kseg0_layout_bss_zero_read_seen = 1'b1;
                else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1120)
                    kseg0_layout_bss_readback_seen = 1'b1;
            end

            if ($test$plusargs("EXPECT_KSEG0_LAYOUT") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7FF0 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_7FF0) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                    kseg0_layout_stack_write_seen = 1'b1;
                else
                    kseg0_layout_stack_read_seen = 1'b1;
            end

            if ($test$plusargs("EXPECT_KSEG0_DEPTH") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= 32'h8000_7000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr <= 32'h8000_704C &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr ==
                    (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr & 32'h1FFF_FFFF) &&
                ((u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr[1:0]) == 2'b00)) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                    kseg0_depth_write_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_7000) >> 2] = 1'b1;
                else
                    kseg0_depth_read_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_7000) >> 2] = 1'b1;
            end

            if ($test$plusargs("EXPECT_KSEG0_DEPTH") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_8000 &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_addr == 32'h0000_8000) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                    kseg0_depth_stack_write_seen = 1'b1;
                else
                    kseg0_depth_stack_read_seen = 1'b1;
            end

            if ($test$plusargs("EXPECT_KSEG0_RUNTIME_ABI") &&
                u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_0180)
                    runtime_abi_handler_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we == 4'd0 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_1300)
                    runtime_abi_reloc_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we == 4'd0 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1670)
                    runtime_abi_data_seen = 1'b1;
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr >= 32'h8000_1680 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr <= 32'h8000_168C &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr[1:0] == 2'b00) begin
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                        runtime_abi_bss_write_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_1680) >> 2] = 1'b1;
                    else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_1680)
                        runtime_abi_bss_read_seen = 1'b1;
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7000 ||
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7004) begin
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                        runtime_abi_heap_write_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_7000) >> 2] = 1'b1;
                    else
                        runtime_abi_heap_read_mask[(u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr - 32'h8000_7000) >> 2] = 1'b1;
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'h8000_7FF0) begin
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)
                        runtime_abi_stack_write_seen = 1'b1;
                    else
                        runtime_abi_stack_read_seen = 1'b1;
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF0 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == RUNTIME_EXCEPTION_MARKER)
                    runtime_abi_exception_seen = 1'b1;
            end

            if ($test$plusargs("BOOT_DEBUG") && u_soc.u_impl.s2_rvalid &&
                u_soc.u_impl.s2_rready)
                $display("DEBUG: XIP response data=%h last=%b", u_soc.u_impl.s2_rdata,
                         u_soc.u_impl.s2_rlast);

            if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_req &&
                (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_we != 4'd0)) begin
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_8000) begin
                    boot_status_stage_seen = 1'b1;
                    boot_status_stage_value = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata;
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_8004) begin
                    boot_status_failure_seen = 1'b1;
                    boot_status_failure_value = u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata;
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFF8 &&
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == HANDOFF_MARKER)
                    handoff_seen = 1'b1;
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.mem_vaddr == 32'hA000_FFFC) begin
                        if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_BEEF)
                            pass_mailbox_seen = 1'b1;
                        else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == 32'hDEAD_DEAD)
                            fail_mailbox_seen = 1'b1;
                        else if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.data_wdata == XIP_TIMEOUT_MARKER)
                            xip_timeout_mailbox_seen = 1'b1;
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
                if (spi_protocol_error) begin
                    if (ENABLE_QSPI_QUAD)
                        fail("quad SPI XIP command was not read 6B");
                    else
                        fail("SPI XIP command was not standard read 03");
                end
                if (!handoff_seen || !stage1_entry_seen)
                    fail("valid image did not reach the handoff marker and kseg0 entry");
                if ($test$plusargs("EXPECT_KSEG0_RUNTIME_ABI")) begin
                    if (!runtime_abi_entry_seen)
                        fail("runtime ABI image did not execute from relocated kseg0 entry");
                    if (!runtime_abi_handler_seen || !runtime_abi_vector_seen)
                        fail("runtime ABI exception handler was not relocated to EBase vector");
                    if (!runtime_abi_reloc_seen || !runtime_abi_data_seen)
                        fail("runtime ABI relocation/data access was not observed");
                    if (runtime_abi_bss_write_mask != 4'hF || !runtime_abi_bss_read_seen)
                        fail("runtime ABI .bss clear/readback contract was not observed");
                    if (runtime_abi_heap_write_mask != 2'b11 || runtime_abi_heap_read_mask != 2'b11)
                        fail("runtime ABI heap allocation read/write contract was not observed");
                    if (!runtime_abi_stack_write_seen || !runtime_abi_stack_read_seen)
                        fail("runtime ABI stack access contract was not observed");
                    if (!runtime_abi_exception_seen)
                        fail("runtime ABI exception handler did not publish its marker");
                    $display("REGRESSION_TEST_SUCCESS product_manifest_handoff_runtime_abi");
                    $finish;
                end
                if ($test$plusargs("EXPECT_KSEG0_RUNTIME") && !kseg0_pa_seen)
                    fail("MMU-enabled kseg0 stage-1 fetch did not use the physical SRAM address");
                if ($test$plusargs("EXPECT_KSEG0_DATA") && !kseg0_data_seen)
                    fail("MMU-enabled kseg0 stage-1 data access did not use the physical SRAM address");
                if ($test$plusargs("EXPECT_KSEG0_DATA") && !kseg0_data_second_seen)
                    fail("MMU-enabled kseg0 second data word did not use the physical SRAM address");
                if ($test$plusargs("EXPECT_KSEG0_DATA") && !kseg0_data_read_seen)
                    fail("MMU-enabled kseg0 data readback was not observed");
                if ($test$plusargs("EXPECT_KSEG0_LAYOUT")) begin
                    if (!kseg0_layout_rodata_read_seen)
                        fail("kseg0 runtime .rodata read was not observed");
                    if (!kseg0_layout_data_read_seen)
                        fail("kseg0 runtime initialized .data read was not observed");
                    if (kseg0_layout_bss_write_mask != 4'hF)
                        fail("kseg0 runtime .bss was not explicitly cleared across all words");
                    if (!kseg0_layout_bss_zero_read_seen || !kseg0_layout_bss_readback_seen)
                        fail("kseg0 runtime .bss zero/readback sequence was not observed");
                    if (!kseg0_layout_stack_write_seen || !kseg0_layout_stack_read_seen)
                        fail("kseg0 runtime linker stack translation/readback was not observed");
                end
                if ($test$plusargs("EXPECT_KSEG0_DEPTH")) begin
                    if (kseg0_depth_write_mask != 20'hF_FFFF)
                        fail("kseg0 depth did not write all 20 data words");
                    if (kseg0_depth_read_mask != 20'hF_FFFF)
                        fail("kseg0 depth did not read all 20 data words");
                    if (!kseg0_depth_stack_write_seen || !kseg0_depth_stack_read_seen)
                        fail("kseg0 depth stack translation/readback was not observed");
                end
                if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[22] ||
                    u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_status[2])
                    fail("BEV or ERL remained set after handoff");
                $display("REGRESSION_TEST_SUCCESS product_manifest_handoff_valid");
                $finish;
            end

            if (fail_mailbox_seen || xip_timeout_mailbox_seen) begin
                if (expect_boot_failure == 0)
                    fail("valid image was rejected by Boot ROM");
                if (EXPECT_XIP_TIMEOUT != 0) begin
                    if (!xip_timeout_mailbox_seen)
                        fail("XIP timeout did not take the Boot ROM bus-error path");
                    if (u_soc.u_impl.u_core_subsystem.u_core.u_cpu.u_mips_cp0.cp0_cause[6:2] != 5'h07)
                        fail("XIP timeout did not raise DBE");
                    if (!boot_status_stage_seen || !boot_status_failure_seen ||
                        boot_status_stage_value != 32'h0000_0020 ||
                        boot_status_failure_value != 32'hB007_0004)
                        fail("XIP timeout did not publish boot-status failure code");
                end else if (!fail_mailbox_seen) begin
                    fail("manifest rejection used the XIP bus-error failure path");
                end else if (!$test$plusargs("EXPECT_RUNTIME_FAILURE") &&
                             (!boot_status_stage_seen || !boot_status_failure_seen ||
                             boot_status_stage_value != 32'h0000_0020 ||
                             boot_status_failure_value != 32'hB007_0003)) begin
                    fail("manifest rejection did not publish boot-status failure code");
                end
                if (!$test$plusargs("EXPECT_RUNTIME_FAILURE") &&
                    (handoff_seen || stage1_entry_seen))
                    fail("bad image executed after a manifest failure");
                $display("REGRESSION_TEST_SUCCESS product_manifest_handoff_%0s", expect_failure_name);
                $finish;
            end

            if (cycles > ($test$plusargs("EXPECT_KSEG0_RUNTIME_MULTI") ? 500000 :
                         (($test$plusargs("EXPECT_KSEG0_LAYOUT") ||
                           $test$plusargs("EXPECT_KSEG0_RUNTIME_ABI")) ? 120000 : 30000))) begin
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
        expect_boot_failure = $test$plusargs("EXPECT_BOOT_FAILURE") || (EXPECT_XIP_TIMEOUT != 0);
        expect_failure_name = (EXPECT_XIP_TIMEOUT != 0) ? "xip_timeout" : "bad_crc";
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
