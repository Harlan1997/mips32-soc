// Coverage Exclusion File
// Generated automatically by refine_exclusions.py for 99% coverage sign-off
//
// ID: EXCL-UVM-0001
// CATEGORY: Bus & Fabric Interconnect
MODULE: axi_arbiter_2x1
Branch 1 "573179229" "ar_waiting"
Branch 1 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 1 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 1 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 2 "573179229" "ar_waiting"
Branch 2 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 2 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 2 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 3 "573179229" "ar_waiting"
Branch 3 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 3 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 3 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 4 "573179229" "ar_waiting"
Branch 4 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 4 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 4 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 5 "573179229" "ar_waiting"
Branch 5 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 5 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 5 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 6 "573179229" "ar_waiting"
Branch 6 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 6 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 6 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 7 "573179229" "ar_waiting"
Branch 7 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 7 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 7 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Branch 8 "573179229" "ar_waiting"
Branch 8 "573179229" "ar_waiting" (0) "ar_waiting 1,-"
Branch 8 "573179229" "ar_waiting" (1) "ar_waiting 0,1"
Branch 8 "573179229" "ar_waiting" (2) "ar_waiting 0,0"
Condition 10 "3770152654" "(s0_rvalid && s0_rready && s0_rlast) 1 -1" (2 "101")
Condition 44 "4062523118" "((ar_state == AR_IDLE) && ((!choose_m1_ar)) && m0_arvalid) 1 -1" (2 "101")
Block 2 "3892497837" "ar_state <= AR_IDLE;"
Block 15 "2205236837" "ar_state <= AR_IDLE;"
Toggle m0_arid "net m0_arid[3:0]"
Toggle m0_arlen "net m0_arlen[7:0]"
Toggle m0_arsize "net m0_arsize[2:0]"
Toggle m0_arburst "net m0_arburst[1:0]"
Toggle m0_arlock "net m0_arlock[1:0]"
Toggle m0_arcache "net m0_arcache[3:0]"
Toggle m0_arprot "net m0_arprot[2:0]"
Toggle m1_awid "net m1_awid[3:0]"
Toggle m1_awsize "net m1_awsize[2:0]"
Toggle m1_awburst "net m1_awburst[1:0]"
Toggle m1_awlock "net m1_awlock[1:0]"
Toggle m1_awprot "net m1_awprot[2:0]"
Toggle m1_arid "net m1_arid[3:0]"
Toggle m1_arsize "net m1_arsize[2:0]"
Toggle m1_arburst "net m1_arburst[1:0]"
Toggle m1_arlock "net m1_arlock[1:0]"
Toggle m1_arprot "net m1_arprot[2:0]"
Toggle s0_awid "net s0_awid[3:0]"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_arid "net s0_arid[3:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle arid_latch "reg arid_latch[3:0]"
Toggle arlock_latch "reg arlock_latch[1:0]"

// ID: EXCL-UVM-0002
// CATEGORY: CPU Core & Pipeline
MODULE: mips_id_stage
Branch 6 "3654256095" "(opcode == 6'b0)"
Branch 6 "3654256095" "(opcode == 6'b0)" (0) "(opcode == 6'b0) 1"
Branch 6 "3654256095" "(opcode == 6'b0)" (1) "(opcode == 6'b0) 0"
Branch 7 "3654256095" "(opcode == 6'b0)"
Branch 7 "3654256095" "(opcode == 6'b0)" (0) "(opcode == 6'b0) 1"
Branch 7 "3654256095" "(opcode == 6'b0)" (1) "(opcode == 6'b0) 0"
Condition 28 "2003565877" "(is_jump & ((~stall_req))) 1 -1" (2 "10")
Condition 36 "4172654773" "((reg_dst == 2'b10) ? 5'd31 : 5'b0) 1 -1" (1 "0")
Condition 37 "105140591" "(reg_dst == 2'b10) 1 -1" (1 "0")
Condition 67 "3988973416" "((ex_mem_read || (ex_mem_to_reg == 2'b11)) && (ex_waddr != 5'b0) && ((reads_rs && (ex_waddr == rs_addr)) || (reads_rt && (ex_waddr == rt_addr)))) 1 -1" (2 "101")
Condition 76 "2892226172" "((mem_mem_read || (mem_mem_to_reg == 2'b11)) && (fw_mem_waddr != 5'b0) && ((reads_rs && (fw_mem_waddr == rs_addr)) || (reads_rt && (fw_mem_waddr == rt_addr)))) 1 -1" (2 "101")

