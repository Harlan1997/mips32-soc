# SoC 功能完整性计划

> 版本：v1.10（2026-08-01）
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
| `integration/function-contract` | 唯一功能集成线；以 C2 `fcfc9c1` 为父线，已合入 C1 4-way I-cache、boot/memory 产品契约和 Boot ROM/CP0 向量切片 | 当前验证和后续产品功能变更只在此线收敛，暂不直接推入 `master` |
| IF/I-cache response PC alignment | `44d263a` 将 IF 请求改为 `pc`，与 I-cache hit 的上一请求响应和 IF/ID 的 `pc_plus_4` 标签不一致；修复恢复 `inst_addr=next_pc` | `BLOCK_VERIFIED`：默认 prototype 路径与产品 Boot ROM 路径均验证 reset branch、delay slot、两次写回和精确分支目标；反向改回 `pc` 时定向测试失败 |
| Boot ROM reset/vector slice | 独立 64-KB AXI S4 Boot ROM、`BFC0_0000 -> 1FC0_0000` 复位取指、产品 `BEV/ERL` 复位、`BFC0_0380` 与 `EBase+0x180` 普通异常路径已实现；`SOC_PRODUCT_BOOT_ENABLE` 默认仍为 `0` | `BLOCK_VERIFIED`，并有完整 SoC directed 证据；它不是可启动的产品 boot firmware，不能升级为 `SOC_INTEGRATED` 或产品启动完成 |
| Product TLB/MMU boot slice | `SOC_PRODUCT_BOOT_ENABLE=1` 与 `SOC_MMU_ENABLE=1` 下，CPU 保留 TLB lookup miss/invalid 的来源位；miss 选 `BFC0_0200`/`EBase`，invalid 保持 `BFC0_0380`/`EBase+0x180`；最小 Boot ROM linker、BEV refill handler、wired kseg2-APB 映射、动态 DDR refill，以及复制到 SRAM 的 EBase `Mod` handler 已新增 | 完整 SoC firmware directed 通过：I-side 覆盖两个 BEV 模式的 miss/invalid，D-side 覆盖 BEV=1 miss/invalid；两个 firmware gate 覆盖 `TLBWI`/`Wired`、DTLB refill/`ERET` retry、DDR/APB，以及 EBase `Mod` precise-state 检查、`D=1` 修复和 retry。独立 `tlb_asid_policy` gate 进一步验证 4KB ASID 隔离、Global 跨 ASID、Invalid/Modified 分类；`product-kseg0-runtime-gate` 证明 MMU 开启时 stage-1 VA `0x8000_1000` 取指映射到 PA `0x0000_1000`；另有独立 IP-based vectored interrupt gate。不含完整 kseg0 runtime、cache-error 或 kernel boot，不能标为 MMU 产品完成 |
| Development manifest handoff | Boot ROM 经实际单线 SPI XIP 读取固定 64-byte `SOC1` development manifest，CRC32 校验后把 stage-1 拷贝至 Boot SRAM 并跳转 `0x8000_1000`；MMU-enabled slice 额外确认该 kseg0 入口仍走物理 SRAM `0x0000_1000`；同时修复 SPI 读相位、MMU C=2 D-cache 属性路由和长路径镜像截断 | 完整 SoC directed gate 覆盖有效镜像，及 11 条单字段 header/CRC 失败镜像；不预加载 SRAM、不使用 `axi_flash_image_model`，并拒绝未加载的全 `FF` fixture，可由独立 Make target 和 block aggregate 重跑 | 仅为 `BLOCK_VERIFIED` 的 development boot 与 kseg0 指令交接子集。没有完整 runtime 数据映射、page-table/ASID rollover、签名、QSPI 写擦/四线、DDR handoff、boot-status/WDT 或生产 ROM artifact |
| XIP controller stall / bus error | 产品 `axi_spi_flash` 的 read AXI 通道由 `axi_read_timeout_guard` 包装，默认 512 cycles 内必须完成下游 `ARREADY` 和每个下一拍 `RVALID`；超时返回 `SLVERR`、延迟 response drain 后恢复。I-cache/D-cache 非 OKAY response 透传为 CPU IBE/DBE，Boot ROM 的 DBE/IBE handler 写 `DEAD_B007` | guard unit 覆盖 AR/R timeout、late drain、恢复和 sticky；完整产品 manifest gate 以 4-cycle guard 验证无 internal force/MISO 篡改的 DBE 到 `DEAD_B007`；I/D cache error unit 均通过 | `BLOCK_VERIFIED`：保护 AXI/controller 挂死，不可检测无 ready/error 的原始 SPI 静默 MISO；无软件可读错误寄存器、完整 cache-error vector policy 或 QSPI fault/status |
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
| CPU/CP0 | 已接入；默认 `SOC_MMU_ENABLE=0`；产品模式区分 TLB miss refill、invalid/general 与 IP-based vectored interrupt 的 BEV/EBase 向量 | smoke 与 Phase 3A/3B CPU/CP0 gate 通过；CP0 timer/TLB 单测验证 `IV/VS`；产品 directed 覆盖 I-side BEV=1/0 miss/invalid、D-side BEV=1 miss/invalid、EBase `Mod` precise state/recovery，以及软件 `IP1` 到 `EBase+0x220` | refill/invalid、最小 kernel-mode `Mod` recovery 与 IP-based vectored interrupt 子集已验证；cache-error、完整 Modified policy、外部 EIC/VEIC、ISA reference/compliance 和 MMU 产品启动仍未闭合 |
| L1 cache | 阻塞式 D-cache 在 DUT；4-way I-cache 已合入 `integration/function-contract` | D-cache unit、`cache_sweep` 与 smoke 通过；IF/I-cache response-PC 的默认和 Boot ROM reset-branch directed tests、合入后 unit gate `10/10`、SoC smoke 和 seed 10 UVM stress 通过 | I-cache 具备当前集成基线的 block/通用 SoC 证据；本次只关闭 response-PC 对齐的 reset/branch 子项，refill/eviction/reset 专项 SoC 测试仍不足，不能标为 `CONTRACT_CLOSED` |
| L2 cache | 默认 write-through L2 已接入；write-back 为 opt-in | L2 unit、L2 firmware、Phase 2/3 与 smoke 通过 | 当前 blocking L2 契约可用；不具备 coherency/ECC/生产性能闭合 |
| AXI fabric | C3 crossbar 已在 `master`；DDR 是 S3 slave | fabric unit `4/4`，Phase 2/3、10-seed stress 通过 | cross-slave 并发已验证；同一 slave 仍受单 outstanding slave 限制 |
| DMA | 已接入 APB/AXI | DMA unit、DMA firmware、DMA copy/IRQ UVM 通过；grant stability 修复已在 C2 集成父线 | 当前 direct-copy/IRQ 契约有证据；不可宣称 IOMMU/coherency 或完整系统 DMA 生态 |
| VIC/interrupt | 已接入 CPU 单 IRQ 线，源为 UART/TIMER/DMA；CPU 侧支持按 `Cause.IP` 的 `Cause.IV/IntCtl.VS` 向量，`Config3.VEIC=0` | VIC unit、VIC firmware、PIC mask UVM 与 IP1 vectored-interrupt SoC gate 通过 | mask/active 与 CPU IP-based vector 已验证；外部 EIC/VEIC vector ID、嵌套/优先级跨 VIC-CPU 合同和 UART RX source 当前不可用 |
| UART | `apb_uart_16550` 已接入 APB；`soc_top` 已暴露 UART TX/RX、RTS/CTS、DTR/DSR、DCD/RI pins；PIC bit0 为 RX-specific IRQ，bit1 保留历史 aggregate IRQ 语义；legacy/UVM 配置仍可关闭 pin wiring | UART unit、UART CPU loopback gate 和 block aggregate `10/10` 通过；unit 已分别检查 RX/TX IRQ；尚无真实外部 RX waveform、pad-mux 或板级 gate | RTL pin/IRQ wiring 已实现，但产品 pad binding、外部线路/电气约束、板级驱动和 RX 外部流量仍未闭合 |
| DDR | S3 使用 `axi_ddr_behavioral` 容量占位模型 | `xbar_ddr` unit 通过 | 无 DDR controller/PHY/校准/refresh/DDR boot，属于 P0 blocker |
| Flash/boot | `axi_spi_flash` 支持简单 SPI read XIP；独立只读 Boot ROM 已作为 S4 接入产品配置。产品 XIP read 以默认 512-cycle AXI guard 限时，非 OKAY response 经 cache/CPU 转 IBE/DBE；开发 Boot ROM 可经产品 SPI 引脚读取 manifest/payload、CRC 校验、拷贝 Boot SRAM 并转交 kseg0 stage 1 | Boot ROM burst/read-error/write-reject、无 SRAM preload 的首笔复位取指、response-PC 对齐的 reset branch、普通异常、TLB refill/invalid product directed tests、AXI timeout guard、I/D cache error unit，以及有效、11 条 header/CRC failure 和 timeout-to-DBE manifest handoff 均通过；生产 `axi_spi_flash` 的 pin-level `0x03`/24-bit address、连续读和写 `SLVERR` unit gate 通过 | 真实单线 XIP 具备 development reset-to-handoff、字段拒绝和 controller/AXI stall failure evidence；无 production ROM/signature、原始 SPI 无响应检测、QSPI command/FIFO/erase/program/四线、软件错误状态、DDR init 或 U-Boot boot，仍为 P0 blocker |
| MMU/TLB | RTL 与 unit TB 存在，默认关闭；产品 opt-in 具备 refill/invalid vector routing、最小 Boot ROM kseg1 linker、BEV refill handler、wired kseg2-APB map，以及复制到 SRAM 的 EBase `Mod` handler | MMU/CP0 unit、`make tlb-asid-policy-gate`、完整 SoC I/D vector directed、`make product-mmu-boot-gate` 和 `make product-mmu-ebase-modified-gate` 通过；ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified；后者覆盖 DTLB `Mod`、CP0 precise state、EBase handler relocation、`D` bit repair 和 `ERET` retry；IP-based vectored interrupt 有独立 SoC gate | 最小 BEV 启动、4KB ASID/异常分类、单一 EBase `Mod` recovery 与 CPU vector table 已有证据；完整 kseg0 runtime、page-table/ASID rollover、cache-error policy、kernel/OS boot 仍未闭合 |
| WDT/clock/reset | `apb_wdt` 已映射到 APB `0x4000_7000`；到期产生一次性 `wdt_reset`，`mips_soc_impl` 以 `soc_rst_n = rst_n & ~wdt_reset` 复位 SoC；WDT 与 boot-status 均留在 always-on 域 | WDT unit、boot-status unit、外设子系统 AXI/APB retention gate、默认 SoC smoke、预加载 firmware retention 和无 SRAM preload 的 Boot ROM WDT failure gate 均通过；gate 验证 wired APB map、stage/failure、POR|WDT cause 和第二次 Boot ROM 入口 | APB/reset、stage/failure retention 和软件/Boot ROM reset path 已有证据；由 manifest/QSPI/DDR 真实故障触发的失败分类、板级 reset 观测和量产 ROM 仍未闭合 |
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

