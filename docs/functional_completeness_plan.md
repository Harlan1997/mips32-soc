# SoC 功能完整性计划

> 版本：v0.4（2026-08-01）
>
> 目标：建立一条可复现、可审计的 SoC 功能完整性主线，并明确区分“当前 RTL 契约通过”和“商用 SoC 功能完成”。本文优先覆盖产品架构、RTL 集成、块级验证、firmware 与 SoC UVM；覆盖率只保留为历史风险记录，不是当前执行主线。Lint、CDC/RDC、formal、综合/时序和 PPA 明确暂缓，不作为本阶段 gate。

## 1. 完成等级

每项功能必须逐级推进，禁止直接把块级通过标成 SoC 完成：

1. `IMPLEMENTED`：RTL 已提交，接口和非目标已写入 spec。
2. `BLOCK_VERIFIED`：块级 directed/negative/reset 测试通过。
3. `SOC_INTEGRATED`：接入产品 SoC，firmware 和 SoC UVM 通过。
4. `CONTRACT_CLOSED`：多 seed、错误路径、复位/背压、scoreboard、功能覆盖率和当前契约签收通过。
5. `PRODUCT_FUNCTION_READY`：产品 boot、存储器、CPU 特权路径、对外 I/O、外设、中断和系统软件入口均已接入并有对应 SoC 证据。

`CONTRACT_CLOSED` 不代表 `PRODUCT_FUNCTION_READY`，更不代表 tapeout ready。最终物理和静态签核暂缓。

## 2. 当前基线快照

| 对象 | 状态 | 处理 |
|---|---|---|
| `master@6ecbbbc` | 当前产品基线，已包含 C3 crossbar 和 Phase 4 商用模块历史 | 作为集成基线 |
| `integration/function-contract@8b3dc6b` | 唯一功能集成线；以 C2 `fcfc9c1` 为父线，已合入 C1 4-way I-cache | 当前验证和后续产品功能变更只在此线收敛，暂不直接推入 `master` |
| `phase-c2-l2-nonblocking@fcfc9c1` | 比 `master` 多 7 个提交；含已独立提交的 JTAG、firmware、gate 与本计划修复 | 已是集成线父线；L2-NB、ROB、DDR placeholder 的产品状态仍须分项判断 |
| `phase-c1-icache-4way@d695cb5` | 已由 merge commit `8b3dc6b` 合入集成线 | 保留为历史分支，不再重复 merge |
| `phase-c3-axi-crossbar`、`phase4-dut-block-commercial-closure` | 已为 `master` 祖先 | 只保留历史引用，禁止重复合并 |
| D-cache NB WIP：`feature/dcache-nb-stage3@fcfc9c1` | 未跟踪 `rtl/cache/dcache_nb.v`、`tb/unit/dcache/tb_dcache_nb.v`，以及相关 spec/gate 修改 | 已有唯一 feature 分支，但仍仅为 `BLOCK_VERIFIED`；未接入 CPU/SoC，不能计入 SoC 功能完成 |
| 本轮功能修复/验证改动 | JTAG `7f74345`、firmware `1288681`、gate 隔离 `324d663`、原始计划 `fcfc9c1` 已分别提交 | 已进入集成线父线；不得与 D-cache NB WIP 混合提交 |
| Coverage 生成工件 | `product_exclusions.el`、`uvm_exclusions.el` 和 `exclusion_manifest.json` 已由 fresh VDB 重生成但 strict URG 仍报 invalid object/checksum mismatch | 保留作 P3 调查输入；在告警清零和人工审计前不得提交或作为 coverage signoff 依据 |
| `stash@{0}` | C3 遗留 WIP，含旧 fabric/coverage 变更 | 审计后 apply 或归档，禁止盲删 |
| 最新 full signoff | `build/signoff/functional_completeness_20260801` 已完成所有 5 个功能阶段；只在 99% code-coverage threshold 失败 | 功能结果可用于当前 RTL contract 证据；coverage closure 保留为 P3，不能发布 `CONTRACT_CLOSED` |

## 3. 商用 SoC 功能判断

**结论：当前项目不是功能完整的商用 SoC。** 它已经具备可执行的 MIPS32 原型 SoC 和一套通过的当前 RTL 契约回归，但产品启动、真实主存、MMU 启用、对外 UART、QSPI boot 和系统软件入口尚未闭合。块级 RTL 存在或 unit test 通过均不能替代该结论。