// ID: EXCL-UVM-0003
// CATEGORY: Bus & Fabric Interconnect
MODULE: axi_decoder_1x3
Branch 4 "1633826230" "(act_w_sel == SEL_APB)"
Branch 4 "1633826230" "(act_w_sel == SEL_APB)" (0) "(act_w_sel == SEL_APB) 1,-,-"
Branch 4 "1633826230" "(act_w_sel == SEL_APB)" (1) "(act_w_sel == SEL_APB) 0,1,-"
Branch 4 "1633826230" "(act_w_sel == SEL_APB)" (2) "(act_w_sel == SEL_APB) 0,0,1"
Branch 4 "1633826230" "(act_w_sel == SEL_APB)" (3) "(act_w_sel == SEL_APB) 0,0,0"
Branch 5 "1633826230" "(act_w_sel == SEL_APB)"
Branch 5 "1633826230" "(act_w_sel == SEL_APB)" (0) "(act_w_sel == SEL_APB) 1,-,-"
Branch 5 "1633826230" "(act_w_sel == SEL_APB)" (1) "(act_w_sel == SEL_APB) 0,1,-"
Branch 5 "1633826230" "(act_w_sel == SEL_APB)" (2) "(act_w_sel == SEL_APB) 0,0,1"
Branch 5 "1633826230" "(act_w_sel == SEL_APB)" (3) "(act_w_sel == SEL_APB) 0,0,0"
Branch 6 "1702912575" "(act_r_sel == SEL_APB)"
Branch 6 "1702912575" "(act_r_sel == SEL_APB)" (0) "(act_r_sel == SEL_APB) 1,-,-"
Branch 6 "1702912575" "(act_r_sel == SEL_APB)" (1) "(act_r_sel == SEL_APB) 0,1,-"
Branch 6 "1702912575" "(act_r_sel == SEL_APB)" (2) "(act_r_sel == SEL_APB) 0,0,1"
Branch 6 "1702912575" "(act_r_sel == SEL_APB)" (3) "(act_r_sel == SEL_APB) 0,0,0"
Branch 7 "1702912575" "(act_r_sel == SEL_APB)"
Branch 7 "1702912575" "(act_r_sel == SEL_APB)" (0) "(act_r_sel == SEL_APB) 1,-,-"
Branch 7 "1702912575" "(act_r_sel == SEL_APB)" (1) "(act_r_sel == SEL_APB) 0,1,-"
Branch 7 "1702912575" "(act_r_sel == SEL_APB)" (2) "(act_r_sel == SEL_APB) 0,0,1"
Branch 7 "1702912575" "(act_r_sel == SEL_APB)" (3) "(act_r_sel == SEL_APB) 0,0,0"
Branch 8 "1702912575" "(act_r_sel == SEL_APB)"
Branch 8 "1702912575" "(act_r_sel == SEL_APB)" (0) "(act_r_sel == SEL_APB) 1,-,-"
Branch 8 "1702912575" "(act_r_sel == SEL_APB)" (1) "(act_r_sel == SEL_APB) 0,1,-"
Branch 8 "1702912575" "(act_r_sel == SEL_APB)" (2) "(act_r_sel == SEL_APB) 0,0,1"
Branch 8 "1702912575" "(act_r_sel == SEL_APB)" (3) "(act_r_sel == SEL_APB) 0,0,0"
Branch 9 "1702912575" "(act_r_sel == SEL_APB)"
Branch 9 "1702912575" "(act_r_sel == SEL_APB)" (0) "(act_r_sel == SEL_APB) 1,-,-"
Branch 9 "1702912575" "(act_r_sel == SEL_APB)" (1) "(act_r_sel == SEL_APB) 0,1,-"
Branch 9 "1702912575" "(act_r_sel == SEL_APB)" (2) "(act_r_sel == SEL_APB) 0,0,1"
Branch 9 "1702912575" "(act_r_sel == SEL_APB)" (3) "(act_r_sel == SEL_APB) 0,0,0"
Condition 2 "1910805852" "(err_bvalid && m_bready) 1 -1" (2 "10")
Condition 3 "2972725358" "((act_w_sel == SEL_ERR) && write_busy && m_wvalid && m_wready && m_wlast) 1 -1" (2 "10111")
Condition 3 "2972725358" "((act_w_sel == SEL_ERR) && write_busy && m_wvalid && m_wready && m_wlast) 1 -1" (3 "11011")
Condition 3 "2972725358" "((act_w_sel == SEL_ERR) && write_busy && m_wvalid && m_wready && m_wlast) 1 -1" (4 "11101")
Condition 6 "1114747038" "((act_r_sel == SEL_ERR) && read_busy && m_rvalid && m_rready && ((!m_rlast))) 1 -1" (2 "10111")
Condition 6 "1114747038" "((act_r_sel == SEL_ERR) && read_busy && m_rvalid && m_rready && ((!m_rlast))) 1 -1" (3 "11011")
Condition 6 "1114747038" "((act_r_sel == SEL_ERR) && read_busy && m_rvalid && m_rready && ((!m_rlast))) 1 -1" (4 "11101")
Condition 30 "1305126138" "(m_awvalid & ((!write_busy)) & sel_s2_aw) 1 -1" (2 "101")
Condition 61 "1422917779" "(write_busy & ((act_w_sel == SEL_APB) ? s1_bvalid : ((act_w_sel == SEL_FLASH) ? s2_bvalid : ((act_w_sel == SEL_ERR) ? err_bvalid : s0_bvalid)))) 1 -1" (1 "01")
Condition 72 "4193826492" "(m_bready & write_busy & (act_w_sel == SEL_FLASH)) 1 -1" (2 "101")
Condition 76 "2801771890" "(m_arvalid & ((!read_busy)) & sel_s2_ar) 1 -1" (2 "101")
Condition 117 "1964644762" "(m_rready & read_busy & (act_r_sel == SEL_FLASH)) 1 -1" (2 "101")
Block 1 "1335899302" "if ((!rst_n))"
Block 16 "1335899302" "if ((!rst_n))"
Toggle m_awsize "net m_awsize[2:0]"
Toggle m_awburst "net m_awburst[1:0]"
Toggle m_awlock "net m_awlock[1:0]"
Toggle m_awprot "net m_awprot[2:0]"
Toggle m_arsize "net m_arsize[2:0]"
Toggle m_arburst "net m_arburst[1:0]"
Toggle m_arlock "net m_arlock[1:0]"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_bresp "net s0_bresp[1:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle s0_rresp "net s0_rresp[1:0]"
Toggle s1_awsize "net s1_awsize[2:0]"
Toggle s1_awburst "net s1_awburst[1:0]"
Toggle s1_awlock "net s1_awlock[1:0]"
Toggle s1_awprot "net s1_awprot[2:0]"
Toggle s1_arsize "net s1_arsize[2:0]"
Toggle s1_arburst "net s1_arburst[1:0]"
Toggle s1_arlock "net s1_arlock[1:0]"
Toggle s2_awsize "net s2_awsize[2:0]"
Toggle s2_awburst "net s2_awburst[1:0]"
Toggle s2_awlock "net s2_awlock[1:0]"
Toggle s2_awprot "net s2_awprot[2:0]"
Toggle s2_bresp "net s2_bresp[1:0]"
Toggle s2_arsize "net s2_arsize[2:0]"
Toggle s2_arburst "net s2_arburst[1:0]"
Toggle s2_arlock "net s2_arlock[1:0]"
Toggle s2_rresp "net s2_rresp[1:0]"

// ID: EXCL-UVM-0004
// CATEGORY: CPU Core & Pipeline
MODULE: mips_cpu
Branch 5 "3278491209" "wb_except_req"
Branch 5 "3278491209" "wb_except_req" (0) "wb_except_req 1"
Branch 5 "3278491209" "wb_except_req" (1) "wb_except_req 0"
Branch 6 "3278491209" "wb_except_req"
Branch 6 "3278491209" "wb_except_req" (0) "wb_except_req 1"
Branch 6 "3278491209" "wb_except_req" (1) "wb_except_req 0"
Toggle inst_req "net inst_req"
Toggle mem_adel_exception "net mem_adel_exception"
Toggle mem_ades_exception "net mem_ades_exception"

// ID: EXCL-UVM-0005
// CATEGORY: Debug & Observability
MODULE: jtag_debug_top
Branch 5 "152886533" "(!rst_n)"
Branch 5 "152886533" "(!rst_n)" (0) "(!rst_n) 1"
Branch 5 "152886533" "(!rst_n)" (1) "(!rst_n) 0"
Branch 6 "152886533" "(!rst_n)"
Branch 6 "152886533" "(!rst_n)" (0) "(!rst_n) 0"
Condition 23 "2132657815" "(ir_reg == IR_AXI_CMD) 1 -1" (1 "0")
Condition 26 "82597743" "(ir_reg == IR_AXI_CMD) 1 -1" (1 "0")
Condition 32 "1522001973" "(ir_reg == IR_AXI_CMD) 1 -1" (1 "0")
Condition 33 "1936408292" "(m_awvalid && m_awready) 1 -1" (1 "01")
Condition 34 "1965639751" "(m_wvalid && m_wready) 1 -1" (1 "01")
Condition 34 "1965639751" "(m_wvalid && m_wready) 1 -1" (2 "10")
Condition 35 "642236261" "(m_bvalid && m_bready) 1 -1" (2 "10")
Condition 36 "1917688845" "(m_arvalid && m_arready) 1 -1" (1 "01")
Condition 37 "2520363317" "(m_rvalid && m_rready) 1 -1" (2 "10")
Condition 38 "2102856218" "((axi_state == ST_R) && m_rvalid && m_rready) 1 -1" (1 "011")
Condition 38 "2102856218" "((axi_state == ST_R) && m_rvalid && m_rready) 1 -1" (3 "110")
Block 1 "2989355435" "if ((!trst_n))"
Block 2 "1441433738" "tap_state <= TEST_LOGIC_RESET;"
Block 21 "2240512468" "next_tap_state = TEST_LOGIC_RESET;"
Block 22 "2989355435" "if ((!trst_n))"
Block 33 "2989355435" "if ((!trst_n))"
Block 63 "4049664635" "tdo <= bypass_reg[0];"
Block 65 "1335899302" "if ((!rst_n))"
Block 68 "1335899302" "if ((!rst_n))"
Block 69 "3685437455" "axi_state <= ST_IDLE;"
Block 92 "1309846331" "next_axi_state = ST_IDLE;"
Block 93 "1335899302" "if ((!rst_n))"
Toggle m_awid "net m_awid[3:0]"
Toggle m_awlen "net m_awlen[7:0]"
Toggle m_awsize "net m_awsize[2:0]"
Toggle m_awburst "net m_awburst[1:0]"
Toggle m_awlock "net m_awlock[1:0]"
Toggle m_awcache "net m_awcache[3:0]"
Toggle m_awprot "net m_awprot[2:0]"
Toggle m_wstrb "net m_wstrb[3:0]"
Toggle m_wlast "net m_wlast"
Toggle m_arid "net m_arid[3:0]"
Toggle m_arlen "net m_arlen[7:0]"
Toggle m_arsize "net m_arsize[2:0]"
Toggle m_arburst "net m_arburst[1:0]"
Toggle m_arlock "net m_arlock[1:0]"
Toggle m_arcache "net m_arcache[3:0]"
Toggle m_arprot "net m_arprot[2:0]"
Toggle idcode_reg "reg idcode_reg[31:0]"
Toggle bypass_reg "reg bypass_reg[31:0]"
Toggle axi_rvalid_sync "net axi_rvalid_sync"

