MODULE: dcache
Fsm state
Transition REFILL_REQ->IDLE "reset"
Transition UC_REQ->IDLE "reset"
Transition UC_WDATA->IDLE "reset"
Transition WRITEBACK_DATA->IDLE "reset"
Transition WRITEBACK_REQ->IDLE "reset"
Transition WRITEBACK_RESP->IDLE "reset"

MODULE: icache
Fsm state
Transition MISS->IDLE "reset"

MODULE: apb_axi_dma
Fsm state
Transition ST_AR->ST_IDLE "reset"
Transition ST_AW->ST_IDLE "reset"
Transition ST_R->ST_IDLE "reset"
Transition ST_W->ST_IDLE "reset"

MODULE: axi_sram
Fsm w_state
Transition W_DATA->W_IDLE "reset"

MODULE: axi2apb_bridge
Fsm state
Transition R_SETUP->IDLE "reset"
Transition W_ENABLE->IDLE "reset"
Transition W_SETUP->IDLE "reset"

MODULE: axi_spi_flash
Fsm state
Transition ADDR->IDLE "reset"
Transition CMD->IDLE "reset"
Transition READ->IDLE "reset"

MODULE: jtag_debug_top
Fsm axi_state
Transition ST_AR->ST_IDLE "reset"
Transition ST_AW->ST_IDLE "reset"
Transition ST_W->ST_IDLE "reset"