| 域 | 当前产品集成 | 已有测试证据 | 商用功能结论 |
|---|---|---|---|
| CPU/CP0 | 已接入；默认 `SOC_MMU_ENABLE=0` | smoke 与 Phase 3A/3B CPU/CP0 gate 通过，最新 `intr=11 syscall=1 ri=4 adel=1 eret=16` | 仅当前异常/中断子集已验证；无 ISA reference/compliance，MMU 打开后不能启动 |
| L1 cache | 阻塞式 D-cache 在 DUT；4-way I-cache 已合入 `integration/function-contract` | D-cache unit、`cache_sweep` 与 smoke 通过；合入后 unit gate `9/9`、SoC smoke 和 seed 10 UVM stress 通过 | I-cache 具备当前集成基线的 block/通用 SoC 证据；尚缺 refill/eviction/reset 的 I-cache 专项 SoC 测试，不能标为 `CONTRACT_CLOSED` |
| L2 cache | 默认 write-through L2 已接入；write-back 为 opt-in | L2 unit、L2 firmware、Phase 2/3 与 smoke 通过 | 当前 blocking L2 契约可用；不具备 coherency/ECC/生产性能闭合 |
| AXI fabric | C3 crossbar 已在 `master`；DDR 是 S3 slave | fabric unit `4/4`，Phase 2/3、10-seed stress 通过 | cross-slave 并发已验证；同一 slave 仍受单 outstanding slave 限制 |
| DMA | 已接入 APB/AXI | DMA unit、DMA firmware、DMA copy/IRQ UVM 通过；grant stability 修复已在 C2 集成父线 | 当前 direct-copy/IRQ 契约有证据；不可宣称 IOMMU/coherency 或完整系统 DMA 生态 |
| VIC/interrupt | 已接入 CPU 单 IRQ 线，源为 UART/TIMER/DMA | VIC unit、VIC firmware、PIC mask UVM 通过 | mask/active 已验证；CPU 侧无向量化 EIC/VEIC 产品契约，UART RX source 当前不可用 |
| UART | `apb_uart_16550` 已接入 APB，但产品 top 没有 UART pins；子系统将 `uart_rx` 固定为 `1`、`uart_rx_int` 固定为 `0` | UART unit 和 UART firmware gate 通过；UVM 仅覆盖 TX IRQ | UART block 不是产品级 UART；TX/RX pad、RX IRQ 和板级驱动未闭合 |
| DDR | S3 使用 `axi_ddr_behavioral` 容量占位模型 | `xbar_ddr` unit 通过 | 无 DDR controller/PHY/校准/refresh/DDR boot，属于 P0 blocker |
| Flash/boot | `axi_spi_flash` 支持简单 SPI read XIP；验证可选用 loadable AXI image | flash read/write response、loadable image UVM 通过 | 无 boot ROM、QSPI command/FIFO/erase/program 或 U-Boot boot，属于 P0 blocker |
| MMU/TLB | RTL 与 unit TB 存在，但默认关闭 | MMU/CP0 unit 及脚手架存在；`SOC_MMU_ENABLE=1` smoke/refill gate 预期失败 | reset/exception vector 位于 useg 导致取指死锁；须先迁移到 kseg0/1 并实现 vector policy |
| WDT/clock/reset | `apb_wdt`、clock/reset helper RTL 存在 | 无 WDT 集成或专用产品 gate；产品 top 只有单一 `clk/rst_n` | 未形成产品 reset/clock/watchdog 功能链 |
| Debug/JTAG | 产品 top 接入 JTAG | JTAG reset-recovery UVM 与合入后 seed 10 bus stress 通过；AXI payload 锁存修复为 `7f74345` | 当前仿真功能可用；产品级 debug security/authentication 和量产工具链仍未定义 |

## 4. 唯一集成与合并计划

当前不得直接向 `master` 混合提交。按下面顺序建立唯一集成线：