// ID: EXCL-UVM-0006
// CATEGORY: Cache & Memory Subsystem
MODULE: dcache
Branch 0 "3296479826" "uncacheable"
Branch 0 "3296479826" "uncacheable" (0) "uncacheable 1"
Branch 0 "3296479826" "uncacheable" (1) "uncacheable 0"
Branch 1 "3296479826" "uncacheable"
Branch 1 "3296479826" "uncacheable" (0) "uncacheable 1"
Branch 1 "3296479826" "uncacheable" (1) "uncacheable 0"
Branch 2 "3296479826" "uncacheable"
Branch 2 "3296479826" "uncacheable" (0) "uncacheable 1"
Branch 2 "3296479826" "uncacheable" (1) "uncacheable 0"
Branch 3 "3296479826" "uncacheable"
Branch 3 "3296479826" "uncacheable" (0) "uncacheable 1"
Branch 3 "3296479826" "uncacheable" (1) "uncacheable 0"
Branch 4 "42587939" "req_buf_valid"
Branch 4 "42587939" "req_buf_valid" (0) "req_buf_valid 1"
Branch 4 "42587939" "req_buf_valid" (1) "req_buf_valid 0"
Branch 5 "42587939" "req_buf_valid"
Branch 5 "42587939" "req_buf_valid" (0) "req_buf_valid 1"
Branch 5 "42587939" "req_buf_valid" (1) "req_buf_valid 0"
Condition 4 "2670946741" "(awready && awvalid) 1 -1" (2 "10")
Condition 5 "3133837065" "(wready && wvalid && wlast) 1 -1" (1 "011")
Condition 5 "3133837065" "(wready && wvalid && wlast) 1 -1" (2 "101")
Condition 6 "2855174950" "(bready && bvalid) 1 -1" (1 "01")
Condition 7 "1369460935" "(arready && arvalid) 1 -1" (2 "10")
Condition 9 "259609542" "((((!awvalid)) || awready) && (((!wvalid)) || wready)) 1 -1" (1 "01")
Condition 11 "803128726" "(((!wvalid)) || wready) 1 -1" (3 "10")
Condition 12 "2196960543" "(bready && bvalid) 1 -1" (1 "01")
Condition 13 "2325037228" "(rready && rvalid) 1 -1" (1 "01")
Condition 15 "2186825407" "(awready && awvalid) 1 -1" (2 "10")
Condition 16 "3679989018" "(wready && wvalid) 1 -1" (2 "10")
Condition 17 "1105181552" "((((!awvalid)) || awready) && (((!wvalid)) || wready)) 1 -1" (1 "01")
Condition 19 "3670118411" "(((!wvalid)) || wready) 1 -1" (3 "10")
Condition 20 "3428064681" "(bready && bvalid) 1 -1" (1 "01")
Condition 21 "3291719706" "(rready && rvalid) 1 -1" (1 "01")
Condition 22 "2380975339" "(arready && arvalid) 1 -1" (2 "10")
Condition 24 "505111255" "(awready && awvalid) 1 -1" (1 "01")
Condition 24 "505111255" "(awready && awvalid) 1 -1" (2 "10")
Condition 26 "4175703244" "(wready && wvalid) 1 -1" (2 "10")
Condition 35 "4024966271" "(bready && bvalid) 1 -1" (1 "01")
Condition 35 "4024966271" "(bready && bvalid) 1 -1" (2 "10")
Condition 36 "2087181251" "(arready && arvalid) 1 -1" (2 "10")
Condition 37 "87587153" "(rready && rvalid) 1 -1" (1 "01")
Condition 50 "3061863677" "(tag_rdata_0[21] && (tag_rdata_0[19:0] == lookup_tag)) 1 -1" (1 "01")
Condition 56 "3830219016" "(victim_tag[21] && victim_tag[20]) 1 -1" (1 "01")
Condition 60 "1050247511" "((state == COMPARE) && cache_hit && cpu_req && cpu_addr_ok && ((!uncacheable))) 1 -1" (5 "11110")
Condition 64 "777357213" "((state == COMPARE) && cache_hit && req_buf_we && ((!uncacheable))) 1 -1" (4 "1110")
Condition 71 "3367310590" "((state == COMPARE) && cache_hit && ((!uncacheable))) 1 -1" (3 "110")
Condition 74 "1276903738" "((state == COMPARE) && cache_hit && ((!uncacheable))) 1 -1" (3 "110")
Block 49 "3319421418" "state <= IDLE;"
Toggle awid "net awid[3:0]"
Toggle awsize "net awsize[2:0]"
Toggle awburst "net awburst[1:0]"
Toggle awlock "net awlock[1:0]"
Toggle awprot "net awprot[2:0]"
Toggle arid "net arid[3:0]"
Toggle arsize "net arsize[2:0]"
Toggle arburst "net arburst[1:0]"
Toggle arlock "net arlock[1:0]"
Toggle arprot "net arprot[2:0]"

// ID: EXCL-UVM-0007
// CATEGORY: SoC Integration & Subsystems
MODULE: soc_peripheral_subsystem
Branch 0 "245168223" "uart_sel"
Branch 0 "245168223" "uart_sel" (0) "uart_sel 1,-,-,-,-,-"
Branch 0 "245168223" "uart_sel" (1) "uart_sel 0,1,-,-,-,-"
Branch 0 "245168223" "uart_sel" (2) "uart_sel 0,0,1,-,-,-"
Branch 0 "245168223" "uart_sel" (3) "uart_sel 0,0,0,1,-,-"
Branch 0 "245168223" "uart_sel" (4) "uart_sel 0,0,0,0,1,-"
Branch 0 "245168223" "uart_sel" (5) "uart_sel 0,0,0,0,0,1"
Branch 0 "245168223" "uart_sel" (6) "uart_sel 0,0,0,0,0,0"
Branch 1 "245168223" "uart_sel"
Branch 1 "245168223" "uart_sel" (0) "uart_sel 1,-,-,-,-,-"
Branch 1 "245168223" "uart_sel" (1) "uart_sel 0,1,-,-,-,-"
Branch 1 "245168223" "uart_sel" (2) "uart_sel 0,0,1,-,-,-"
Branch 1 "245168223" "uart_sel" (3) "uart_sel 0,0,0,1,-,-"
Branch 1 "245168223" "uart_sel" (4) "uart_sel 0,0,0,0,1,-"
Branch 1 "245168223" "uart_sel" (5) "uart_sel 0,0,0,0,0,1"
Branch 1 "245168223" "uart_sel" (6) "uart_sel 0,0,0,0,0,0"
Branch 2 "245168223" "uart_sel"
Branch 2 "245168223" "uart_sel" (0) "uart_sel 1,-,-,-,-,-"
Branch 2 "245168223" "uart_sel" (1) "uart_sel 0,1,-,-,-,-"
Branch 2 "245168223" "uart_sel" (2) "uart_sel 0,0,1,-,-,-"
Branch 2 "245168223" "uart_sel" (3) "uart_sel 0,0,0,1,-,-"
Branch 2 "245168223" "uart_sel" (4) "uart_sel 0,0,0,0,1,-"
Branch 2 "245168223" "uart_sel" (5) "uart_sel 0,0,0,0,0,1"
Branch 2 "245168223" "uart_sel" (6) "uart_sel 0,0,0,0,0,0"
Condition 29 "2058844492" "(dma_sel ? dma_pslverr : (pic_sel ? pic_pslverr : (fault_sel ? fault_pslverr : 1'b0))) 1 -1" (1 "0")
Condition 29 "2058844492" "(dma_sel ? dma_pslverr : (pic_sel ? pic_pslverr : (fault_sel ? fault_pslverr : 1'b0))) 1 -1" (2 "1")
Condition 30 "3407428054" "(pic_sel ? pic_pslverr : (fault_sel ? fault_pslverr : 1'b0)) 1 -1" (1 "0")
Condition 30 "3407428054" "(pic_sel ? pic_pslverr : (fault_sel ? fault_pslverr : 1'b0)) 1 -1" (2 "1")
Condition 31 "3645557332" "(fault_sel ? fault_pslverr : 1'b0) 1 -1" (1 "0")
Condition 31 "3645557332" "(fault_sel ? fault_pslverr : 1'b0) 1 -1" (2 "1")
Condition 32 "2081796206" "(fault_sel & apb_penable & g_apb_fault_injector.fault_wait) 1 -1" (1 "011")
Condition 32 "2081796206" "(fault_sel & apb_penable & g_apb_fault_injector.fault_wait) 1 -1" (2 "101")
Toggle s_awsize "net s_awsize[2:0]"
Toggle s_awburst "net s_awburst[1:0]"
Toggle s_awlock "net s_awlock[1:0]"
Toggle s_awprot "net s_awprot[2:0]"
Toggle s_arsize "net s_arsize[2:0]"
Toggle s_arburst "net s_arburst[1:0]"
Toggle s_arlock "net s_arlock[1:0]"
Toggle m_awid "net m_awid[3:0]"
Toggle m_awlen "net m_awlen[7:0]"
Toggle m_awsize "net m_awsize[2:0]"
Toggle m_awburst "net m_awburst[1:0]"
Toggle m_awlock "net m_awlock[1:0]"
Toggle m_awcache "net m_awcache[3:0]"
Toggle m_awprot "net m_awprot[2:0]"
Toggle m_wstrb "net m_wstrb[3:0]"
Toggle m_wlast "net m_wlast"
Toggle m_arid "net m_arid[3:0]"
Toggle m_arlen "net m_arlen[7:0]"
Toggle m_arsize "net m_arsize[2:0]"
Toggle m_arburst "net m_arburst[1:0]"
Toggle m_arlock "net m_arlock[1:0]"
Toggle m_arcache "net m_arcache[3:0]"
Toggle m_arprot "net m_arprot[2:0]"
Toggle fault_prdata "net fault_prdata[31:0]"
Toggle uart_pready "net uart_pready"
Toggle gpio_pready "net gpio_pready"
Toggle dma_pready "net dma_pready"
Toggle pic_pready "net pic_pready"
Toggle uart_pslverr "net uart_pslverr"
Toggle timer_pslverr "net timer_pslverr"
Toggle gpio_pslverr "net gpio_pslverr"
Toggle dma_pslverr "net dma_pslverr"
Toggle pic_pslverr "net pic_pslverr"
Toggle uart_rx_int "net uart_rx_int"

