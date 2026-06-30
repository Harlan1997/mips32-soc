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