- 已建立 `docs/boot_memory_contract.md` v1.4，冻结候选 reset/vector、物理/虚拟地址图、镜像格式、失败行为和六个行为 gate。
- 第二至第十一个 RTL/firmware 垂直切片已完成：TLB lookup miss 与 matching-invalid 的 vector 分派覆盖 I-side 两个 BEV 模式和 D-side BEV=1；最小产品 Boot ROM linker/BEV refill handler 进一步覆盖 wired kseg2-APB 映射、DTLB refill、`TLBWR`、寄存器恢复、`ERET` retry、DDR store/load 和 APB write；独立 ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、Invalid/Modified 分类；独立 gate 还证明 Boot ROM 把通用 handler 复制到 SRAM `EBase+0x180`，处理 precise `Mod`、将 `D=0` 改为 `D=1` 并 `ERET` retry；IP-based `Cause.IV/IntCtl.VS` vectored interrupt gate 已证明 IP1 到 `EBase+0x220`；development manifest gate 则经实际 SPI XIP 完成 CRC 校验、Boot SRAM 拷贝和 kseg0 stage-1 handoff，`product-kseg0-runtime-gate` 在 `SOC_MMU_ENABLE=1` 下确认入口 VA 到 SRAM PA 的取指转换；XIP guard 则将下游 AR/R stall 限时为 `SLVERR`，经 cache/CPU DBE 路径由 Boot ROM 记录 `DEAD_B007`；UART pins/IRQ slice、WDT APB/reset path、boot-status retention、预加载 firmware reset-retention 和无 SRAM preload 的 Boot ROM WDT failure slice 已有独立 gate。仍只关闭向量路由、最小 BEV 启动链、4KB ASID/异常分类、单一 `Mod` recovery、development handoff、kseg0 指令交接、AXI-side XIP stall、manifest/DDR 故障到 failure code 的完整分类、完整 kseg0 runtime 数据路径、cache-error/EIC 异常、生产 QSPI 和真实 DDR。
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

