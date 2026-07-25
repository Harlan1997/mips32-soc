`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "../agents/axi_transaction.sv"
`include "soc_config.vh"

`uvm_analysis_imp_decl(_ext)
`uvm_analysis_imp_decl(_sram)

class soc_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(soc_scoreboard)

    uvm_analysis_imp_ext  #(axi_transaction, soc_scoreboard) ext_export;
    uvm_analysis_imp_sram #(axi_transaction, soc_scoreboard) sram_export;

    int unsigned ext_read_count;
    int unsigned ext_write_count;
    int unsigned sram_read_count;
    int unsigned sram_write_count;
    int unsigned gpio_check_count;
    int unsigned gpio_update_count;
    int unsigned uart_check_count;
    int unsigned uart_update_count;
    int unsigned timer_check_count;
    int unsigned timer_update_count;
    int unsigned pic_check_count;
    int unsigned pic_update_count;
    int unsigned sram_data_check_count;
    int unsigned sram_data_update_count;
    int unsigned flash_data_check_count;
    int unsigned dma_reg_check_count;
    int unsigned dma_reg_update_count;
    int unsigned dma_copy_check_count;
    int unsigned dma_copy_update_count;
    int unsigned dma_copy_skip_count;

    logic [31:0] gpio_data_model;
    logic [31:0] gpio_dir_model;
    logic [31:0] timer_ctrl_model;
    logic [31:0] timer_load_model;
    logic [31:0] timer_val_model;
    logic [31:0] timer_int_model;
    logic [31:0] pic_mask_model;
    logic        uart_tx_irq_pending;
    bit          flash_image_loaded;
    logic [31:0] sram_word_model[int unsigned];
    logic [3:0]  sram_known_mask[int unsigned];
    logic [31:0] dma_src_model;
    logic [31:0] dma_dst_model;
    logic [31:0] dma_len_model;
    logic        dma_int_en_model;
    logic        dma_done_model;
    logic [31:0] dma_expected_word[int unsigned];
    logic [3:0]  dma_expected_mask[int unsigned];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ext_export  = new("ext_export", this);
        sram_export = new("sram_export", this);
        gpio_data_model = 32'h0000_0000;
        gpio_dir_model  = 32'h0000_0000;
        timer_ctrl_model = 32'h0000_0000;
        timer_load_model = 32'h0000_0000;
        timer_val_model  = 32'h0000_0000;
        timer_int_model  = 32'h0000_0000;
        pic_mask_model   = 32'h0000_0000;
        uart_tx_irq_pending = 1'b0;
        flash_image_loaded = $test$plusargs("FLASH_IMAGE") ||
                             $test$plusargs("FLASH_IMAGE=");
        dma_src_model    = 32'h0000_0000;
        dma_dst_model    = 32'h0000_0000;
        dma_len_model    = 32'h0000_0000;
        dma_int_en_model = 1'b0;
        dma_done_model   = 1'b0;
    endfunction

    function bit is_sram_window(logic [31:0] addr);
        return (((addr & `SOC_64KB_REGION_MASK) == `SOC_BOOT_BASE) ||
                ((addr & `SOC_64KB_REGION_MASK) == `SOC_SRAM_ALIAS_BASE));
    endfunction

    function bit is_apb_window(logic [31:0] addr);
        return ((addr & `SOC_64KB_REGION_MASK) == `SOC_APB_BASE);
    endfunction

    function bit is_flash_window(logic [31:0] addr);
        return ((addr & `SOC_256MB_REGION_MASK) == `SOC_FLASH_BASE);
    endfunction

    function bit is_mapped(logic [31:0] addr);
        return is_sram_window(addr) || is_apb_window(addr) || is_flash_window(addr);
    endfunction

    function bit is_gpio_data_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DATA_OFFSET));
    endfunction

    function bit is_gpio_dir_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_GPIO_OFFSET + `SOC_GPIO_DIR_OFFSET));
    endfunction

    function bit is_uart_tx_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_TX_OFFSET));
    endfunction

    function bit is_uart_status_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_STATUS_OFFSET));
    endfunction

    function bit is_uart_irq_status_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_IRQ_STATUS_OFFSET));
    endfunction

    function bit is_uart_irq_clear_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_UART_OFFSET + `SOC_UART_IRQ_CLEAR_OFFSET));
    endfunction

    function bit is_apb_fault_addr(logic [31:0] addr);
        return ((addr & 32'hFFFF_F000) == (`SOC_APB_BASE + `SOC_APB_FAULT_OFFSET));
    endfunction

    function bit is_timer_ctrl_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_CTRL_OFFSET));
    endfunction

    function bit is_timer_load_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_LOAD_OFFSET));
    endfunction

    function bit is_timer_val_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_VAL_OFFSET));
    endfunction

    function bit is_timer_int_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_TIMER_OFFSET + `SOC_TIMER_INT_OFFSET));
    endfunction

    function bit is_pic_status_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_STATUS_OFFSET));
    endfunction

    function bit is_pic_mask_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_MASK_OFFSET));
    endfunction

    function bit is_pic_active_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_PIC_OFFSET + `SOC_PIC_ACTIVE_OFFSET));
    endfunction

    function bit is_dma_src_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_SRC_OFFSET));
    endfunction

    function bit is_dma_dst_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_DST_OFFSET));
    endfunction

    function bit is_dma_len_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_LEN_OFFSET));
    endfunction

    function bit is_dma_ctrl_addr(logic [31:0] addr);
        return (addr == (`SOC_APB_BASE + `SOC_APB_DMA_OFFSET + `SOC_DMA_CTRL_OFFSET));
    endfunction

    function int unsigned sram_word_key(logic [31:0] addr);
        return ((addr & 32'h0000_FFFC) >> 2);
    endfunction

    function void check_read_responses(axi_transaction tr, logic [1:0] expected, string scope_name);
        if (tr.resp.size() != (tr.len + 1)) begin
            `uvm_error("SB_RESP_SIZE", $sformatf("%s read addr=0x%08h has %0d responses, expected %0d",
                       scope_name, tr.addr, tr.resp.size(), tr.len + 1))
        end

        foreach (tr.resp[i]) begin
            if (tr.resp[i] !== expected) begin
                `uvm_error("SB_RESP", $sformatf("%s read addr=0x%08h beat=%0d resp=%0b expected=%0b",
                           scope_name, tr.addr, i, tr.resp[i], expected))
            end
        end
    endfunction

    function void check_write_response(axi_transaction tr, logic [1:0] expected, string scope_name);
        if (tr.resp.size() < 1) begin
            `uvm_error("SB_RESP_SIZE", $sformatf("%s write addr=0x%08h has no B response", scope_name, tr.addr))
            return;
        end

        if (tr.resp[0] !== expected) begin
            `uvm_error("SB_RESP", $sformatf("%s write addr=0x%08h resp=%0b expected=%0b",
                       scope_name, tr.addr, tr.resp[0], expected))
        end
    endfunction

    function void write_ext(axi_transaction tr);
        logic [1:0] expected_resp;

        if (tr.trans_type == AXI_READ) begin
            ext_read_count++;
            if (is_apb_fault_addr(tr.addr)) begin
                expected_resp = `SOC_AXI_RESP_SLVERR;
            end else begin
                expected_resp = is_mapped(tr.addr) ? `SOC_AXI_RESP_OKAY : `SOC_AXI_RESP_DECERR;
            end
            check_read_responses(tr, expected_resp, "ext");
            if (expected_resp == `SOC_AXI_RESP_OKAY) begin
                check_apb_gpio_read(tr);
                check_apb_uart_read(tr);
                check_apb_timer_read(tr);
                check_apb_pic_read(tr);
                check_apb_dma_read(tr);
                check_sram_read_data(tr);
                check_flash_read_data(tr);
            end
        end else begin
            ext_write_count++;
            if (!is_mapped(tr.addr)) begin
                expected_resp = `SOC_AXI_RESP_DECERR;
            end else if (is_flash_window(tr.addr)) begin
                expected_resp = `SOC_AXI_RESP_SLVERR;
            end else if (is_apb_fault_addr(tr.addr)) begin
                expected_resp = `SOC_AXI_RESP_SLVERR;
            end else begin
                expected_resp = `SOC_AXI_RESP_OKAY;
            end
            check_write_response(tr, expected_resp, "ext");
            if (expected_resp == `SOC_AXI_RESP_OKAY) begin
                update_apb_gpio_model(tr);
                update_apb_uart_model(tr);
                update_apb_timer_model(tr);
                update_apb_pic_model(tr);
                update_apb_dma_model(tr);
                update_sram_model(tr);
            end
        end
    endfunction

    function void update_sram_model(axi_transaction tr);
        logic [31:0] beat_addr;
        int unsigned key;
        logic [31:0] model_word;
        logic [3:0]  known_mask;

        if (!is_sram_window(tr.addr) || tr.size != 3'b010) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            key = sram_word_key(beat_addr);
            model_word = sram_word_model.exists(key) ? sram_word_model[key] : 32'h0000_0000;
            known_mask = sram_known_mask.exists(key) ? sram_known_mask[key] : 4'h0;

            if (tr.strb[i][0]) begin
                model_word[7:0] = tr.data[i][7:0];
                known_mask[0] = 1'b1;
            end
            if (tr.strb[i][1]) begin
                model_word[15:8] = tr.data[i][15:8];
                known_mask[1] = 1'b1;
            end
            if (tr.strb[i][2]) begin
                model_word[23:16] = tr.data[i][23:16];
                known_mask[2] = 1'b1;
            end
            if (tr.strb[i][3]) begin
                model_word[31:24] = tr.data[i][31:24];
                known_mask[3] = 1'b1;
            end

            sram_word_model[key] = model_word;
            sram_known_mask[key] = known_mask;
            sram_data_update_count++;
        end
    endfunction

    function void check_sram_read_data(axi_transaction tr);
        logic [31:0] beat_addr;
        int unsigned key;
        logic [31:0] expected_word;
        logic [3:0]  known_mask;
        logic [31:0] byte_mask;

        if (!is_sram_window(tr.addr) || tr.size != 3'b010) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            key = sram_word_key(beat_addr);
            if (sram_word_model.exists(key) && sram_known_mask.exists(key)) begin
                expected_word = sram_word_model[key];
                known_mask = sram_known_mask[key];
                byte_mask = {{8{known_mask[3]}}, {8{known_mask[2]}}, {8{known_mask[1]}}, {8{known_mask[0]}}};
                if ((tr.data[i] & byte_mask) !== (expected_word & byte_mask)) begin
                    `uvm_error("SB_SRAM_DATA", $sformatf("SRAM read mismatch addr=0x%08h data=0x%08h expected=0x%08h mask=0x%08h",
                               beat_addr, tr.data[i], expected_word, byte_mask))
                end
                sram_data_check_count++;
            end
        end
    endfunction

    function void check_flash_read_data(axi_transaction tr);
        logic [31:0] beat_addr;

        if (!is_flash_window(tr.addr)) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (flash_image_loaded) begin
                flash_data_check_count++;
                continue;
            end
            if (tr.data[i] !== 32'h0000_0000) begin
                `uvm_error("SB_FLASH_DATA", $sformatf("Flash read mismatch addr=0x%08h data=0x%08h expected=0x00000000",
                           beat_addr, tr.data[i]))
            end
            flash_data_check_count++;
        end
    endfunction

    function void update_apb_gpio_model(axi_transaction tr);
        if (tr.data.size() < 1) begin
            return;
        end

        if (is_gpio_data_addr(tr.addr)) begin
            gpio_data_model = tr.data[0];
            gpio_update_count++;
        end else if (is_gpio_dir_addr(tr.addr)) begin
            gpio_dir_model = tr.data[0];
            gpio_update_count++;
        end
    endfunction

    function void check_apb_gpio_read(axi_transaction tr);
        logic [31:0] beat_addr;
        logic [31:0] driven_mask;
        logic [31:0] expected_data_bits;
        logic [31:0] observed_data_bits;

        if (tr.data.size() < 1) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (is_gpio_dir_addr(beat_addr)) begin
                gpio_check_count++;
                if (tr.data[i] !== gpio_dir_model) begin
                    `uvm_error("SB_GPIO", $sformatf("GPIO DIR read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], gpio_dir_model))
                end
            end else if (is_gpio_data_addr(beat_addr)) begin
                driven_mask = gpio_dir_model;
                gpio_check_count++;
                expected_data_bits = gpio_data_model & driven_mask;
                observed_data_bits = tr.data[i] & driven_mask;
                if (observed_data_bits !== expected_data_bits) begin
                    `uvm_error("SB_GPIO", $sformatf("GPIO DATA driven-bit mismatch addr=0x%08h data=0x%08h expected_masked=0x%08h mask=0x%08h",
                               beat_addr, tr.data[i], expected_data_bits, driven_mask))
                end
            end
        end
    endfunction

    function void update_apb_uart_model(axi_transaction tr);
        if (tr.data.size() < 1) begin
            return;
        end

        if (is_uart_tx_addr(tr.addr)) begin
            uart_tx_irq_pending = 1'b1;
            uart_update_count++;
        end else if (is_uart_irq_clear_addr(tr.addr)) begin
            if (tr.data[0][1]) begin
                uart_tx_irq_pending = 1'b0;
            end
            uart_update_count++;
        end
    endfunction

    function void check_apb_uart_read(axi_transaction tr);
        logic [31:0] beat_addr;

        if (tr.data.size() < 1) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (is_uart_status_addr(beat_addr)) begin
                uart_check_count++;
                if (tr.data[i] !== {30'd0, uart_tx_irq_pending, 1'b1}) begin
                    `uvm_error("SB_UART", $sformatf("UART STATUS read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], {30'd0, uart_tx_irq_pending, 1'b1}))
                end
            end else if (is_uart_tx_addr(beat_addr)) begin
                uart_check_count++;
                if (tr.data[i] !== 32'h0000_0000) begin
                    `uvm_error("SB_UART", $sformatf("UART TX read mismatch addr=0x%08h data=0x%08h expected=0x00000000",
                               beat_addr, tr.data[i]))
                end
            end else if (is_uart_irq_status_addr(beat_addr)) begin
                uart_check_count++;
                if (tr.data[i] !== {30'd0, uart_tx_irq_pending, 1'b0}) begin
                    `uvm_error("SB_UART", $sformatf("UART IRQ_STATUS read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], {30'd0, uart_tx_irq_pending, 1'b0}))
                end
            end
        end
    endfunction

    function void update_apb_timer_model(axi_transaction tr);
        if (tr.data.size() < 1) begin
            return;
        end

        if (is_timer_ctrl_addr(tr.addr)) begin
            timer_ctrl_model = tr.data[0];
            timer_update_count++;
        end else if (is_timer_load_addr(tr.addr)) begin
            timer_load_model = tr.data[0];
            timer_val_model = tr.data[0];
            timer_update_count++;
        end else if (is_timer_val_addr(tr.addr)) begin
            timer_val_model = tr.data[0];
            timer_update_count++;
        end else if (is_timer_int_addr(tr.addr)) begin
            if (tr.data[0][0]) begin
                timer_int_model[0] = 1'b0;
            end
            timer_update_count++;
        end
    endfunction

    function void check_apb_timer_read(axi_transaction tr);
        logic [31:0] beat_addr;

        if (tr.data.size() < 1) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (is_timer_ctrl_addr(beat_addr)) begin
                timer_check_count++;
                if (tr.data[i] !== timer_ctrl_model) begin
                    `uvm_error("SB_TIMER", $sformatf("TIMER CTRL read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], timer_ctrl_model))
                end
            end else if (is_timer_load_addr(beat_addr)) begin
                timer_check_count++;
                if (tr.data[i] !== timer_load_model) begin
                    `uvm_error("SB_TIMER", $sformatf("TIMER LOAD read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], timer_load_model))
                end
            end else if (is_timer_val_addr(beat_addr)) begin
                timer_check_count++;
                if (!timer_ctrl_model[0] && tr.data[i] !== timer_val_model) begin
                    `uvm_error("SB_TIMER", $sformatf("TIMER VAL read mismatch while disabled addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], timer_val_model))
                end
            end else if (is_timer_int_addr(beat_addr)) begin
                timer_check_count++;
                if (!timer_ctrl_model[0] && tr.data[i][0] !== timer_int_model[0]) begin
                    `uvm_error("SB_TIMER", $sformatf("TIMER INT read mismatch while disabled addr=0x%08h data=0x%08h expected_bit0=%0b",
                               beat_addr, tr.data[i], timer_int_model[0]))
                end
            end
        end
    endfunction

    function void update_apb_pic_model(axi_transaction tr);
        if (tr.data.size() < 1) begin
            return;
        end

        if (is_pic_mask_addr(tr.addr)) begin
            pic_mask_model = tr.data[0];
            pic_update_count++;
        end
    endfunction

    function void check_apb_pic_read(axi_transaction tr);
        logic [31:0] beat_addr;
        bit expected_dma_irq;

        if (tr.data.size() < 1) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (is_pic_mask_addr(beat_addr)) begin
                pic_check_count++;
                if (tr.data[i] !== pic_mask_model) begin
                    `uvm_error("SB_PIC", $sformatf("PIC MASK read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], pic_mask_model))
                end
            end else if (is_pic_active_addr(beat_addr) && pic_mask_model == 32'h0000_0000) begin
                pic_check_count++;
                if (tr.data[i] !== 32'h0000_0000) begin
                    `uvm_error("SB_PIC", $sformatf("PIC ACTIVE read mismatch with zero mask addr=0x%08h data=0x%08h expected=0x00000000",
                               beat_addr, tr.data[i]))
                end
            end else if (is_pic_active_addr(beat_addr) && pic_mask_model[3]) begin
                pic_check_count++;
                expected_dma_irq = dma_done_model & dma_int_en_model;
                if (tr.data[i][3] !== expected_dma_irq) begin
                    `uvm_error("SB_PIC", $sformatf("PIC ACTIVE DMA bit mismatch addr=0x%08h data=0x%08h expected_bit3=%0b",
                               beat_addr, tr.data[i], expected_dma_irq))
                end
            end else if (is_pic_status_addr(beat_addr)) begin
                pic_check_count++;
                expected_dma_irq = dma_done_model & dma_int_en_model;
                if (tr.data[i][3] !== expected_dma_irq) begin
                    `uvm_error("SB_PIC", $sformatf("PIC STATUS DMA bit mismatch addr=0x%08h data=0x%08h expected_bit3=%0b",
                               beat_addr, tr.data[i], expected_dma_irq))
                end
            end
        end
    endfunction

    function void update_apb_dma_model(axi_transaction tr);
        if (tr.data.size() < 1) begin
            return;
        end

        if (is_dma_src_addr(tr.addr)) begin
            dma_src_model = tr.data[0];
            dma_reg_update_count++;
        end else if (is_dma_dst_addr(tr.addr)) begin
            dma_dst_model = tr.data[0];
            dma_reg_update_count++;
        end else if (is_dma_len_addr(tr.addr)) begin
            dma_len_model = tr.data[0];
            dma_reg_update_count++;
        end else if (is_dma_ctrl_addr(tr.addr)) begin
            dma_int_en_model = tr.data[0][1];
            if (tr.data[0][2]) begin
                dma_done_model = 1'b0;
            end
            if (tr.data[0][0]) begin
                build_dma_copy_prediction();
            end
            dma_reg_update_count++;
        end
    endfunction

    function void check_apb_dma_read(axi_transaction tr);
        logic [31:0] beat_addr;

        if (tr.data.size() < 1) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            if (is_dma_src_addr(beat_addr)) begin
                dma_reg_check_count++;
                if (tr.data[i] !== dma_src_model) begin
                    `uvm_error("SB_DMA_REG", $sformatf("DMA SRC read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], dma_src_model))
                end
            end else if (is_dma_dst_addr(beat_addr)) begin
                dma_reg_check_count++;
                if (tr.data[i] !== dma_dst_model) begin
                    `uvm_error("SB_DMA_REG", $sformatf("DMA DST read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], dma_dst_model))
                end
            end else if (is_dma_len_addr(beat_addr)) begin
                dma_reg_check_count++;
                if (tr.data[i] !== dma_len_model) begin
                    `uvm_error("SB_DMA_REG", $sformatf("DMA LENGTH read mismatch addr=0x%08h data=0x%08h expected=0x%08h",
                               beat_addr, tr.data[i], dma_len_model))
                end
            end else if (is_dma_ctrl_addr(beat_addr)) begin
                dma_reg_check_count++;
                if (tr.data[i][1] !== dma_int_en_model) begin
                    `uvm_error("SB_DMA_REG", $sformatf("DMA CTRL INT_EN read mismatch addr=0x%08h data=0x%08h expected_bit1=%0b",
                               beat_addr, tr.data[i], dma_int_en_model))
                end
                if (tr.data[i][2]) begin
                    dma_done_model = 1'b1;
                end
            end
        end
    endfunction

    function void build_dma_copy_prediction();
        int unsigned words;
        logic [31:0] src_addr;
        logic [31:0] dst_addr;
        int unsigned src_key;
        int unsigned dst_key;

        if (dma_len_model == 0) begin
            return;
        end

        if (dma_len_model[1:0] != 2'b00 ||
            !is_sram_window(dma_src_model) ||
            !is_sram_window(dma_dst_model)) begin
            dma_copy_skip_count++;
            return;
        end

        words = dma_len_model >> 2;
        for (int unsigned i = 0; i < words; i++) begin
            src_addr = dma_src_model + (i << 2);
            dst_addr = dma_dst_model + (i << 2);
            src_key = sram_word_key(src_addr);
            dst_key = sram_word_key(dst_addr);

            if (sram_word_model.exists(src_key) &&
                sram_known_mask.exists(src_key) &&
                sram_known_mask[src_key] == 4'hF) begin
                dma_expected_word[dst_key] = sram_word_model[src_key];
                dma_expected_mask[dst_key] = 4'hF;
                dma_copy_update_count++;
            end else begin
                dma_copy_skip_count++;
            end
        end
    endfunction

    function void check_dma_sram_write(axi_transaction tr);
        logic [31:0] beat_addr;
        int unsigned key;
        logic [31:0] expected_word;
        logic [3:0]  expected_mask;
        logic [31:0] byte_mask;

        if (tr.id != 4'd2 || tr.trans_type != AXI_WRITE || tr.size != 3'b010) begin
            return;
        end

        foreach (tr.data[i]) begin
            beat_addr = tr.addr + (i << tr.size);
            key = sram_word_key(beat_addr);
            if (dma_expected_word.exists(key) && dma_expected_mask.exists(key)) begin
                expected_word = dma_expected_word[key];
                expected_mask = dma_expected_mask[key] & tr.strb[i];
                byte_mask = {{8{expected_mask[3]}}, {8{expected_mask[2]}}, {8{expected_mask[1]}}, {8{expected_mask[0]}}};
                if ((tr.data[i] & byte_mask) !== (expected_word & byte_mask)) begin
                    `uvm_error("SB_DMA_COPY", $sformatf("DMA write mismatch addr=0x%08h data=0x%08h expected=0x%08h mask=0x%08h",
                               beat_addr, tr.data[i], expected_word, byte_mask))
                end
                dma_copy_check_count++;
                dma_expected_word.delete(key);
                dma_expected_mask.delete(key);
            end else begin
                dma_copy_skip_count++;
            end
        end
    endfunction

    function void write_sram(axi_transaction tr);
        if (!is_sram_window(tr.addr)) begin
            `uvm_error("SB_SRAM_ADDR", $sformatf("SRAM monitor observed non-SRAM addr=0x%08h", tr.addr))
        end

        if (tr.trans_type == AXI_READ) begin
            sram_read_count++;
            check_read_responses(tr, `SOC_AXI_RESP_OKAY, "sram");
        end else begin
            sram_write_count++;
            check_write_response(tr, `SOC_AXI_RESP_OKAY, "sram");
            check_dma_sram_write(tr);
            if (tr.id == 4'd2) begin
                update_sram_model(tr);
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB_SUMMARY", $sformatf("ext reads=%0d writes=%0d; sram reads=%0d writes=%0d; gpio updates=%0d checks=%0d; uart updates=%0d checks=%0d; timer updates=%0d checks=%0d; pic updates=%0d checks=%0d; dma reg updates=%0d checks=%0d copy predictions=%0d checks=%0d skips=%0d; sram data updates=%0d checks=%0d; flash data checks=%0d",
                  ext_read_count, ext_write_count, sram_read_count, sram_write_count,
                  gpio_update_count, gpio_check_count, uart_update_count, uart_check_count,
                  timer_update_count, timer_check_count, pic_update_count, pic_check_count,
                  dma_reg_update_count, dma_reg_check_count, dma_copy_update_count,
                  dma_copy_check_count, dma_copy_skip_count,
                  sram_data_update_count,
                  sram_data_check_count, flash_data_check_count), UVM_LOW)
    endfunction
endclass

`endif
