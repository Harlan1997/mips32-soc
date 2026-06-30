MODULE: dcache
Fsm state
Transition REFILL_REQ->IDLE "reset"
Transition WRITE_BACK->IDLE "reset"
Transition REFILL_WAIT->IDLE "reset"
Transition REFILL_WRITE->IDLE "reset"

MODULE: icache
Fsm state
Transition REFILL_REQ->IDLE "reset"
Transition REFILL_WAIT->IDLE "reset"
Transition REFILL_WRITE->IDLE "reset"

MODULE: apb_axi_dma
Fsm state
Transition ST_AR->ST_IDLE "reset"
Transition ST_R->ST_IDLE "reset"
Transition ST_AW->ST_IDLE "reset"
Transition ST_W->ST_IDLE "reset"
Transition ST_B->ST_IDLE "reset"
