INSTANCE: tb_mips_soc.u_soc.u_core.u_dcache
Fsm state
Transition REFILL_REQ->IDLE "reset"
Transition UC_REQ->IDLE "reset"
Transition UC_WDATA->IDLE "reset"
Transition WRITEBACK_DATA->IDLE "reset"
Transition WRITEBACK_REQ->IDLE "reset"
Transition WRITEBACK_RESP->IDLE "reset"

INSTANCE: tb_mips_soc.u_soc.u_core.u_icache
Fsm state
Transition MISS->IDLE "reset"

INSTANCE: tb_mips_soc.u_soc.u_apb_dma
Fsm state
Transition ST_AR->ST_IDLE "reset"
Transition ST_AW->ST_IDLE "reset"
Transition ST_R->ST_IDLE "reset"
Transition ST_W->ST_IDLE "reset"