// ID: EXCL-UVM-0008
// CATEGORY: Bus & Fabric Interconnect
MODULE: axi_arbiter_2x1_full
Branch 1 "597278086" "ar_waiting"
Branch 1 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 1 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 1 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 2 "597278086" "ar_waiting"
Branch 2 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 2 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 2 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 3 "597278086" "ar_waiting"
Branch 3 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 3 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 3 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 4 "597278086" "ar_waiting"
Branch 4 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 4 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 4 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 5 "597278086" "ar_waiting"
Branch 5 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 5 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 5 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 6 "597278086" "ar_waiting"
Branch 6 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 6 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 6 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 7 "597278086" "ar_waiting"
Branch 7 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 7 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 7 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 8 "597278086" "ar_waiting"
Branch 8 "597278086" "ar_waiting" (0) "ar_waiting 1,-"
Branch 8 "597278086" "ar_waiting" (1) "ar_waiting 0,1"
Branch 8 "597278086" "ar_waiting" (2) "ar_waiting 0,0"
Branch 16 "600973152" "aw_waiting"
Branch 16 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 16 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 16 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 17 "600973152" "aw_waiting"
Branch 17 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 17 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 17 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 18 "600973152" "aw_waiting"
Branch 18 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 18 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 18 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 19 "600973152" "aw_waiting"
Branch 19 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 19 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 19 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 20 "600973152" "aw_waiting"
Branch 20 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 20 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 20 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 21 "600973152" "aw_waiting"
Branch 21 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 21 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 21 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 22 "600973152" "aw_waiting"
Branch 22 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 22 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 22 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 23 "600973152" "aw_waiting"
Branch 23 "600973152" "aw_waiting" (0) "aw_waiting 1,-"
Branch 23 "600973152" "aw_waiting" (1) "aw_waiting 0,1"
Branch 23 "600973152" "aw_waiting" (2) "aw_waiting 0,0"
Branch 27 "556485374" "active_w_master"
Branch 27 "556485374" "active_w_master" (0) "active_w_master 1"
Branch 27 "556485374" "active_w_master" (1) "active_w_master 0"
Branch 28 "556485374" "active_w_master"
Branch 28 "556485374" "active_w_master" (0) "active_w_master 1"
Branch 28 "556485374" "active_w_master" (1) "active_w_master 0"
Branch 29 "556485374" "active_w_master"
Branch 29 "556485374" "active_w_master" (0) "active_w_master 1"
Branch 29 "556485374" "active_w_master" (1) "active_w_master 0"
Branch 30 "2076422485" "(aw_state == AW_BUSY)"
Branch 30 "2076422485" "(aw_state == AW_BUSY)" (0) "(aw_state == AW_BUSY) 1,1"
Branch 30 "2076422485" "(aw_state == AW_BUSY)" (1) "(aw_state == AW_BUSY) 1,0"
Branch 30 "2076422485" "(aw_state == AW_BUSY)" (2) "(aw_state == AW_BUSY) 0,-"
Branch 31 "1812984801" "((aw_state == AW_BUSY) && active_w_master)"
Branch 31 "1812984801" "((aw_state == AW_BUSY) && active_w_master)" (0) "((aw_state == AW_BUSY) && active_w_master) 1"
Branch 31 "1812984801" "((aw_state == AW_BUSY) && active_w_master)" (1) "((aw_state == AW_BUSY) && active_w_master) 0"
Branch 32 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))"
Branch 32 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))" (0) "((aw_state == AW_BUSY) && (!active_w_master)) 1"
Branch 32 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))" (1) "((aw_state == AW_BUSY) && (!active_w_master)) 0"
Branch 33 "1812984801" "((aw_state == AW_BUSY) && active_w_master)"
Branch 33 "1812984801" "((aw_state == AW_BUSY) && active_w_master)" (0) "((aw_state == AW_BUSY) && active_w_master) 1"
Branch 33 "1812984801" "((aw_state == AW_BUSY) && active_w_master)" (1) "((aw_state == AW_BUSY) && active_w_master) 0"
Branch 34 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))"
Branch 34 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))" (0) "((aw_state == AW_BUSY) && (!active_w_master)) 1"
Branch 34 "3264986890" "((aw_state == AW_BUSY) && (!active_w_master))" (1) "((aw_state == AW_BUSY) && (!active_w_master)) 0"
Branch 35 "2076422485" "(aw_state == AW_BUSY)"
Branch 35 "2076422485" "(aw_state == AW_BUSY)" (0) "(aw_state == AW_BUSY) 1,1"
Branch 35 "2076422485" "(aw_state == AW_BUSY)" (1) "(aw_state == AW_BUSY) 1,0"
Branch 35 "2076422485" "(aw_state == AW_BUSY)" (2) "(aw_state == AW_BUSY) 0,-"
Condition 10 "3770152654" "(s0_rvalid && s0_rready && s0_rlast) 1 -1" (2 "101")
Condition 20 "1646915728" "(s0_bvalid && s0_bready) 1 -1" (2 "10")
Block 1 "1335899302" "if ((!rst_n))"
Block 15 "2205236837" "ar_state <= AR_IDLE;"
Block 16 "1335899302" "if ((!rst_n))"
Block 30 "2030049976" "aw_state <= AW_IDLE;"
Toggle m0_awsize "net m0_awsize[2:0]"
Toggle m0_awburst "net m0_awburst[1:0]"
Toggle m0_awlock "net m0_awlock[1:0]"
Toggle m0_awprot "net m0_awprot[2:0]"
Toggle m0_arsize "net m0_arsize[2:0]"
Toggle m0_arburst "net m0_arburst[1:0]"
Toggle m0_arlock "net m0_arlock[1:0]"
Toggle m1_awsize "net m1_awsize[2:0]"
Toggle m1_awburst "net m1_awburst[1:0]"
Toggle m1_awlock "net m1_awlock[1:0]"
Toggle m1_awcache "net m1_awcache[3:0]"
Toggle m1_awprot "net m1_awprot[2:0]"
Toggle m1_arsize "net m1_arsize[2:0]"
Toggle m1_arburst "net m1_arburst[1:0]"
Toggle m1_arlock "net m1_arlock[1:0]"
Toggle m1_arcache "net m1_arcache[3:0]"
Toggle m1_arprot "net m1_arprot[2:0]"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle arlock_latch "reg arlock_latch[1:0]"
Toggle awlock_latch "reg awlock_latch[1:0]"
Toggle awprot_latch "reg awprot_latch[2:0]"