- `SOC_MMU_ENABLE=1`：最小 Boot ROM kseg1 linker、BEV refill handler、wired mapping、4KB ASID/Global/Invalid/Modified policy gate、EBase `Mod` handler relocation/retry gate，以及 stage-1 kseg0 指令交接 gate 已通过；继续完成完整 kseg0 runtime 数据路径、page-table/ASID rollover、cache-error/EIC 和 kernel-mode firmware gate。refill/invalid 的 EBase/BEV 向量路由及 IP-based vectored interrupt 已有 directed 证据。
- CPU/CP0：补 MIPS ISA compliance 与 reference-model lockstep；现有 exception smoke 只作为子集证据。
- 外设：为已接入的 UART TX/RX/flow-control 完成 pad-mux、外部 RX waveform 和板级 gate；为 WDT 补无预加载 Boot ROM failure firmware、自动重启和板级 reset 观测；补齐 GPIO/timer 产品软件驱动。
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

历史 full signoff 的功能阶段均通过，coverage 阈值单独失败，保留为后续质量工作。**Phase 0 的 C1/C2 分支整理、Phase 2 boot/memory 架构冻结、Boot ROM 复位/普通向量、TLB refill/invalid 的 BEV-EBase 路由、最小 Boot ROM kseg1 linker/BEV refill/wired mapping、复制到 SRAM 的 EBase `Mod` recovery、4KB ASID/Global/Invalid/Modified policy、IP-based `Cause.IV/IntCtl.VS` vectored interrupt、经实际 SPI XIP 的 development manifest/CRC-to-kseg0-SRAM handoff 和 header/CRC rejection matrix，以及 XIP controller/AXI stall 到 CPU DBE/`DEAD_B007` 失败行为均已完成。当前下一项是完整 kseg0 runtime linker、page-table/ASID rollover、cache-error/EIC policy；仍不是 coverage closure。**

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
| 2026-08-01 | `integration/function-contract@3157091` | boot/memory architecture review: RTL reset/vector/MMU path, address map, linker, DDR/QSPI/WDT integration and existing block specs | COMPLETE（架构 gate，非 RTL 测试） | `docs/boot_memory_contract.md` v0.1 冻结候选产品地址图、MIPS reset/vector policy、flash manifest、失败行为和 6 个行为 gate；当前未形成任何 product boot RTL 完成声明。 |
| 2026-08-01 | `integration/function-contract@44d263a` Boot ROM reset/map slice | `RUN_DIR=build/unit_tb/product_reset_fetch_final3 tb/unit/bootrom/run_product_reset_fetch.sh` | PASS：`REGRESSION_TEST_SUCCESS product_reset_fetch` | 以 `SOC_PRODUCT_BOOT_ENABLE=1` 编译顶层；复位 PC 为 `0xBFC0_0000`，首笔 I-cache AR 为 `0x1FC0_0000`，并握手至 S4 Boot ROM。该测试不预加载 SRAM，不执行 ROM 镜像。 |
| 2026-08-01 | 同上 | `make soc-smoke` | PASS：进程退出码 `0` | 默认 `SOC_PRODUCT_BOOT_ENABLE=0` 的 SRAM-preload smoke 在 IF 取址修正后无功能回归；URG exclusion 告警属于暂缓的 coverage 维护。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/bootrom_final2 tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 新增 Boot ROM burst/read-error/write-reject unit test 和产品复位路径 test；原有九个块级测试均通过。 |
| 2026-08-01 | `integration/function-contract` Boot ROM/CP0 vector slice | `RUN_DIR=build/unit_tb/product_boot_vector_ebase tb/unit/bootrom/run_product_boot_vector.sh` | PASS：`REGRESSION_TEST_SUCCESS product_boot_vector` | ROM `syscall` 先进入 `BFC0_0380`；bootstrap 指令清除 `BEV/ERL` 后第二次异常进入 `EBase+0x180`，并验证 `0x8000_0180 -> 0x0000_0180` S0 路由。 |
| 2026-08-01 | 同上 | `tb/unit/cp0/run.sh` | PASS：`cp0_timer: PASS` | 增加 `bev_out` 接口连接后，既有 CP0 timer/TLB 单元回归通过。 |
| 2026-08-01 | `integration/function-contract` TLB vector slice | `RUN_DIR=build/unit_tb/product_tlb_vectors_try4 tb/unit/bootrom/run_product_tlb_vectors.sh` | PASS：`REGRESSION_TEST_SUCCESS product_tlb_vectors` | 以 `SOC_PRODUCT_BOOT_ENABLE=1`、`SOC_MMU_ENABLE=1` 编译完整 SoC；I-TLB `hit=0` 的 miss 分别到 `BFC0_0200`/`EBase`，matching `hit=1,V=0` 的 invalid 分别到 `BFC0_0380`/`EBase+0x180`。 |
| 2026-08-01 | 同上 | `RUN_DIR=build/unit_tb/product_tlb_data_vectors_try1 tb/unit/bootrom/run_product_tlb_data_vectors.sh` | PASS：`REGRESSION_TEST_SUCCESS product_tlb_data_vectors` | MEM-side useg load 的 DTLB miss 到 `BFC0_0200`，matching invalid 到 `BFC0_0380`；证明 data path 未只依赖 `ExcCode=TLBL`。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/tlb_vector_final tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 既有 10 个 block 类别和新增两条 product TLB vector directed tests 均通过，ROB sideband parity test 也通过。 |
| 2026-08-01 | `cba3a08` 与 TLB vector slice 对照 | `make soc-smoke SOC_TEST_RUN_DIR=...` | 两个基线均为 testbench timeout，未产生 `REGRESSION_TEST_SUCCESS` | 该历史结论已被后续 fetch-path 审计取代：timeout 不是 TLB sideband 根因，见下一条。 |
| 2026-08-01 | `integration/function-contract` product MMU boot slice | `make product-mmu-boot-gate PRODUCT_MMU_BOOT_DIR=build/unit_tb/product_mmu_boot_final3` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_boot` | 从 `BFC0_0000` Boot ROM firmware 启动，安装 wired kseg2-APB TLB 项，DTLB miss 到 `BFC0_0200`，`TLBWR` 后保留被中断寄存器并以 `ERET` 重试，DDR store/load、APB write 和 `0xA000_FFFC` mailbox 请求完成。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/product_mmu_boot_aggregate_final tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 新增产品 MMU firmware 子测已进入 Boot ROM 类别；其余九个功能类别未回归。 |
| 2026-08-01 | `integration/function-contract` EBase/Modified slice | `make product-mmu-ebase-modified-gate PRODUCT_MMU_EBASE_MODIFIED_DIR=build/unit_tb/product_mmu_ebase_modified_try3` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_ebase_modified` | Boot ROM 将 handler 拷贝到 SRAM `0x180`，清 `BEV/ERL` 后 valid `D=0` useg store 以 `Cause=Mod` 进入 `0x8000_0180`；handler 校验 precise `Cause`/`BadVAddr`/`EPC`，重写 entry 的 `D=1` 并 `ERET` retry，store/load 后写成功 mailbox。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/product_mmu_ebase_modified_aggregate tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 新 EBase/Modified firmware gate 已加入 Boot ROM 类别；九个既有功能类别以及其余 Boot ROM 产品路径均通过。 |
| 2026-08-01 | `integration/function-contract` SPI XIP slice | `make spi-flash-unit-gate SPI_FLASH_UNIT_DIR=build/unit_tb/axi_spi_flash_final` | PASS：`REGRESSION_TEST_SUCCESS axi_spi_flash` | 针对产品 `axi_spi_flash`（非 loadable verification model）验证 `0x03` + 24-bit address、两拍连续 serial read、AXI response ID/`RLAST` 和只读窗口写 `SLVERR`。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/axi_spi_flash_aggregate tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | SPI XIP unit gate 已进入第 10 类 Boot ROM/flash 聚合门禁；其余九类既有块级测试和全部 Boot ROM/MMU 产品路径均通过。 |
| 2026-08-01 | `integration/function-contract` development manifest handoff slice | `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_handoff_final` | PASS：`REGRESSION_TEST_SUCCESS product_manifest_handoff_valid` 与 `product_manifest_handoff_bad_crc` | 有效镜像在无 SRAM preload、无 `axi_flash_image_model` 下经实际 SPI pins 完成 manifest/payload `0x03` 读、CRC32、Boot SRAM 拷贝、`BEV/ERL` 清除和 kseg0 stage-1 handoff；bad-CRC 只到失败 mailbox。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/product_manifest_handoff_aggregate tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 新 handoff 的有效/CRC-failure 两路径已纳入 Boot ROM/flash 聚合类别，既有九类 block contract 未回归。 |
| 2026-08-01 | 同上，firmware SHA256 `4deaea0d6bab403dee89a64a84548cca8eeaa05f6dafbf00c880896def493bc8` | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/manifest_handoff_postchange` | PASS：`REGRESSION_TEST_SUCCESS`，CPU/CP0 `intr=11 syscall=1 ri=4 adel=1 eret=16` | CPU-to-D-cache 新增的 MMU C=2 uncached 属性接口未使默认 prototype smoke 回归；生成 coverage report 时的 exclusion 警告仍按 P3 跟踪，不能被解释为 coverage signoff。 |
| 2026-08-01 | `integration/function-contract` manifest rejection matrix | `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_negative_path_buffer_final2` | PASS：有效镜像与 11 个 `REGRESSION_TEST_SUCCESS product_manifest_handoff_*` 拒绝标记 | 每个镜像只损坏一个字段，分别验证 magic、version、header length、payload offset、三种 payload length、load/entry address、flags 和 CRC 都会写失败 mailbox，且不进入 handoff/stage 1。此前 128-character image-plusarg 截断会使 aggregate 负向路径落入全 `FF` 初值；缓冲扩展为 512 characters 并加入 fixture-load guard 后，长路径 run 不再有 testbench `$readmemh` 打开失败。 |
| 2026-08-01 | 同上 | `RUN_ROOT=build/unit_tb/product_manifest_negative_path_buffer_aggregate_final2 tb/unit/run_dut_block_unit_gate.sh` | PASS：`10/10` | 修复后的 rejection matrix 由第 10 类 Boot ROM/flash 聚合门禁调用，且以超过旧 128-character 限制的镜像路径运行；其余 block 类别未回归。 |
| 2026-08-01 | `integration/function-contract` XIP timeout/DBE slice | `make xip-read-timeout-unit-gate XIP_READ_TIMEOUT_UNIT_DIR=build/unit_tb/axi_read_timeout_guard_dev1` | PASS：`REGRESSION_TEST_SUCCESS axi_read_timeout_guard` | 4-cycle directed guard 覆盖 downstream `ARREADY` timeout、`RVALID` timeout、晚到 response drain、后续 read 恢复和 sticky timeout。产品默认值为 512 cycles。 |
| 2026-08-01 | 同上 | `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_xip_timeout_final` | PASS：有效镜像、11 条 manifest rejection 与 `REGRESSION_TEST_SUCCESS product_manifest_handoff_xip_timeout` | 无修改 SPI responder、无 force；把 production guard 降至 4 cycles 后，Boot ROM XIP read 的 `SLVERR` 经 D-cache/CPU 变为 DBE，general handler 写 `DEAD_B007`，不进入 handoff。 |
| 2026-08-01 | 同上 | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/xip_timeout_smoke_final` | PASS：`REGRESSION_TEST_SUCCESS`，CPU/CP0 `intr=11 syscall=1 ri=4 adel=1 eret=16` | 修复 smoke 在兼容身份映射下误用 `0xB000_0000` kseg1 flash alias，改从 fabric-visible `0x1000_0000` XIP window 读取；此前每轮的正确 DECERR/DBE 不再被误报为异常。 |
| 2026-08-01 | 同上 | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/xip_timeout_aggregate_final` | PASS：`10/10` | guard、XIP timeout manifest handoff、I/D cache error 回归及九类既有 block contract 均通过。 |
| 2026-08-01 | `integration/function-contract` vectored-interrupt slice | `tb/unit/cp0/run.sh`、`make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/product_vectored_interrupt_try4` | PASS：`cp0_timer: PASS`、`REGRESSION_TEST_SUCCESS product_vectored_interrupt` | CP0 验证 `Cause.IV`/`IntCtl.VS`、最高 enabled pending IP7、`VS=1` 的 `0x2E0` 和最大 `VS=31` 的 `0x1D20` 偏移；完整产品 SoC 仅加载 Boot ROM、无 SRAM preload，以软件 IP1、`VS=1`、`BEV=0` 进入 `0x8000_0220`，并观察物理 `0x0000_0220` 取指及 `EXL/INT` 状态。 |
| 2026-08-01 | 同上 | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/vectored_interrupt_aggregate_final`、`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/vectored_interrupt_smoke` | PASS：block aggregate、`REGRESSION_TEST_SUCCESS` | 新 CP0/vector 接口未回归 MDU、DMA、VIC、UART、WDT、L2/L2NB、L1 cache、ROB、SPI/XIP、Boot ROM/MMU；smoke `CPU_CP0_SUMMARY intr=11 syscall=1 ri=4 adel=1 eret=16`。smoke 中的 `RI=0xA` 输出来自显式非法指令/嵌套异常 stimulus。 |
| 2026-08-01 | `integration/function-contract@c7018b7` | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit/tlb_asid_policy_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/tlb_asid_aggregate` | PASS：独立 gate `REGRESSION_TEST_SUCCESS tlb_asid_policy`，8 项检查通过；Boot ROM/MMU 聚合 `10/10` | 以 `SOC_MMU_ENABLE=1` 直接连接 `mips_tlb`/`mips_mmu`；证明 4KB 非 Global ASID 隔离、奇偶页选择、Global 跨 ASID，以及 matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified 分类。未覆盖可变页、multi-hit、micro-TLB 或 OS 级 ASID rollover。 |
| 2026-08-01 | `integration/function-contract` UART pin/IRQ slice | `make uart-cpu-gate SOC_TEST_UART_CPU_DIR=build/soc_test/uart_pins_gate_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/uart_pins_aggregate` | PASS：UART CPU firmware gate；UART unit 检查 RX/TX IRQ 分离；DUT block aggregate `10/10` | `soc_top` 产品 wrapper 接出 UART/modem pins；PIC bit0 连接 RX-specific IRQ，bit1 保持历史 aggregate IRQ，`ENABLE_UART_PINS=0` 的 legacy/UVM tie-off 行为未改变。仍缺外部 RX waveform、pad-mux 和板级 gate。 |
| 2026-08-01 | `integration/function-contract` WDT APB/reset slice | `make wdt-unit-gate WDT_UNIT_DIR=build/unit_tb/wdt_try2`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_try1`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/wdt_compile_smoke` | PASS：`REGRESSION_TEST_SUCCESS wdt`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、默认 SoC smoke | WDT 已在 `0x4000_7000` 解码；外设 gate 通过 AXI/APB 写 LOAD/CTRL，观察一次性 reset pulse 拉低 aggregate reset 并在 reset 后读到 sticky STATUS。尚未验证 Boot ROM failure code/boot-status persistence。 |
| 2026-08-01 | `integration/function-contract` boot-status retention slice | `make boot-status-unit-gate`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_boot_status`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/boot_status_smoke` | PASS：`REGRESSION_TEST_SUCCESS boot_status`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、`REGRESSION_TEST_SUCCESS` | `0x4000_8000` 解码为 always-on APB block；`BOOT_STAGE`/`FAILURE` 在 WDT reset 后保持，`RESET_CAUSE[POR/WDT]` sticky 且 W1C。该 gate 只证明寄存器和 reset retention，不代表 Boot ROM failure firmware 已闭合。 |
| 2026-08-01 | `integration/function-contract` WDT boot-failure firmware slice | `make wdt-boot-failure-gate` | PASS：`wdt_boot_failure: REGRESSION_TEST_SUCCESS`、SoC mailbox `REGRESSION_TEST_SUCCESS` | 预加载 firmware 首次写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070001` 后 arm WDT；第二次入口读回 stage/failure 与 `POR|WDT` cause，清除状态后完成。该证据覆盖软件触发 reset/retention，不满足无 SRAM preload 的产品 boot gate。 |
| 2026-08-01 | `integration/function-contract` product WDT Boot ROM failure slice | `make product-wdt-boot-failure-gate PRODUCT_WDT_BOOT_FAILURE_DIR=build/unit_tb/product_wdt_boot_failure_try6` | PASS：`REGRESSION_TEST_SUCCESS product_wdt_boot_failure` | 不调用 `preload_sram_hex`；Boot ROM 在 `SOC_MMU_ENABLE=1` 下安装 5 个 wired APB TLB entries，写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070002`、arm WDT，第二次 `BFC0_0000` 入口校验 `POR|WDT` 与保留字段后写成功 mailbox。该 gate 证明 reset/retention 软件路径，不覆盖 manifest/QSPI/DDR 故障分类。 |

## 10. 已知未决问题

| 优先级 | 问题 | 对计划的影响 | 处理条件 |
|---|---|---|---|
| P0 | 产品 boot、DDR 和 QSPI 尚未闭合：Boot ROM 复位、普通与 refill/invalid BEV-EBase vector、IP-based vectored interrupt、最小 BEV MMU firmware、单一 EBase `Mod` recovery、development manifest header/CRC-to-SRAM handoff，以及 controller/AXI stall-to-DBE 已通过；生产 ROM/signature、原始 SPI 无响应检测、cache-error/EIC policy、QSPI/U-Boot/Linux、DDR controller/PHY 仍未实现 | SoC 已有受限的 reset-to-development-stage-1 和 XIP transport-stall failure evidence，但无可发布的 secure boot 或产品主存，不能称商用 SoC | 在本文件 Phase 2 继续实现完整 runtime exception/cache-error policy、QSPI、DDR、boot-status/WDT 与 production handoff，并分别验证。 |
| P0 | 最小 Boot ROM kseg1 linker、BEV refill handler、wired mapping、4KB ASID/Global/Invalid/Modified gate、SRAM EBase `Mod` recovery 和 IP-based vectored interrupt 已通过，但产品主 runtime 尚未迁移到 kseg0；page-table/ASID rollover、cache-error/EIC policy 和 kernel firmware 未验收；历史 prototype smoke timeout 的 fetch-path 根因已修复 | MMU/TLB 有最小启动、4KB ASID/异常分类、`Mod` recovery 和 CPU vector table 证据，但不能作为可启动的产品 OS 功能 | 建立完整 kseg0 runtime linker、page-table/ASID rollover、exception policy 和 kernel firmware gate，再跑 exception regression。 |
| P0 | UART RTL pins/IRQ wiring 已接入 `soc_top`，但 pad-mux/板级电气绑定、真实外部 RX waveform 和 RX firmware 仍未验收；WDT APB/reset pulse、boot-status retention、预加载 firmware retention 和无 SRAM preload Boot ROM failure slice 已通过 | 对外 serial I/O 仍缺板级证据；WDT gate 只证明 deliberate Boot ROM failure/reset，不证明 manifest/QSPI/DDR 真实故障分类、量产 ROM 和板级 reset 观测 | 固化 UART pad contract 并补外部 RX gate；把真实 manifest/controller/DDR failure 映射到 failure code，并增加板级 watchdog/reset 观测。 |
| P3 | 当前 fresh VDB 执行 `refine_exclusions.py` 后，strict URG 仍报告 invalid condition/branch vector、illegal exclusion attempt 与 module checksum mismatch；合并 UVM 仅 SCORE `80.05`、COND `97.09`、TOGGLE `71.32`、FSM `53.33`、BRANCH `78.53`，product CPU/CP0 仅 SCORE `75.94`、LINE `83.84`、TOGGLE `69.05`、FSM `48.68`、BRANCH `78.33` | 当前功能行为证据有效，但 code-coverage 数字和 99% 入口均不能签收；不得提交本轮自动生成的 exclusion 文件 | 作为后续质量工作独立处理；不替代或阻塞本文件的产品功能 P0/P1。证据：`build/signoff/functional_completeness_20260801/coverage/urg.log`、`coverage_summary.json`。 |
| P2 | `dcache_nb` 与其 TB 是未提交 WIP，已通过块级 gate 但尚未接入 CPU/SoC | 只能标为 `BLOCK_VERIFIED`，不得计入当前 SoC 功能完成 | 完成 CPU 接入、hazard/forwarding 和 SoC stress 证据后再升级。 |
| P1 | crossbar 支持 cross-slave 并发，但 L2/APB/flash/DDR slave 仍限制同 slave outstanding；SPI serial boot、cache-error/EIC/VEIC policy、MMU/Linux boot 均未纳入当前 RTL contract | 即使当前功能 gate 通过，也只能声明当前已文档化契约，不是商用 SoC 完整性结论 | 每项建独立 spec/RTL/firmware/UVM 变更集，并按本计划的五级状态推进。 |
| P3 | `tb/uvm_tb/cov.cfg` 仍包含 3 个不存在模块模式，VCS 每次 coverage compile 均发出 `VCM-HFUFR` warning | 不影响当前产品功能主线，但使 coverage scope 噪声和进度判读变差 | 在后续 coverage 专项中删除或更新过时 scope；再跑 coverage compile，要求该 warning 清零。 |