| 变更集 | 文件范围 | 当前状态 | 处理规则 |
|---|---|---|---|
| `fix(jtag-axi-contract)` | `rtl/perips/jtag_debug_top.v`、`tb/uvm_tb/checkers/axi_protocol_checker.sv`、`tb/uvm_tb/tb_top/tb_top.sv` | commit `7f74345`；seed 10 stress 已通过 | 已进入集成线父线，不与 firmware 或 cache WIP 混合 |
| `test(firmware-failures-and-div)` | `tb/soc_test/fw/tests/mdu_cpu/main.c`、`tb/soc_test/fw/tests/soc_smoke/main.c` | commit `1288681`；mdu_cpu DIV 与 smoke 已通过 | 已进入集成线父线；保留 raw `div` 指令和 failure mailbox 语义 |
| `test(clean-run-gates)` | 四个 `tb/uvm_tb/run_phase*_complete.sh` | commit `324d663`；`bash -n` 与 Phase 2 hardened run 通过 | 已进入集成线父线；这是证据可复现性修复，不是 RTL feature |
| `feat(dcache-nb-stage3)` | `rtl/cache/dcache_nb.v`、`tb/unit/dcache/tb_dcache_nb.v`、D-cache spec/roadmap/checklist、`tb/unit/run_dut_block_unit_gate.sh` | 位于 `feature/dcache-nb-stage3@fcfc9c1` 的 untracked RTL/TB 加本地文档与 gate WIP；block gate `9/9` | 单独留在 feature branch；不得改产品默认 `dcache.v` 或与 C1 unit-gate 更新混合 |
| `docs(functional-readiness)` | `docs/functional_completeness_plan.md` | `fcfc9c1` 为初版；本次集成证据以独立文档提交记录 | 文档不与 RTL feature 或 D-cache NB WIP 混合 |
| `coverage-generated-artifacts` | `tb/coverage/exclusion_manifest.json`、`product_exclusions.el`、`uvm_exclusions.el` | 自动生成且 strict URG 仍失败 | 不 stage、不 commit；留作后续 P3 调查输入 |

1. 已冻结并分类：D-cache NB WIP、JTAG/firmware/gate commits、coverage 生成工件和文档彼此隔离；禁止跨类别提交。
2. `integration/function-contract` 已从 `phase-c2-l2-nonblocking@fcfc9c1` 建立。C2 的 L2-NB、ROB skeleton、DDR placeholder、MMU 脚手架和 DMA 修复仍按产品接入状态分项判断，不能整体标记为“商用缓存/DDR/MMU完成”。
3. `phase-c1-icache-4way` 已以 `8b3dc6b` 合入；人工合并的文档和 unit gate 已通过 `bash -n` 及合并后 unit gate `9/9`。同一基线的 SoC smoke 与 seed 10 UVM stress 均通过。
4. JTAG AXI payload 锁存、protocol checker bind/packing 与 firmware failure-mailbox 已作为独立 commit 固化，并在集成基线重复 seed 10 bus stress。
5. D-cache NB 保持在 `feature/dcache-nb-stage3`，当前只能是 `BLOCK_VERIFIED`；在 CPU/ROB tag、hazard/forwarding 和 SoC stress 完成前禁止合入产品默认路径。
6. `phase-c3-axi-crossbar` 与 `phase4-dut-block-commercial-closure` 均已是 `master` 祖先，只归档引用，禁止再次 merge。`stash@{0}` 只审计、不删除；其内容不进入集成线，除非被拆成可验证主题。

退出条件：存在一个干净的 integration branch；每个 WIP 有唯一主题与 commit 归属；每个已合入功能都有同一基线上的 block/firmware/SoC 证据。

## 5. 执行顺序

### Phase 0：状态冻结

- 以 `master@6ecbbbc` 建立唯一集成线；每个主题功能使用独立分支或提交。
- 把未提交的 D-cache NB 工作保存为一个可审阅变更集；默认不接入 `mips_soc`。
- 对每项功能登记：spec、RTL commit、块级日志、firmware 日志、UVM 日志、coverage 报告和残余风险。
- 对旧分支和 stash 做一次归档决策，完成前不删除任何引用。

退出条件：工作区状态可解释，所有 WIP 都有归属，集成基线唯一。

### Phase 1：当前 RTL 契约恢复

按以下顺序执行，任何一步失败都停止向后推进：

1. `make firmware`
2. `make dut-block-unit-gate`
3. `make fabric-unit-gate`
4. `make soc-smoke`
5. `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix`
6. `make phase2-complete`
7. `make phase3-complete`
8. `make phase3b-complete` 和 `make phase3c-complete`
9. `make current-contract-signoff`

Phase 1 的关闭条件是：seed 10 无 checker/scoreboard/error，full signoff 生成 clean report，且所有必需功能覆盖组达到当前门槛。