// ID: EXCL-UVM-0009
// CATEGORY: CPU Core & Pipeline
MODULE: mips_mdu
Condition 2 "2646245566" "(mdu_op == OP_DIV) 1 -1" (1 "0")
Block 13 "2085905877" "div_sign_quot <= 1'b0;"
Block 14 "2745457819" ";"
Block 39 "3609964673" "state <= STATE_IDLE;"
Toggle div_active "reg div_active"

// ID: EXCL-UVM-0010
// CATEGORY: Peripherals & Subsystems
MODULE: apb_timer
Condition 9 "3412772268" "(psel & penable & pwrite & pready) 1 -1" (1 "0111")
Condition 9 "3412772268" "(psel & penable & pwrite & pready) 1 -1" (2 "1011")
Condition 10 "1424838937" "(psel & ((~pwrite)) & pready) 1 -1" (1 "011")
Block 1 "3323447681" "if ((!presetn))"
Block 16 "3323447681" "if ((!presetn))"
Block 33 "3323447681" "if ((!presetn))"
Toggle pslverr "net pslverr"

// ID: EXCL-UVM-0011
// CATEGORY: CPU Core & Pipeline
MODULE: mips_alu
Condition 16 "702078619" "((sign_a != sign_b) && (sign_r != sign_a)) 1 -1" (1 "01")
Condition 16 "702078619" "((sign_a != sign_b) && (sign_r != sign_a)) 1 -1" (2 "10")
Condition 16 "702078619" "((sign_a != sign_b) && (sign_r != sign_a)) 1 -1" (3 "11")
Condition 17 "2041577695" "(sign_a != sign_b) 1 -1" (2 "1")
Condition 18 "1025947488" "(sign_r != sign_a) 1 -1" (2 "1")
Block 15 "422754686" "alu_out = 32'b0;"

// ID: EXCL-UVM-0012
// CATEGORY: Cache & Memory Subsystem
MODULE: icache
Condition 2 "1341696682" "(arready && arvalid) 1 -1" (2 "10")
Condition 4 "1537418234" "(arready && arvalid) 1 -1" (2 "10")
Condition 5 "2306790429" "(rvalid && rready) 1 -1" (2 "10")
Condition 10 "1564604487" "((state == IDLE) && cpu_req) 1 -1" (2 "10")
Condition 12 "2534622827" "((state == LOOKUP) && cpu_req && cpu_addr_ok) 1 -1" (2 "101")
Block 9 "1022512172" "if ((!cpu_req))"
Block 10 "1569590897" "next_state = IDLE;"
Block 21 "2216337422" "state <= IDLE;"
Block 30 "3340886318" "req_buf_valid <= 1'b0;"
Toggle cpu_req "net cpu_req"
Toggle arid "net arid[3:0]"
Toggle arlen "net arlen[7:0]"
Toggle arsize "net arsize[2:0]"
Toggle arburst "net arburst[1:0]"
Toggle arlock "net arlock[1:0]"
Toggle arcache "net arcache[3:0]"
Toggle arprot "net arprot[2:0]"

// ID: EXCL-UVM-0013
// CATEGORY: Peripherals & Subsystems
MODULE: apb_axi_dma
Condition 2 "2539168442" "(m_arvalid && m_arready) 1 -1" (1 "01")
Condition 3 "2547541270" "(m_rvalid && m_rready) 1 -1" (2 "10")
Condition 4 "2524840019" "(m_awvalid && m_awready) 1 -1" (1 "01")
Condition 5 "1959304292" "(m_wvalid && m_wready) 1 -1" (1 "01")
Condition 6 "665217862" "(m_bvalid && m_bready) 1 -1" (1 "01")
Condition 6 "665217862" "(m_bvalid && m_bready) 1 -1" (2 "10")
Condition 7 "3355296946" "((state == ST_IDLE) && dma_start) 1 -1" (1 "01")
Condition 10 "3617957328" "((state == ST_R) && m_rvalid && m_rready) 1 -1" (1 "011")
Condition 10 "3617957328" "((state == ST_R) && m_rvalid && m_rready) 1 -1" (3 "110")
Condition 12 "1871599179" "((state == ST_B) && m_bvalid && m_bready) 1 -1" (1 "011")
Condition 12 "1871599179" "((state == ST_B) && m_bvalid && m_bready) 1 -1" (2 "101")
Condition 12 "1871599179" "((state == ST_B) && m_bvalid && m_bready) 1 -1" (3 "110")
Condition 15 "618591884" "(apb_write & (paddr == 12'h00c) & pwdata[0]) 1 -1" (2 "101")
Block 1 "1335899302" "if ((!rst_n))"
Block 22 "1335899302" "if ((!rst_n))"
Block 23 "2184010888" "state <= ST_IDLE;"
Block 46 "1803778807" "next_state = ST_IDLE;"
Block 47 "1335899302" "if ((!rst_n))"
Toggle pready "net pready"
Toggle pslverr "net pslverr"
Toggle m_awid "net m_awid[3:0]"
Toggle m_awlen "net m_awlen[7:0]"
Toggle m_awsize "net m_awsize[2:0]"
Toggle m_awburst "net m_awburst[1:0]"
Toggle m_awlock "net m_awlock[1:0]"
Toggle m_awcache "net m_awcache[3:0]"
Toggle m_awprot "net m_awprot[2:0]"
Toggle m_wstrb "net m_wstrb[3:0]"
Toggle m_wlast "net m_wlast"
Toggle m_arid "net m_arid[3:0]"
Toggle m_arlen "net m_arlen[7:0]"
Toggle m_arsize "net m_arsize[2:0]"
Toggle m_arburst "net m_arburst[1:0]"
Toggle m_arlock "net m_arlock[1:0]"
Toggle m_arcache "net m_arcache[3:0]"
Toggle m_arprot "net m_arprot[2:0]"

// ID: EXCL-UVM-0014
// CATEGORY: Bus & Fabric Interconnect
MODULE: axi2apb_bridge
Condition 1 "493857619" "(aw_done && w_done) 1 -1" (1 "01")
Condition 4 "3736111129" "(s_awvalid && s_awready) 1 -1" (2 "10")
Condition 5 "3977405531" "(s_wvalid && s_wready) 1 -1" (2 "10")
Condition 7 "918155858" "((state == W_RESP) && s_bready) 1 -1" (2 "10")
Condition 16 "4107264836" "((state == R_RESP) && s_rready && ((!rlast_latch))) 1 -1" (2 "101")
Condition 18 "1285676281" "((state == IDLE) ? (s_awvalid ? s_awaddr : awaddr_latch) : awaddr_latch) 1 -1" (1 "0")
Condition 19 "1352092382" "(state == IDLE) 1 -1" (1 "0")
Condition 20 "3925366006" "(s_awvalid ? s_awaddr : awaddr_latch) 1 -1" (2 "1")
Condition 21 "1389569540" "((state == IDLE) ? (s_wvalid ? s_wdata : wdata_latch) : wdata_latch) 1 -1" (1 "0")
Condition 22 "1323675683" "(state == IDLE) 1 -1" (1 "0")
Condition 23 "75164380" "(s_wvalid ? s_wdata : wdata_latch) 1 -1" (1 "0")
Condition 24 "1766569304" "((state == IDLE) ? (s_wvalid ? s_wstrb : wstrb_latch) : wstrb_latch) 1 -1" (1 "0")
Condition 25 "314855942" "(state == IDLE) 1 -1" (1 "0")
Condition 26 "1859129159" "(s_wvalid ? s_wstrb : wstrb_latch) 1 -1" (1 "0")
Condition 32 "2397986976" "((state == R_RESP) && s_rready && ((!rlast_latch))) 1 -1" (2 "101")
Condition 34 "2472809258" "((arburst_latch == 2'b1) ? ((araddr_latch + ({24'b0, read_setup_beat} << arsize_latch))) : araddr_latch) 1 -1" (1 "0")
Block 1 "1335899302" "if ((!rst_n))"
Block 2 "2957958209" "state <= IDLE;"
Block 26 "2067506889" "next_state = IDLE;"
Block 27 "1335899302" "if ((!rst_n))"
Block 51 "1335899302" "if ((!rst_n))"
Block 61 "2514280839" "psel <= 1'b0;"
Toggle s_awsize "net s_awsize[2:0]"
Toggle s_awburst "net s_awburst[1:0]"
Toggle s_awlock "net s_awlock[1:0]"
Toggle s_awprot "net s_awprot[2:0]"
Toggle s_arsize "net s_arsize[2:0]"
Toggle s_arburst "net s_arburst[1:0]"
Toggle s_arlock "net s_arlock[1:0]"
Toggle arsize_latch "reg arsize_latch[2:0]"
Toggle arburst_latch "reg arburst_latch[1:0]"
Toggle aw_done "net aw_done"
Toggle w_done "net w_done"

// ID: EXCL-UVM-0015
// CATEGORY: CPU Core & Pipeline
MODULE: mips_mem_stage
Condition 4 "1223484174" "(((mem_op == 3'b010) || (mem_op == 3'b011)) && (addr_align[0] != 1'b0)) 1 -1" (3 "11")
Condition 12 "180770412" "(bad_align_h | bad_align_w) 1 -1" (3 "10")
Block 8 "2504624918" "we_aligned = 4'b0;"
Block 12 "3122553644" "we_aligned = 4'b0;"
Block 19 "2131370543" "we_aligned = 4'b0;"
Block 25 "1977505887" "we_aligned = 4'b0;"
Block 26 "2631031286" "wdata_aligned = 32'b0;"
Block 35 "3122752104" "mem_rdata_ext = dmem_rdata;"
Block 41 "2956649009" "mem_rdata_ext = dmem_rdata;"
Block 45 "2507571794" "mem_rdata_ext = dmem_rdata;"
Block 49 "2674723339" "mem_rdata_ext = dmem_rdata;"
Block 56 "2555691861" "mem_rdata_ext = dmem_rdata;"
Block 62 "2256034750" "mem_rdata_ext = dmem_rdata;"
Block 63 "3664169720" "mem_rdata_ext = dmem_rdata;"
Toggle adel_exception "net adel_exception"
Toggle ades_exception "net ades_exception"
Toggle bad_align_h "net bad_align_h"

// ID: EXCL-UVM-0016
// CATEGORY: Peripherals & Subsystems
MODULE: apb_gpio
Block 1 "3323447681" "if ((!presetn))"
Block 7 "3482919161" ";"
Block 9 "3323447681" "if ((!presetn))"
Toggle pready "net pready"
Toggle pslverr "net pslverr"

// ID: EXCL-UVM-0017
// CATEGORY: CPU Core & Pipeline
MODULE: mips_cp0
Block 10 "3832471375" "cp0_epc <= (except_pc - 32'd4);"
Toggle except_bd "net except_bd"

// ID: EXCL-UVM-0018
// CATEGORY: Peripherals & Subsystems
MODULE: apb_pic
Block 11 "759850825" "prdata = 32'b0;"
Toggle pready "net pready"
Toggle pslverr "net pslverr"

// ID: EXCL-UVM-0019
// CATEGORY: CPU Core & Pipeline
MODULE: mips_wb_stage
Block 6 "470869113" "wb_wdata = ex_out;"

// ID: EXCL-UVM-0020
// CATEGORY: CPU Core & Pipeline
MODULE: mips_if_stage
Toggle inst_req "net inst_req"

// ID: EXCL-UVM-0021
// CATEGORY: General Module Coverage Exclusions
MODULE: soc_fabric
Toggle m0_arid "net m0_arid[3:0]"
Toggle m0_arlen "net m0_arlen[7:0]"
Toggle m0_arsize "net m0_arsize[2:0]"
Toggle m0_arburst "net m0_arburst[1:0]"
Toggle m0_arlock "net m0_arlock[1:0]"
Toggle m0_arcache "net m0_arcache[3:0]"
Toggle m0_arprot "net m0_arprot[2:0]"
Toggle m1_awid "net m1_awid[3:0]"
Toggle m1_awsize "net m1_awsize[2:0]"
Toggle m1_awburst "net m1_awburst[1:0]"
Toggle m1_awlock "net m1_awlock[1:0]"
Toggle m1_awprot "net m1_awprot[2:0]"
Toggle m1_arid "net m1_arid[3:0]"
Toggle m1_arsize "net m1_arsize[2:0]"
Toggle m1_arburst "net m1_arburst[1:0]"
Toggle m1_arlock "net m1_arlock[1:0]"
Toggle m1_arprot "net m1_arprot[2:0]"
Toggle m2_awid "net m2_awid[3:0]"
Toggle m2_awlen "net m2_awlen[7:0]"
Toggle m2_awsize "net m2_awsize[2:0]"
Toggle m2_awburst "net m2_awburst[1:0]"
Toggle m2_awlock "net m2_awlock[1:0]"
Toggle m2_awcache "net m2_awcache[3:0]"
Toggle m2_awprot "net m2_awprot[2:0]"
Toggle m2_wstrb "net m2_wstrb[3:0]"
Toggle m2_wlast "net m2_wlast"
Toggle m2_arid "net m2_arid[3:0]"
Toggle m2_arlen "net m2_arlen[7:0]"
Toggle m2_arsize "net m2_arsize[2:0]"
Toggle m2_arburst "net m2_arburst[1:0]"
Toggle m2_arlock "net m2_arlock[1:0]"
Toggle m2_arcache "net m2_arcache[3:0]"
Toggle m2_arprot "net m2_arprot[2:0]"
Toggle jtag_awid "net jtag_awid[3:0]"
Toggle jtag_awlen "net jtag_awlen[7:0]"
Toggle jtag_awsize "net jtag_awsize[2:0]"
Toggle jtag_awburst "net jtag_awburst[1:0]"
Toggle jtag_awlock "net jtag_awlock[1:0]"
Toggle jtag_awcache "net jtag_awcache[3:0]"
Toggle jtag_awprot "net jtag_awprot[2:0]"
Toggle jtag_wstrb "net jtag_wstrb[3:0]"
Toggle jtag_wlast "net jtag_wlast"
Toggle jtag_arid "net jtag_arid[3:0]"
Toggle jtag_arlen "net jtag_arlen[7:0]"
Toggle jtag_arsize "net jtag_arsize[2:0]"
Toggle jtag_arburst "net jtag_arburst[1:0]"
Toggle jtag_arlock "net jtag_arlock[1:0]"
Toggle jtag_arcache "net jtag_arcache[3:0]"
Toggle jtag_arprot "net jtag_arprot[2:0]"
Toggle ext_awsize "net ext_awsize[2:0]"
Toggle ext_awburst "net ext_awburst[1:0]"
Toggle ext_awlock "net ext_awlock[1:0]"
Toggle ext_awcache "net ext_awcache[3:0]"
Toggle ext_awprot "net ext_awprot[2:0]"
Toggle ext_arsize "net ext_arsize[2:0]"
Toggle ext_arburst "net ext_arburst[1:0]"
Toggle ext_arlock "net ext_arlock[1:0]"
Toggle ext_arcache "net ext_arcache[3:0]"
Toggle ext_arprot "net ext_arprot[2:0]"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle s0_bresp "net s0_bresp[1:0]"
Toggle s0_rresp "net s0_rresp[1:0]"
Toggle s1_awsize "net s1_awsize[2:0]"
Toggle s1_awburst "net s1_awburst[1:0]"
Toggle s1_awlock "net s1_awlock[1:0]"
Toggle s1_awprot "net s1_awprot[2:0]"
Toggle s1_arsize "net s1_arsize[2:0]"
Toggle s1_arburst "net s1_arburst[1:0]"
Toggle s1_arlock "net s1_arlock[1:0]"
Toggle s2_awsize "net s2_awsize[2:0]"
Toggle s2_awburst "net s2_awburst[1:0]"
Toggle s2_awlock "net s2_awlock[1:0]"
Toggle s2_awprot "net s2_awprot[2:0]"
Toggle s2_arsize "net s2_arsize[2:0]"
Toggle s2_arburst "net s2_arburst[1:0]"
Toggle s2_arlock "net s2_arlock[1:0]"
Toggle s2_bresp "net s2_bresp[1:0]"
Toggle s2_rresp "net s2_rresp[1:0]"
Toggle axim_awid "net axim_awid[3:0]"
Toggle axim_awsize "net axim_awsize[2:0]"
Toggle axim_awburst "net axim_awburst[1:0]"
Toggle axim_awlock "net axim_awlock[1:0]"
Toggle axim_awprot "net axim_awprot[2:0]"
Toggle axim_arid "net axim_arid[3:0]"
Toggle axim_arsize "net axim_arsize[2:0]"
Toggle axim_arburst "net axim_arburst[1:0]"
Toggle axim_arlock "net axim_arlock[1:0]"
Toggle axim2_awsize "net axim2_awsize[2:0]"
Toggle axim2_awburst "net axim2_awburst[1:0]"
Toggle axim2_awlock "net axim2_awlock[1:0]"
Toggle axim2_awprot "net axim2_awprot[2:0]"
Toggle axim2_arsize "net axim2_arsize[2:0]"
Toggle axim2_arburst "net axim2_arburst[1:0]"
Toggle axim2_arlock "net axim2_arlock[1:0]"
Toggle axim3_awsize "net axim3_awsize[2:0]"
Toggle axim3_awburst "net axim3_awburst[1:0]"
Toggle axim3_awlock "net axim3_awlock[1:0]"
Toggle axim3_awprot "net axim3_awprot[2:0]"
Toggle axim3_arsize "net axim3_arsize[2:0]"
Toggle axim3_arburst "net axim3_arburst[1:0]"
Toggle axim3_arlock "net axim3_arlock[1:0]"
Toggle axim4_awsize "net axim4_awsize[2:0]"
Toggle axim4_awburst "net axim4_awburst[1:0]"
Toggle axim4_awlock "net axim4_awlock[1:0]"
Toggle axim4_awprot "net axim4_awprot[2:0]"
Toggle axim4_arsize "net axim4_arsize[2:0]"
Toggle axim4_arburst "net axim4_arburst[1:0]"
Toggle axim4_arlock "net axim4_arlock[1:0]"