### Phase 2：产品启动与主存闭合

- 冻结 ROM boot 地址、异常向量和 firmware linker 规则；不能继续从 useg reset vector 启动。
- 实现或集成真实 DDR controller/PHY contract；完成 init、calibration、refresh、AXI backpressure 与 DDR memory test。
- 实现实际 QSPI boot source（XIP/command path、image format、boot ROM）并完成 reset 到 first-stage firmware 的 SoC gate。
- 在 Phase 2 完成前，禁止把 behavioral DDR 或 loadable flash-image 测试称为产品 boot/memory 闭合。

### Phase 3：CPU、缓存和总线功能闭合

- 4-way I-cache 已合入并完成通用 unit/SoC 证据；补 refill、eviction、reset 的专项 SoC sequence 后，才能将其标为 `CONTRACT_CLOSED`。
- 将 C.2 变更拆成 L2-NB、ROB、DDR placeholder、DMA 修复四个可审阅主题。
- 保持 `dcache_nb.v` 独立，先完成 block gate；之后进行 C.4 Stage 4：CPU/ROB tag、完成重排、load-use hazard 和 forwarding。
- 只有完成 CPU 接入、SoC smoke、UVM overlap/stress 和性能前后对比后，D-cache NB 才能变成 `SOC_INTEGRATED`。
- 明确当前限制：1 MSHR、2-slot order queue、下游单 outstanding；2+ MSHR、store buffer 和完整 CACHE 指令继续列为 backlog。

### Phase 4：外设与系统软件功能闭合

- `SOC_MMU_ENABLE=1`：在 boot/vector relocation 后，完成 refill、invalid/modified、EBase/BEV 和 kernel-mode firmware gate。
- CPU/CP0：补 MIPS ISA compliance 与 reference-model lockstep；现有 exception smoke 只作为子集证据。
- 外设：把 UART TX/RX/flow-control 接到产品 pins，完成 RX IRQ；接入 WDT 并验证 reset path；补齐 GPIO/timer 产品软件驱动。
- 中断：定义 CPU-visible priority/vector contract，验证 VIC source mapping、mask、priority、nesting 与 reset。
- 系统软件：完成 U-Boot/Linux boot、basic driver regression 和可复现的长时间稳定性测试。

### Phase 5：产品功能版本发布

- 冻结版本号、基线 commit、firmware SHA256、testlist、seed 范围和报告目录。
- 生成 current-contract signoff 报告和未决问题清单。
- 只有 Phase 1-4 的功能证据齐全，才允许发布 `PRODUCT_FUNCTION_READY`；在此之前只能发布“当前 RTL 契约功能完成”，不使用“商用 SoC 完成”措辞。

## 6. 每项功能的关闭证据

登记表至少包含：

`Feature | Owner | Spec | RTL Commit | Unit | Firmware | SoC UVM | Negative/Reset/Stress | Functional Coverage | Report | Residual Risk | Level`

覆盖率必须与范围绑定：当前契约使用 `signoff_criteria.md` 的门槛；最终 99% 目标保留在 vPlan，不得混写成同一个 gate。覆盖率治理不阻塞当前 Phase 0 分支整理和 Phase 2 产品启动/主存架构工作。

## 7. 暂缓项

以下项目本轮只记录，不执行或阻塞功能 gate：

- Lint
- CDC/RDC
- Formal
- 综合/时序
- PPA

## 8. 当前执行点

固定 `seed=10`、块级 gate、fabric gate、SoC smoke、Phase 2、Phase 3A/3B/3C 和 10-seed stress 均已通过。C1 已在唯一集成线完成合并后 unit gate、SoC smoke 和 seed 10 UVM stress。完整 `current-contract-signoff` 的功能阶段均通过；coverage 阈值单独失败，保留为后续质量工作。**Phase 0 的 C1/C2 分支整理已完成；下一步是 Phase 2 boot 与真实主存的架构定义，不是 coverage closure。**

## 9. 执行记录