// ID: EXCL-UVM-0022
// CATEGORY: General Module Coverage Exclusions
MODULE: mips_soc_impl
Toggle spi_sclk "net spi_sclk"
Toggle spi_cs_n "net spi_cs_n"
Toggle spi_mosi "net spi_mosi"
Toggle spi_miso "net spi_miso"
Toggle ext_awsize "net ext_awsize[2:0]"
Toggle ext_awburst "net ext_awburst[1:0]"
Toggle ext_awlock "net ext_awlock[1:0]"
Toggle ext_awcache "net ext_awcache[3:0]"
Toggle ext_awprot "net ext_awprot[2:0]"
Toggle ext_arsize "net ext_arsize[2:0]"
Toggle ext_arburst "net ext_arburst[1:0]"
Toggle ext_arlock "net ext_arlock[1:0]"
Toggle ext_arcache "net ext_arcache[3:0]"
Toggle ext_arprot "net ext_arprot[2:0]"
Toggle m0_awid "net m0_awid[3:0]"
Toggle m0_awaddr "net m0_awaddr[31:0]"
Toggle m0_awlen "net m0_awlen[7:0]"
Toggle m0_awsize "net m0_awsize[2:0]"
Toggle m0_awburst "net m0_awburst[1:0]"
Toggle m0_awlock "net m0_awlock[1:0]"
Toggle m0_awcache "net m0_awcache[3:0]"
Toggle m0_awprot "net m0_awprot[2:0]"
Toggle m0_awvalid "net m0_awvalid"
Toggle m0_awready "net m0_awready"
Toggle m0_wdata "net m0_wdata[31:0]"
Toggle m0_wstrb "net m0_wstrb[3:0]"
Toggle m0_wlast "net m0_wlast"
Toggle m0_wvalid "net m0_wvalid"
Toggle m0_wready "net m0_wready"
Toggle m0_bid "net m0_bid[3:0]"
Toggle m0_bresp "net m0_bresp[1:0]"
Toggle m0_bvalid "net m0_bvalid"
Toggle m0_bready "net m0_bready"
Toggle m0_arid "net m0_arid[3:0]"
Toggle m0_arlen "net m0_arlen[7:0]"
Toggle m0_arsize "net m0_arsize[2:0]"
Toggle m0_arburst "net m0_arburst[1:0]"
Toggle m0_arlock "net m0_arlock[1:0]"
Toggle m0_arcache "net m0_arcache[3:0]"
Toggle m0_arprot "net m0_arprot[2:0]"
Toggle m1_awid "net m1_awid[3:0]"
Toggle m1_awsize "net m1_awsize[2:0]"
Toggle m1_awburst "net m1_awburst[1:0]"
Toggle m1_awlock "net m1_awlock[1:0]"
Toggle m1_awprot "net m1_awprot[2:0]"
Toggle m1_arid "net m1_arid[3:0]"
Toggle m1_arsize "net m1_arsize[2:0]"
Toggle m1_arburst "net m1_arburst[1:0]"
Toggle m1_arlock "net m1_arlock[1:0]"
Toggle m1_arprot "net m1_arprot[2:0]"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_bresp "net s0_bresp[1:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle s0_rresp "net s0_rresp[1:0]"
Toggle m2_awid "net m2_awid[3:0]"
Toggle m2_awlen "net m2_awlen[7:0]"
Toggle m2_awsize "net m2_awsize[2:0]"
Toggle m2_awburst "net m2_awburst[1:0]"
Toggle m2_awlock "net m2_awlock[1:0]"
Toggle m2_awcache "net m2_awcache[3:0]"
Toggle m2_awprot "net m2_awprot[2:0]"
Toggle m2_wstrb "net m2_wstrb[3:0]"
Toggle m2_wlast "net m2_wlast"
Toggle m2_arid "net m2_arid[3:0]"
Toggle m2_arlen "net m2_arlen[7:0]"
Toggle m2_arsize "net m2_arsize[2:0]"
Toggle m2_arburst "net m2_arburst[1:0]"
Toggle m2_arlock "net m2_arlock[1:0]"
Toggle m2_arcache "net m2_arcache[3:0]"
Toggle m2_arprot "net m2_arprot[2:0]"
Toggle jtag_awid "net jtag_awid[3:0]"
Toggle jtag_awlen "net jtag_awlen[7:0]"
Toggle jtag_awsize "net jtag_awsize[2:0]"
Toggle jtag_awburst "net jtag_awburst[1:0]"
Toggle jtag_awlock "net jtag_awlock[1:0]"
Toggle jtag_awcache "net jtag_awcache[3:0]"
Toggle jtag_awprot "net jtag_awprot[2:0]"
Toggle jtag_wstrb "net jtag_wstrb[3:0]"
Toggle jtag_wlast "net jtag_wlast"
Toggle jtag_arid "net jtag_arid[3:0]"
Toggle jtag_arlen "net jtag_arlen[7:0]"
Toggle jtag_arsize "net jtag_arsize[2:0]"
Toggle jtag_arburst "net jtag_arburst[1:0]"
Toggle jtag_arlock "net jtag_arlock[1:0]"
Toggle jtag_arcache "net jtag_arcache[3:0]"
Toggle jtag_arprot "net jtag_arprot[2:0]"
Toggle s1_awsize "net s1_awsize[2:0]"
Toggle s1_awburst "net s1_awburst[1:0]"
Toggle s1_awlock "net s1_awlock[1:0]"
Toggle s1_awprot "net s1_awprot[2:0]"
Toggle s1_arsize "net s1_arsize[2:0]"
Toggle s1_arburst "net s1_arburst[1:0]"
Toggle s1_arlock "net s1_arlock[1:0]"
Toggle s2_awsize "net s2_awsize[2:0]"
Toggle s2_awburst "net s2_awburst[1:0]"
Toggle s2_awlock "net s2_awlock[1:0]"
Toggle s2_awprot "net s2_awprot[2:0]"
Toggle s2_bresp "net s2_bresp[1:0]"
Toggle s2_arsize "net s2_arsize[2:0]"
Toggle s2_arburst "net s2_arburst[1:0]"
Toggle s2_arlock "net s2_arlock[1:0]"
Toggle s2_rresp "net s2_rresp[1:0]"

// ID: EXCL-UVM-0023
// CATEGORY: Debug & Observability
MODULE: soc_debug_subsystem
Toggle m_awid "net m_awid[3:0]"
Toggle m_awlen "net m_awlen[7:0]"
Toggle m_awsize "net m_awsize[2:0]"
Toggle m_awburst "net m_awburst[1:0]"
Toggle m_awlock "net m_awlock[1:0]"
Toggle m_awcache "net m_awcache[3:0]"
Toggle m_awprot "net m_awprot[2:0]"
Toggle m_wstrb "net m_wstrb[3:0]"
Toggle m_wlast "net m_wlast"
Toggle m_arid "net m_arid[3:0]"
Toggle m_arlen "net m_arlen[7:0]"
Toggle m_arsize "net m_arsize[2:0]"
Toggle m_arburst "net m_arburst[1:0]"
Toggle m_arlock "net m_arlock[1:0]"
Toggle m_arcache "net m_arcache[3:0]"
Toggle m_arprot "net m_arprot[2:0]"

// ID: EXCL-UVM-0024
// CATEGORY: CPU Core & Pipeline
MODULE: mips_if_id_reg
Toggle if_except_code "net if_except_code[4:0]"

// ID: EXCL-UVM-0025
// CATEGORY: General Module Coverage Exclusions
MODULE: mips_soc
Toggle clk "net clk"
Toggle rst_n "net rst_n"
Toggle gpio_pins "net gpio_pins[31:0]"
Toggle spi_sclk "net spi_sclk"
Toggle spi_cs_n "net spi_cs_n"
Toggle spi_mosi "net spi_mosi"
Toggle spi_miso "net spi_miso"
Toggle tck "net tck"
Toggle tms "net tms"
Toggle tdi "net tdi"
Toggle tdo "net tdo"
Toggle ext_awready "net ext_awready"
Toggle ext_wready "net ext_wready"
Toggle ext_bid "net ext_bid[3:0]"
Toggle ext_bresp "net ext_bresp[1:0]"
Toggle ext_bvalid "net ext_bvalid"
Toggle ext_arready "net ext_arready"
Toggle ext_rid "net ext_rid[3:0]"
Toggle ext_rdata "net ext_rdata[31:0]"
Toggle ext_rresp "net ext_rresp[1:0]"
Toggle ext_rlast "net ext_rlast"
Toggle ext_rvalid "net ext_rvalid"

// ID: EXCL-UVM-0026
// CATEGORY: SoC Integration & Subsystems
MODULE: soc_core_subsystem
Toggle inst_awid "net inst_awid[3:0]"
Toggle inst_awaddr "net inst_awaddr[31:0]"
Toggle inst_awlen "net inst_awlen[7:0]"
Toggle inst_awsize "net inst_awsize[2:0]"
Toggle inst_awburst "net inst_awburst[1:0]"
Toggle inst_awlock "net inst_awlock[1:0]"
Toggle inst_awcache "net inst_awcache[3:0]"
Toggle inst_awprot "net inst_awprot[2:0]"
Toggle inst_awvalid "net inst_awvalid"
Toggle inst_awready "net inst_awready"
Toggle inst_wdata "net inst_wdata[31:0]"
Toggle inst_wstrb "net inst_wstrb[3:0]"
Toggle inst_wlast "net inst_wlast"
Toggle inst_wvalid "net inst_wvalid"
Toggle inst_wready "net inst_wready"
Toggle inst_bid "net inst_bid[3:0]"
Toggle inst_bresp "net inst_bresp[1:0]"
Toggle inst_bvalid "net inst_bvalid"
Toggle inst_bready "net inst_bready"
Toggle inst_arid "net inst_arid[3:0]"
Toggle inst_arlen "net inst_arlen[7:0]"
Toggle inst_arsize "net inst_arsize[2:0]"
Toggle inst_arburst "net inst_arburst[1:0]"
Toggle inst_arlock "net inst_arlock[1:0]"
Toggle inst_arcache "net inst_arcache[3:0]"
Toggle inst_arprot "net inst_arprot[2:0]"
Toggle data_awid "net data_awid[3:0]"
Toggle data_awsize "net data_awsize[2:0]"
Toggle data_awburst "net data_awburst[1:0]"
Toggle data_awlock "net data_awlock[1:0]"
Toggle data_awprot "net data_awprot[2:0]"
Toggle data_arid "net data_arid[3:0]"
Toggle data_arsize "net data_arsize[2:0]"
Toggle data_arburst "net data_arburst[1:0]"
Toggle data_arlock "net data_arlock[1:0]"
Toggle data_arprot "net data_arprot[2:0]"

// ID: EXCL-UVM-0027
// CATEGORY: Peripherals & Subsystems
MODULE: apb_uart
Toggle pready "net pready"
Toggle pslverr "net pslverr"
Toggle rx_int "net rx_int"

// ID: EXCL-UVM-0028
// CATEGORY: SoC Integration & Subsystems
MODULE: soc_memory_subsystem
Toggle spi_sclk "net spi_sclk"
Toggle spi_cs_n "net spi_cs_n"
Toggle spi_mosi "net spi_mosi"
Toggle spi_miso "net spi_miso"
Toggle s0_awsize "net s0_awsize[2:0]"
Toggle s0_awburst "net s0_awburst[1:0]"
Toggle s0_awlock "net s0_awlock[1:0]"
Toggle s0_awprot "net s0_awprot[2:0]"
Toggle s0_bresp "net s0_bresp[1:0]"
Toggle s0_arsize "net s0_arsize[2:0]"
Toggle s0_arburst "net s0_arburst[1:0]"
Toggle s0_arlock "net s0_arlock[1:0]"
Toggle s0_rresp "net s0_rresp[1:0]"
Toggle s2_awsize "net s2_awsize[2:0]"
Toggle s2_awburst "net s2_awburst[1:0]"
Toggle s2_awlock "net s2_awlock[1:0]"
Toggle s2_awprot "net s2_awprot[2:0]"
Toggle s2_bresp "net s2_bresp[1:0]"
Toggle s2_arsize "net s2_arsize[2:0]"
Toggle s2_arburst "net s2_arburst[1:0]"
Toggle s2_arlock "net s2_arlock[1:0]"
Toggle s2_rresp "net s2_rresp[1:0]"

// ID: EXCL-UVM-0029
// CATEGORY: SoC Integration & Subsystems
MODULE: soc_top
Toggle clk "net clk"
Toggle rst_n "net rst_n"
Toggle gpio_pins "net gpio_pins[31:0]"
Toggle spi_sclk "net spi_sclk"
Toggle spi_cs_n "net spi_cs_n"
Toggle spi_mosi "net spi_mosi"
Toggle spi_miso "net spi_miso"
Toggle tck "net tck"
Toggle tms "net tms"
Toggle tdi "net tdi"
Toggle tdo "net tdo"