| 时间 | 基线 | 命令 | 结果 | 结论 |
|---|---|---|---|---|
| 2026-08-01 | `phase-c2-l2-nonblocking@4baf139`，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix` | FAIL：14.49 us 时 SRAM/S0 AR payload 在 `ARVALID && !ARREADY` 期间变化，14.51 us 时 `ARVALID` 提前撤销；随后 CPU memory stall 直至 watchdog | `4baf139` 未关闭该 SoC blocker。暂停 Phase 1 的后续 gate，先定位 S0 AR 驱动路径。日志：`build/uvm/seed10_dma_fix/vcs_uvm.log` |
| 2026-08-01 | 当前工作区，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_jtag_payload_fix` | PASS：`REGRESSION_TEST_SUCCESS`，无 UVM error/fatal 或 `$error` | 根因是 TCK 域命令寄存器在 AXI 请求等待期间直接改变 master payload。JTAG 启动请求时锁存地址/写数据到 `clk` 域后，S0 和 JTAG master 的 AXI checker 均通过。日志：`build/uvm/seed10_jtag_payload_fix/vcs_uvm.log` |
| 2026-08-01 | 当前工作区 | `make dut-block-unit-gate` | PASS：MDU、DMA、VIC、UART、WDT、L2NB、D-cache、mini-ROB、D-cache NB 共 9/9 | `dcache_nb` 达到块级验证，不代表已接入 CPU 或 SoC。报告目录：`build/unit_tb/dut_block_readiness` |
| 2026-08-01 | 当前工作区 | `make fabric-unit-gate` | PASS：crossbar core、QoS、multi-outstanding、DDR 共 4/4 | Fabric 单元契约未被 JTAG payload 修复破坏。报告目录：`build/unit_tb/fabric` |
| 2026-08-01 | 初始 smoke firmware | `make soc-smoke` | 进程退出成功但 log 含 `DIV ERROR`，且 error 路径仍写成功 mailbox | 该结果不计入通过。根因是 firmware 二操作数 `div` 被 assembler 展开并隐式改写操作数，同时 smoke 没有把功能错误转换为失败。 |
| 2026-08-01 | 当前工作区 | `FW_HEX=build/firmware/mdu_cpu/firmware.hex RUN_DIR=build/soc_test/mdu_cpu_div_fixed tb/soc_test/run.sh` | PASS：正数及两种混合符号 DIV 都由 CPU/MDU 返回正确商和余数 | 使用原始 `div $zero, rs, rt` 指令和失败 mailbox；证明 MDU block 与 CPU 集成正确。日志：`build/soc_test/mdu_cpu_div_fixed/sim.log` |
| 2026-08-01 | firmware SHA256 `4deaea0d6bab403dee89a64a84548cca8eeaa05f6dafbf00c880896def493bc8` | `make soc-smoke` | PASS：所有受检 MDU、ALU、branch、cache、sub-word、DMA、GPIO、quicksort 检查无错误，`REGRESSION_TEST_SUCCESS` | 默认 smoke 已改为将已标注功能错误累计并写失败 mailbox；DIV 测试覆盖正数、混合符号和当前契约定义的零除返回。日志：`build/soc_test/smoke/sim.log` |
| 2026-08-01 | firmware SHA256 `4deaea0d6bab403dee89a64a84548cca8eeaa05f6dafbf00c880896def493bc8` | `RUN_ROOT=build/uvm/phase2_complete_smoke_hardened tb/uvm_tb/run_phase2_complete.sh` | PASS：directed `16/16`、coverage `16/16`、8 个 required functional groups 均为 100%、error scan clean | clean-run 保护已生效。报告：`build/uvm/phase2_complete_smoke_hardened/phase2_completion_report.md` |
| 2026-08-01 | 同上 | `make current-contract-signoff SIGNOFF_DIR=build/signoff/functional_completeness_20260801 NUM_TESTS=10 SEED_BASE=1` | Phase 2 `16/16`，Phase 3A `8/8` 加 CPU/CP0 PASS，Phase 3B `1/1`，Phase 3C `1/1`，stress seed 1-10 全 PASS，15 个 required functional groups 均为 100%；最终 FAIL 于 coverage threshold | 功能 gate 全部通过。唯一失败是 code coverage/exclusion closure；权威报告：`build/signoff/functional_completeness_20260801/current_contract_signoff_report.md`，度量：`coverage_summary.json` |
| 2026-08-01 | `phase-c1-icache-4way@d695cb5` 独立 worktree | `vcs rtl/cache/icache.v tb/unit/icache/tb_icache.v && ./simv` | PASS：`REGRESSION_TEST_SUCCESS icache` | C1 的 4-way I-cache 达到 `BLOCK_VERIFIED`；未在 C1 基线上跑 SoC 集成回归。 |
| 2026-08-01 | `integration/function-contract@8b3dc6b` | `RUN_ROOT=build/unit_tb/integration_c1_icache tb/unit/run_dut_block_unit_gate.sh` | PASS：MDU、DMA、VIC、UART、L2、L2NB、D-cache、ROB、I-cache 共 `9/9` | C1/C2 合并后的 unit-gate 逻辑和 I-cache 测试均通过。 |
| 2026-08-01 | `integration/function-contract@8b3dc6b`，firmware SHA256 `4deaea0d6bab403dee89a64a84548cca8eeaa05f6dafbf00c880896def493bc8` | `make soc-smoke` | PASS：`REGRESSION_TEST_SUCCESS`，CPU/CP0 `intr=11 syscall=1 ri=4 adel=1 eret=16` | C1/C2 组合在 SoC smoke 下可执行。 |
| 2026-08-01 | `integration/function-contract@8b3dc6b`，同上 firmware | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/integration_c1_seed10` | PASS：`REGRESSION_TEST_SUCCESS`，无 UVM error/fatal 或 `$error` | C1/C2 组合在 background AXI stress 下通过；这不替代 I-cache 专项 SoC sequence。 |

## 10. 已知未决问题

| 优先级 | 问题 | 对计划的影响 | 处理条件 |
|---|---|---|---|
| P0 | 产品 boot、DDR 和 QSPI 不存在闭合实现：DDR 为 behavior model，QSPI/U-Boot/Linux 只有 plan；reset/exception vector 仍在 useg | SoC 无真实启动链与产品主存，不能称商用 SoC | 执行本文件 Phase 2，先冻结 boot/vector/memory contract，再分别实现与验证。 |
| P0 | `SOC_MMU_ENABLE=1` 取指死锁；`mips_soc` reset/exception vector/linker 没有 kseg0/1 迁移或 EBase policy | MMU/TLB 不能作为可用产品功能 | boot ROM/vector relocation 后，跑 mmu_refill、kernel firmware 与 exception regression。 |
| P0 | UART block 未接入产品 pins，`uart_rx` 被固定为 1、`uart_rx_int` 为 0；WDT 未映射到 peripheral subsystem | 对外 serial I/O 和 watchdog reset 无产品功能证据 | 定义产品 pinmux/pad contract，接入 UART/WDT，补 firmware/UVM/板级模型 gate。 |
| P3 | 当前 fresh VDB 执行 `refine_exclusions.py` 后，strict URG 仍报告 invalid condition/branch vector、illegal exclusion attempt 与 module checksum mismatch；合并 UVM 仅 SCORE `80.05`、COND `97.09`、TOGGLE `71.32`、FSM `53.33`、BRANCH `78.53`，product CPU/CP0 仅 SCORE `75.94`、LINE `83.84`、TOGGLE `69.05`、FSM `48.68`、BRANCH `78.33` | 当前功能行为证据有效，但 code-coverage 数字和 99% 入口均不能签收；不得提交本轮自动生成的 exclusion 文件 | 作为后续质量工作独立处理；不替代或阻塞本文件的产品功能 P0/P1。证据：`build/signoff/functional_completeness_20260801/coverage/urg.log`、`coverage_summary.json`。 |
| P2 | `dcache_nb` 与其 TB 是未提交 WIP，已通过块级 gate 但尚未接入 CPU/SoC | 只能标为 `BLOCK_VERIFIED`，不得计入当前 SoC 功能完成 | 完成 CPU 接入、hazard/forwarding 和 SoC stress 证据后再升级。 |
| P1 | crossbar 支持 cross-slave 并发，但 L2/APB/flash/DDR slave 仍限制同 slave outstanding；SPI serial boot、PIC CPU vector contract、MMU/Linux boot 均未纳入当前 RTL contract | 即使当前功能 gate 通过，也只能声明当前已文档化契约，不是商用 SoC 完整性结论 | 每项建独立 spec/RTL/firmware/UVM 变更集，并按本计划的五级状态推进。 |
| P3 | `tb/uvm_tb/cov.cfg` 仍包含 3 个不存在模块模式，VCS 每次 coverage compile 均发出 `VCM-HFUFR` warning | 不影响当前产品功能主线，但使 coverage scope 噪声和进度判读变差 | 在后续 coverage 专项中删除或更新过时 scope；再跑 coverage compile，要求该 warning 清零。 |
