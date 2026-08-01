# SoC 功能完整性计划

> 版本：v1.25（2026-08-02）
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

## 1A. 当前交付边界：RTL 前端

本阶段的明确目标是 **RTL 功能编写、前端编译/elaboration 和功能仿真**，暂不进入综合阶段。
当前交付等级使用以下两个 gate：

1. `RTL_FRONTEND_COMPILE_READY`：目标 RTL、接口、参数和仿真模型可重复编译并完成 elaboration。
2. `RTL_FUNCTIONAL_SIM_READY`：块级和 SoC behavioral simulation 覆盖正常、复位、背压、错误和软件驱动路径。

本阶段包含：

- 可综合 RTL 的功能实现和接口契约；
- vendor-neutral DDR4 controller/PHY behavioral model；
- unit test、firmware test、SoC/UVM behavioral simulation；
- reset、timeout、backpressure、非法输入和错误响应验证；
- 每项功能的 commit、测试命令、日志和残余风险登记。

本阶段不包含，也不作为当前 gate 的前置条件：

- TSMC PDK、DDR IO library、真实 Synopsys PHY license；
- 精确 DRAM ordering code、package parasitic、PCB SI/PI/timing 文件；
- lint、CDC/RDC、formal、综合、STA、PPA、gate-level simulation 和 tapeout signoff。

如果 RTL 还没有接入真实 vendor PHY，则 `DDR4-IN-01..08` 保持产品入口阻塞状态，
但不阻塞上述两个 RTL 前端 gate。真实 PHY wrapper 接入时才需要供应商的精确 DFI port list、
ratio、model 和约束。

## 2. 当前基线快照

| 对象 | 状态 | 处理 |
|---|---|---|
| `master@6ecbbbc` | 当前产品基线，已包含 C3 crossbar 和 Phase 4 商用模块历史 | 作为集成基线 |
| `integration/function-contract` | 唯一功能集成线；以 C2 `fcfc9c1` 为父线，已合入 C1 4-way I-cache、boot/memory 产品契约和 Boot ROM/CP0 向量切片 | 当前验证和后续产品功能变更只在此线收敛，暂不直接推入 `master` |
| IF/I-cache response PC alignment | `44d263a` 将 IF 请求改为 `pc`，与 I-cache hit 的上一请求响应和 IF/ID 的 `pc_plus_4` 标签不一致；修复恢复 `inst_addr=next_pc` | `BLOCK_VERIFIED`：默认 prototype 路径与产品 Boot ROM 路径均验证 reset branch、delay slot、两次写回和精确分支目标；反向改回 `pc` 时定向测试失败 |
| Boot ROM reset/vector slice | 独立 64-KB AXI S4 Boot ROM、`BFC0_0000 -> 1FC0_0000` 复位取指、产品 `BEV/ERL` 复位、`BFC0_0380` 与 `EBase+0x180` 普通异常路径已实现；`SOC_PRODUCT_BOOT_ENABLE` 默认仍为 `0` | `BLOCK_VERIFIED`，并有完整 SoC directed 证据；它不是可启动的产品 boot firmware，不能升级为 `SOC_INTEGRATED` 或产品启动完成 |
| Product TLB/MMU boot slice | `SOC_PRODUCT_BOOT_ENABLE=1` 与 `SOC_MMU_ENABLE=1` 下，CPU 保留 TLB lookup miss/invalid 的来源位；miss 选 `BFC0_0200`/`EBase`，invalid 保持 `BFC0_0380`/`EBase+0x180`；最小 Boot ROM linker、BEV refill handler、wired kseg2-APB 映射、动态 DDR refill，以及复制到 SRAM 的 EBase `Mod` handler 已新增 | 完整 SoC firmware directed 通过：I-side 覆盖两个 BEV 模式的 miss/invalid，D-side 覆盖 BEV=1 miss/invalid；两个 firmware gate 覆盖 `TLBWI`/`Wired`、DTLB refill/`ERET` retry、DDR/APB，以及 EBase `Mod` precise-state 检查、`D=1` 修复和 retry。独立 `tlb_asid_policy` gate 进一步验证 4KB ASID 隔离、Global 跨 ASID、Invalid/Modified 分类；`product-kseg0-runtime-gate` 证明 MMU 开启时 stage-1 VA `0x8000_1000` 取指映射到 PA `0x0000_1000`；另有独立 IP-based vectored interrupt gate。不含完整 kseg0 runtime、cache-error 或 kernel boot，不能标为 MMU 产品完成 |
| Development manifest handoff | Boot ROM 经实际单线 SPI XIP 读取固定 64-byte `SOC1` development manifest，CRC32 校验后把 stage-1 拷贝至 Boot SRAM 并跳转 `0x8000_1000`；MMU-enabled slice 额外确认 kseg0 入口取指 `0x8000_1000 -> 0x0000_1000`，stage-1 在 `0x8000_7000/0x8000_7004` 写入并读回数据，分别映射到 `0x0000_7000/0x0000_7004`；同时修复 SPI 读相位、MMU C=2 D-cache 属性路由和长路径镜像截断 | 完整 SoC directed gate 覆盖有效镜像，及 11 条单字段 header/CRC 失败镜像；不预加载 SRAM、不使用 `axi_flash_image_model`，并拒绝未加载的全 `FF` fixture，可由独立 Make target 和 block aggregate 重跑 | 仍为 `BLOCK_VERIFIED` 的 development boot 与有限 kseg0 runtime data-path 子集。没有完整 runtime 数据布局、SoC page-table allocator/shootdown/ASID 压力、签名、QSPI 写擦/四线、DDR handoff、boot-status/WDT 或生产 ROM artifact |
| XIP controller stall / bus error | 产品 `axi_spi_flash` 的 read AXI 通道由 `axi_read_timeout_guard` 包装，默认 512 cycles 内必须完成下游 `ARREADY` 和每个下一拍 `RVALID`；超时返回 `SLVERR`、延迟 response drain 后恢复。uncached response 透传为 IBE/DBE；cached refill/writeback 通过独立 sideband 透传为 CacheErr (ExcCode=30)；Boot ROM 当前仍记录 DBE/IBE `DEAD_B007`；APB `0x4000_5000` 提供版本、controller-present、timeout sticky 和最后错误码，并支持 W1C | guard unit 覆盖 AR/R timeout、late drain、恢复和 sticky；qspi status integration gate 覆盖 guard-to-APB decode、错误分类和 W1C；完整产品 manifest gate 以 4-cycle guard 验证无 internal force/MISO 篡改的 DBE 到 `DEAD_B007`；I/D cache error unit 与 CPU CacheErr/ERL directed gate 均通过 | `SOC_INTEGRATED` 的故障观测切片：保护 AXI/controller 挂死并提供软件可读状态；CPU CacheErr vector/ERL/ErrorEPC 已具备 RTL 证据，但生产 handler/recovery、原始 SPI 静默 MISO 检测、QSPI command/FIFO/erase/program/四线仍未实现 |
| `phase-c2-l2-nonblocking@fcfc9c1` | 比 `master` 多 7 个提交；含已独立提交的 JTAG、firmware、gate 与本计划修复 | 已是集成线父线；L2-NB、ROB、DDR placeholder 的产品状态仍须分项判断 |
| `phase-c1-icache-4way@d695cb5` | 已由 merge commit `8b3dc6b` 合入集成线 | 保留为历史分支，不再重复 merge |
| `phase-c3-axi-crossbar`、`phase4-dut-block-commercial-closure` | 已为 `master` 祖先 | 只保留历史引用，禁止重复合并 |
| D-cache NB WIP：`feature/dcache-nb-stage3@fcfc9c1` | 未跟踪 `rtl/cache/dcache_nb.v`、`tb/unit/dcache/tb_dcache_nb.v`，以及相关 spec/gate 修改 | 已有唯一 feature 分支，但仍仅为 `BLOCK_VERIFIED`；未接入 CPU/SoC，不能计入 SoC 功能完成 |
| 本轮功能修复/验证改动 | JTAG `7f74345`、firmware `1288681`、gate 隔离 `324d663`、原始计划 `fcfc9c1` 已分别提交 | 已进入集成线父线；不得与 D-cache NB WIP 混合提交 |
| Coverage 生成工件 | `product_exclusions.el`、`uvm_exclusions.el` 和 `exclusion_manifest.json` 已由 fresh VDB 重生成但 strict URG 仍报 invalid object/checksum mismatch | 保留作 P3 调查输入；在告警清零和人工审计前不得提交或作为 coverage signoff 依据 |
| `stash@{0}` | C3 遗留 WIP，含旧 fabric/coverage 变更 | 审计后 apply 或归档，禁止盲删 |
| 最新 full signoff | `build/signoff/functional_completeness_20260801` 已完成所有 5 个功能阶段；只在 99% code-coverage threshold 失败 | 功能结果可用于当前 RTL contract 证据；coverage closure 保留为 P3，不能发布 `CONTRACT_CLOSED` |

### ASIC 目标与 DDR 输入状态

当前产品路线已确定为 **ASIC Profile C1 DDR4**。这只关闭了工艺档位和内存
代际选择，没有关闭实现输入：
工艺节点、foundry/PDK、封装和 IO 电压、PHY/IP 供应商与 license、精确
DRAM part、板级 timing/electrical 文件、真实 memory model 以及 boot/WDT
budget 仍缺失或未签收。详细获取顺序和 owner 见
[`docs/ddr4_external_input_acquisition.md`](ddr4_external_input_acquisition.md)。

DDR4 产品契约候选已建立，但 `DDR4-IN-01..08` 仍缺失，因此状态为
`DDR4_MEMORY_ENTRY_BLOCKED`；旧 DDR3 清单不能升级为产品 entry，旧状态仍为
`DDR_ENTRY_READY=0 / BLOCKED`；
`axi_ddr_behavioral` 只能提供地址/容量和 fabric 行为证据，不能提升为
ASIC controller/PHY、真实 DDR boot 或 `PRODUCT_FUNCTION_READY` 证据。

当前执行序列已确定为：**A 参数决策 → B PHY/IP 筛选 → C DDR4 契约/验证框架
→ 真实 PHY/controller → D 中的并行 P0 功能**。阶段 A 的签收表见
[`docs/asic_c1_ddr4_parameter_decision.md`](asic_c1_ddr4_parameter_decision.md)；
推荐基线已接受：28nm LP、TSMC N28/28HPC RFQ target、BGA、1.2 V
commercial、DDR4-2133、x32 single-rank、ECC disabled。`A-DDR4-02`
foundry/PDK 书面确认和 `A-DDR4-09` training/WDT 仍需外部签收；B 当前以
Synopsys DDR4 PHY/controller 为优先 RFQ，不能宣称 PHY 已选。若外部输入
暂时不可得，转入 F1 vendor-neutral contract/model + F4 并行 P0 功能，具体边界
见 [`docs/asic_c1_ddr4_contingency_plan.md`](asic_c1_ddr4_contingency_plan.md)。

## 3. 商用 SoC 功能判断

**结论：当前项目不是功能完整的商用 SoC。** 它已经具备可执行的 MIPS32 原型 SoC 和一套通过的当前 RTL 契约回归，但产品启动、真实主存、MMU 启用、对外 UART、QSPI boot 和系统软件入口尚未闭合。块级 RTL 存在或 unit test 通过均不能替代该结论。

| 域 | 当前产品集成 | 已有测试证据 | 商用功能结论 |
|---|---|---|---|
| CPU/CP0 | 已接入；默认 `SOC_MMU_ENABLE=0`；产品模式区分 CacheErr、TLB miss refill、invalid/general 与 IP-based vectored interrupt 的 BEV/EBase 向量 | smoke 与 Phase 3A/3B CPU/CP0 gate 通过；CP0 timer/TLB 单测验证 `IV/VS`；产品 directed 覆盖 I-side BEV=1/0 miss/invalid、D-side BEV=1 miss/invalid、EBase `Mod` precise state/recovery、CacheErr `ExcCode=30`/`ERL`/`ErrorEPC`/`EBase+0x100`，以及软件 `IP1` 到 `EBase+0x220`；`product-cacheerr-gate` 还覆盖真实 MMU/D-cache/APB SLVERR 到 handler/ERET | refill/invalid、最小 kernel-mode `Mod` recovery、CacheErr hardware contract 和注入式 production handler/recovery slice 已验证；ECC/多级 cache recovery、完整 Modified policy、外部 EIC/VEIC、ISA reference/compliance 和 MMU 产品启动仍未闭合 |
| L1 cache | 阻塞式 D-cache 在 DUT；4-way I-cache 已合入 `integration/function-contract` | D-cache unit、`cache_sweep` 与 smoke 通过；IF/I-cache response-PC 的默认和 Boot ROM reset-branch directed tests、合入后 unit gate `10/10`、SoC smoke 和 seed 10 UVM stress 通过 | I-cache 具备当前集成基线的 block/通用 SoC 证据；本次只关闭 response-PC 对齐的 reset/branch 子项，refill/eviction/reset 专项 SoC 测试仍不足，不能标为 `CONTRACT_CLOSED` |
| L2 cache | 默认 write-through L2 已接入；write-back 为 opt-in | L2 unit、L2 firmware、Phase 2/3 与 smoke 通过 | 当前 blocking L2 契约可用；不具备 coherency/ECC/生产性能闭合 |
| AXI fabric | C3 crossbar 已在 `master`；DDR 是 S3 slave | fabric unit `4/4`，Phase 2/3、10-seed stress 通过 | cross-slave 并发已验证；同一 slave 仍受单 outstanding slave 限制 |
| DMA | 已接入 APB/AXI | DMA unit、DMA firmware、DMA copy/IRQ UVM 通过；grant stability 修复已在 C2 集成父线 | 当前 direct-copy/IRQ 契约有证据；不可宣称 IOMMU/coherency 或完整系统 DMA 生态 |
| VIC/interrupt | 已接入 CPU 单 IRQ 线，源为 UART/TIMER/DMA；CPU 侧支持按 `Cause.IP` 的 `Cause.IV/IntCtl.VS` 向量，`Config3.VEIC=0` | VIC unit、VIC firmware、PIC mask UVM 与 IP1 vectored-interrupt SoC gate 通过 | mask/active 与 CPU IP-based vector 已验证；外部 EIC/VEIC vector ID、嵌套/优先级跨 VIC-CPU 合同和 UART RX source 当前不可用 |
| UART | `apb_uart_16550` 已接入 APB；`soc_top` 已暴露 UART TX/RX、RTS/CTS、DTR/DSR、DCD/RI pins；PIC bit0 为 RX-specific IRQ，bit1 保留历史 aggregate IRQ 语义；legacy/UVM 配置仍可关闭 pin wiring | UART unit、UART CPU loopback gate 和 block aggregate `10/10` 通过；unit 已分别检查 RX/TX IRQ；尚无真实外部 RX waveform、pad-mux 或板级 gate | RTL pin/IRQ wiring 已实现，但产品 pad binding、外部线路/电气约束、板级驱动和 RX 外部流量仍未闭合 |
| DDR | S3 当前仍直接连接 `axi_ddr_behavioral` 容量占位模型；F1 新增 `ddr4_phy_behavioral` vendor-neutral abstract model，但没有 vendor DFI port/IO 行为；S3 未替换，DDR4 product controller 未接入 | `ddr4-phy-behavioral` gate 通过 init/training success/failure、refresh backpressure、读写、fatal/非法命令；`fabric-unit-gate` 4/4；`product-mmu-boot-gate` PASS；`ddr4_external_input_acquisition.md` 已定义 DRAM、package、board SI/PI/timing 的获取路径；entry audit 仍为 `DDR4_ENTRY_READY=0` | F1 只能标为 `BLOCK_VERIFIED (vendor-neutral)`，不能证明 Synopsys/TSMC N28 PHY、SI/PI、training margin、真实 DDR4 memory model 或 DDR4 boot；属于 P0 blocker |
| Flash/boot | `axi_spi_flash` 支持简单 SPI read XIP；独立只读 Boot ROM 已作为 S4 接入产品配置。产品 XIP read 以默认 512-cycle AXI guard 限时，uncached 非 OKAY response 经 CPU 转 IBE/DBE，cached refill/writeback 错误经 CacheErr sideband 转 ExcCode=30；开发 Boot ROM 可经产品 SPI 引脚读取 manifest/payload、CRC 校验、拷贝 Boot SRAM 并转交 kseg0 stage 1 | Boot ROM burst/read-error/write-reject、无 SRAM preload 的首笔复位取指、response-PC 对齐的 reset branch、普通异常、TLB refill/invalid product directed tests、AXI timeout guard、I/D cache error unit、CPU CacheErr/ERL directed gate、`product-cacheerr-gate` 以及有效、11 条 header/CRC failure 和 timeout-to-DBE manifest handoff 均通过；生产 `axi_spi_flash` 的 pin-level `0x03`/24-bit address、连续读和写 `SLVERR` unit gate 通过 | 真实单线 XIP 具备 development reset-to-handoff、字段拒绝、controller/AXI stall failure、cached-refill CacheErr handler/recovery slice 和软件 mailbox 证据；仍无 production ROM/signature、ECC/完整软件错误分类、原始 SPI 无响应检测、QSPI command/FIFO/erase/program/四线、DDR init 或 U-Boot boot，仍为 P0 blocker |
| MMU/TLB | RTL 与 unit TB 存在，默认关闭；产品 opt-in 具备 CacheErr、refill/invalid vector routing、最小 Boot ROM kseg1 linker、BEV refill handler、wired kseg2-APB map，以及复制到 SRAM 的 EBase `Mod` handler | MMU/CP0 unit、`make tlb-asid-policy-gate`、`make tlb-os-context-gate`、`make product-mmu-asid-context-gate`、`make cpu-cache-error-gate`、`make product-cacheerr-gate`、完整 SoC I/D vector directed、`make product-mmu-boot-gate` 和 `make product-mmu-ebase-modified-gate` 通过；ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified；OS-context gate 覆盖软件页表 walk、同 VA 不同 ASID/PFN、wired global 保留、非 wired flush 和 1..255 回卷；SoC gate 进一步覆盖真实 firmware 的 ASID 1/2 映射、切回命中、TLBWI 清除动态槽、wired APB 保留和重新 refill；后者覆盖 DTLB `Mod`、CP0 precise state、EBase handler relocation、`D` bit repair 和 `ERET` retry；`product-cacheerr-gate` 覆盖 cacheable kseg2 APB refill、AXI SLVERR、`Cause.ExcCode=30`、ERL/ErrorEPC、单次 handler marker 和 ERET；IP-based vectored interrupt 有独立 SoC gate | 最小 BEV 启动、4KB ASID/异常分类、软件管理 TLB context-switch/shootdown slice、CacheErr hardware contract 和注入式 handler/recovery slice、单一 EBase `Mod` recovery 与 CPU vector table 已有证据；完整 kseg0 runtime、SoC 多进程 allocator/压力、ECC/外部 EIC/VEIC policy、kernel/OS boot 仍未闭合 |
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

本阶段按当前范围只要求 RTL 编译/elaboration、unit/firmware/SoC behavioral
simulation 和 DDR4 F1 behavioral gate。`phase2-complete`、`phase3-complete`、
`phase3b/3c-complete` 及 `current-contract-signoff` 属于后续扩展回归；其中的
coverage threshold 不属于当前退出条件。

按以下顺序执行，任何一步失败都停止向后推进：

1. `make rtl-frontend-compile`
2. `make firmware`
3. `make ddr4-phy-behavioral-gate`
4. `make dut-block-unit-gate`
5. `make fabric-unit-gate`
6. `make soc-smoke`
7. `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix`
8. `make phase2-complete`
9. `make phase3-complete`
10. `make phase3b-complete` 和 `make phase3c-complete`
11. `make current-contract-signoff`

Phase 1 当前关闭条件是：RTL compile/elaboration 成功，seed 10 无 checker/scoreboard/error，
F1 DDR4 behavioral gate 通过，并生成可追溯的 unit/firmware/SoC 仿真报告。full signoff
和 coverage threshold 延后，不阻塞 `RTL_FUNCTIONAL_SIM_READY`。

当前基线 `5763eec` 已满足 `RTL_FRONTEND_COMPILE_READY`，并已具备
`RTL_FUNCTIONAL_SIM_READY` 所需的 unit、firmware、SoC/UVM、F1 DDR4、Boot ROM/MMU、
XIP/WDT/UART 和 ASID context-switch 行为证据；这不是 `PRODUCT_FUNCTION_READY`，真实 DDR4、
完整 runtime/page-table、ECC/外部 EIC、生产 QSPI 和板级 I/O 仍未闭合；注入式 CacheErr handler/recovery slice 已新增，但不等于量产错误策略闭合。

### Phase 2：产品启动与主存闭合

- 已建立 `docs/boot_memory_contract.md` v1.6，冻结候选 reset/vector、物理/虚拟地址图、镜像格式、失败行为和六个行为 gate；`docs/block_specs/ddr3_spec.md` v1.0 冻结 DDR controller/PHY 的 AXI/APB/DFI/error contract，`soc_config.vh` 固化 `SOC_APB_DDRCTRL_BASE` 及寄存器 offsets；`make ddr-contract-entry-audit` 已将外部输入缺失变成可重复的 `BLOCKED` 结果。该动作只关闭接口歧义，不代表 DDR RTL 已实现。
- 第二至第十五个 RTL/firmware 垂直切片已完成：TLB lookup miss 与 matching-invalid 的 vector 分派覆盖 I-side 两个 BEV 模式和 D-side BEV=1；最小产品 Boot ROM linker/BEV refill handler 进一步覆盖 wired kseg2-APB 映射、DTLB refill、`TLBWR`、寄存器恢复、`ERET` retry、DDR store/load 和 APB write；独立 ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、Invalid/Modified 分类以及同一 index 的 `0xfe -> 0xff` replacement/旧 ASID 隔离；新增 OS-context gate 以真实 `mips_tlb + mips_mmu` 验证软件页表查找、同一 VA 在两个 ASID 下的不同 PFN、wired global 保留、非 wired 清空和 8-bit ASID 1..255 回卷；独立 gate 还证明 Boot ROM 把通用 handler 复制到 SRAM `EBase+0x180`，处理 precise `Mod`、将 `D=0` 改为 `D=1` 并 `ERET` retry；IP-based `Cause.IV/IntCtl.VS` vectored interrupt gate 已证明 IP1 到 `EBase+0x220`；development manifest gate 则经实际 SPI XIP 完成 CRC 校验、Boot SRAM 拷贝和 kseg0 stage-1 handoff，`product-kseg0-runtime-gate` 在 `SOC_MMU_ENABLE=1` 下确认入口取指 `0x8000_1000 -> 0x0000_1000` 和一次数据访问 `0x8000_7000 -> 0x0000_7000`；XIP guard 则将下游 AR/R stall 限时为 `SLVERR`，经 uncached cache/CPU DBE 路径由 Boot ROM 记录 `DEAD_B007`；新增 QSPI/XIP status integration gate 已证明 guard timeout 经产品 APB decode 可读出版本、controller-present、sticky timeout 和 `0x0001_0001` 错误码，并可由 W1C 清除；UART pins/IRQ slice、WDT APB/reset path、boot-status retention、预加载 firmware reset-retention 和无 SRAM preload 的 Boot ROM WDT failure slice 已有独立 gate；`product-cacheerr-gate` 通过真实 MMU/D-cache/APB fault injector 验证 cacheable refill 的 AXI `SLVERR` 到 `Cause.ExcCode=30`、`Status.ERL=1`、精确 `ErrorEPC`、`BFC0_0100` handler marker、ErrorEPC+4/`ERET` 和成功 mailbox。仍只关闭向量路由、最小 BEV 启动链、4KB ASID/异常分类、软件 context-switch 子集、单一 `Mod` recovery、development handoff、有限 kseg0 instruction/data 与硬件 rollover 边界、AXI-side XIP stall/状态观测切片、manifest/DDR 故障到 failure code 的完整分类、完整 kseg0 runtime 数据路径、ECC/外部 EIC/VEIC policy、生产 QSPI 和真实 DDR。
- 冻结 ROM boot 地址、异常向量和 firmware linker 规则；不能继续从 useg reset vector 启动。
- ASIC 路线下先按 `docs/ddr4_external_input_acquisition.md` 完成 `DDR4-IN-01..08`，同步登记 `docs/ddr4_integration_inputs.md` 并使 `DDR4_ENTRY_READY=1`；之后才实现真实 DDR controller/PHY contract，完成 init、calibration、refresh、AXI backpressure 与 DDR memory test。该步骤属于后续产品入口，不阻塞当前 RTL 前端阶段。
- 实现实际 QSPI boot source（XIP/command path、image format、boot ROM）并完成 reset 到 first-stage firmware 的 SoC gate。
- 在 Phase 2 完成前，禁止把 behavioral DDR 或 loadable flash-image 测试称为产品 boot/memory 闭合。

### Phase 3：CPU、缓存和总线功能闭合

- 4-way I-cache 已合入并完成通用 unit/SoC 证据；补 refill、eviction、reset 的专项 SoC sequence 后，才能将其标为 `CONTRACT_CLOSED`。
- 将 C.2 变更拆成 L2-NB、ROB、DDR placeholder、DMA 修复四个可审阅主题。
- 保持 `dcache_nb.v` 独立，先完成 block gate；之后进行 C.4 Stage 4：CPU/ROB tag、完成重排、load-use hazard 和 forwarding。
- 只有完成 CPU 接入、SoC smoke、UVM overlap/stress 和性能前后对比后，D-cache NB 才能变成 `SOC_INTEGRATED`。
- 明确当前限制：1 MSHR、2-slot order queue、下游单 outstanding；2+ MSHR、store buffer 和完整 CACHE 指令继续列为 backlog。

### Phase 4：外设与系统软件功能闭合

- `SOC_MMU_ENABLE=1`：最小 Boot ROM kseg1 linker、BEV refill handler、wired mapping、4KB ASID/Global/Invalid/Modified policy gate、软件页表/context-switch 子集、EBase `Mod` handler relocation/retry gate、stage-1 kseg0 指令交接 gate，以及真实 cached-refill CacheErr handler/recovery gate 已通过；继续完成完整 kseg0 runtime 数据路径、SoC page-table allocator/多进程压力、ECC/外部 EIC policy 和 kernel-mode firmware gate。refill/invalid 的 EBase/BEV 向量路由、CacheErr hardware vector 及 IP-based vectored interrupt 已有 directed 证据。
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

历史 full signoff 的功能阶段均通过，coverage 阈值单独失败，保留为后续质量工作。当前执行优先级已改为
**RTL 前端编译和功能仿真**：不等待完整 PDK/PHY/package/板级资料，也不把综合、时序或 PPA
混入当前 gate。Boot ROM/向量、最小 MMU/TLB、SPI XIP、manifest handoff、WDT retention 和
DDR4 vendor-neutral F1 行为证据继续按 RTL 功能任务管理；完整 kseg0 runtime、page-table/ASID
rollover、ECC/complete cache-error policy、EIC/VEIC、QSPI production path 和真实 DDR4 product entry 仍未完成。**

## 9. 执行记录

| 时间 | 基线 | 命令 | 结果 | 结论 |
|---|---|---|---|---|
| 2026-08-01 | `phase-c2-l2-nonblocking@4baf139`，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix` | FAIL：14.49 us 时 SRAM/S0 AR payload 在 `ARVALID && !ARREADY` 期间变化，14.51 us 时 `ARVALID` 提前撤销；随后 CPU memory stall 直至 watchdog | `4baf139` 未关闭该 SoC blocker。暂停 Phase 1 的后续 gate，先定位 S0 AR 驱动路径。日志：`build/uvm/seed10_dma_fix/vcs_uvm.log` |
| 2026-08-01 | 当前工作区，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_jtag_payload_fix` | PASS：`REGRESSION_TEST_SUCCESS`，无 UVM error/fatal 或 `$error` | 根因是 TCK 域命令寄存器在 AXI 请求等待期间直接改变 master payload。JTAG 启动请求时锁存地址/写数据到 `clk` 域后，S0 和 JTAG master 的 AXI checker 均通过。日志：`build/uvm/seed10_jtag_payload_fix/vcs_uvm.log` |
| 2026-08-01 | 当前工作区 | `make dut-block-unit-gate` | PASS：MDU、DMA、VIC、UART、WDT、L2NB、D-cache、mini-ROB、D-cache NB 共 9/9 | `dcache_nb` 达到块级验证，不代表已接入 CPU 或 SoC。报告目录：`build/unit_tb/dut_block_readiness` |
| 2026-08-01 | 当前工作区 | `make fabric-unit-gate FABRIC_UNIT_DIR=build/unit_tb/fabric_ddr_contract` | PASS：crossbar core、QoS、multi-outstanding、DDR 共 4/4 | DDR evidence 仅覆盖 `SOC_DDR_BASE` 映射、128-MB/FLASH 边界、behavioral read-after-write 和 unmapped `DECERR`；不覆盖 controller/PHY init/calibration/refresh。独立报告目录：`build/unit_tb/fabric_ddr_contract` |
| 2026-08-01 | 当前工作区 | `make product-mmu-boot-gate PRODUCT_MMU_BOOT_DIR=build/unit_tb/product_mmu_boot_ddr_contract` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_boot` | Boot ROM/MMU firmware 完成 wired TLB、DTLB refill/`ERET` retry、behavioral DDR store/load 与 APB write；该 gate 明确使用 `axi_ddr_behavioral`，不能升级为真实 DDR product boot evidence。 |
| 2026-08-01 | `integration/function-contract` | `make ddr-contract-entry-audit DDR_ENTRY_AUDIT_DIR=build/unit_tb/ddr_contract_entry_v1` | PASS：契约一致性检查全部通过；报告状态为 `BLOCKED`（预期） | `DDR-IN-01..08` 中 PHY/IP、DFI port list、DRAM part、board timing、real memory model、WDT budget 仍缺失；审计确认未授权任何 `ddr3_ctrl` RTL，实现入口被明确阻塞。报告：`build/unit_tb/ddr_contract_entry_v1/ddr_contract_entry_report.md` |
| 2026-08-01 | `integration/function-contract` | DDR controller/PHY contract architecture review；`docs/block_specs/ddr3_spec.md` v1.0、`rtl/include/soc_config.vh` DDR APB macros、`docs/address_map.md` v0.4、`docs/boot_memory_contract.md` v1.6 | COMPLETE（文档/接口 gate，非 RTL 测试） | 冻结 AXI 32-bit/4-bit ID、INCR 1-16 beat、S3 地址边界、APB `0x4000_6000` 寄存器/错误 ABI、axi/ddr/DFI clock-reset 和 bounded `SLVERR` reject 语义；记录 PHY vendor/IP、DRAM part/timing file、real memory model 为 implementation blockers。S3 未替换，不能标为 `IMPLEMENTED` 或 `SOC_INTEGRATED`。 |
| 2026-08-02 | `integration/function-contract` | `make ddr-contract-entry-audit DDR_ENTRY_AUDIT_DIR=build/unit_tb/ddr_contract_entry_profile_c1_ddr4` | PASS：契约、ASIC Profile C1 DDR4、DDR4 spec/manifest 检查通过；总体结果为 `BLOCKED`（预期） | 已记录用户选择 C1 DDR4，建立 `ddr4_spec.md` 与 `DDR4-IN-01..08` 输入清单；旧 DDR3 清单降为 legacy prototype 边界，未授权产品 DDR4 controller。报告：`build/unit_tb/ddr_contract_entry_profile_c1_ddr4/ddr_contract_entry_report.md` |
| 2026-08-02 | `integration/function-contract` | 建立 [ASIC C1 DDR4 参数决策包](asic_c1_ddr4_parameter_decision.md) | BASELINE ACCEPTED：A-02/A-09 外部签收待定，B RFQ 准备启动 | 已接受 28nm LP、BGA、1.2 V commercial、DDR4-2133、x32 single-rank、ECC disabled；foundry/PDK 和 training/WDT 仍未签收。 |
| 2026-08-02 | `integration/function-contract` | 建立 [C1 DDR4 PHY/IP 筛选计划](asic_c1_ddr4_phy_selection_plan.md) | RFQ_PRIORITY_SYNOPSYS：PHY_NOT_SELECTED | 已选择 Synopsys + TSMC N28/28HPC 作为优先 RFQ 组合，保留 Cadence/Rambus/foundry-approved 备选；只有工艺/封装确认和 vendor 书面支持后，才能更新 `DDR4-IN-03/04/07`。 |
| 2026-08-02 | `integration/function-contract` | 建立 [C1 DDR4 外部输入缺失推进方案](asic_c1_ddr4_contingency_plan.md) | ACTIVE：F1 + F4；DDR4 产品 entry 仍 BLOCKED | 外部资料暂不可得时，F1 只做 vendor-neutral contract/model，F4 推进 kseg0 runtime、page-table/ASID rollover、cache-error/EIC、QSPI/UART/WDT 等 P0；不得将 behavioral/FPGA 证据升级为 ASIC DDR4 证据。 |
| 2026-08-02 | `integration/function-contract` | `make ddr4-phy-behavioral-gate DDR4_PHY_BEHAVIORAL_DIR=build/unit_tb/ddr4_phy_behavioral_f1_v3` | PASS：`REGRESSION_TEST_SUCCESS ddr4_phy_behavioral` | F1 抽象 PHY 验证 init/training success、training/init failure、refresh busy/backpressure、读写、fatal 和非法命令；证据等级为 `BLOCK_VERIFIED (vendor-neutral)`。 |
| 2026-08-02 | `integration/function-contract` | `make fabric-unit-gate FABRIC_UNIT_DIR=build/unit_tb/fabric_f1_ddr4_contract`；`make product-mmu-boot-gate PRODUCT_MMU_BOOT_DIR=build/unit_tb/product_mmu_boot_f1_ddr4` | PASS：fabric `4/4`；`REGRESSION_TEST_SUCCESS product_mmu_boot` | F1 增量未回归现有 AXI DDR window、crossbar 和 MMU boot behavioral DDR evidence；不代表真实 DDR4 PHY/controller 完成。 |
| 2026-08-01 | `integration/function-contract` | `make ddr-contract-entry-audit DDR_ENTRY_AUDIT_DIR=build/unit_tb/ddr_contract_entry_asic_v1` | PASS：契约、ASIC 路线和输入获取计划检查通过；总体结果为 `BLOCKED`（预期） | 已将产品路线固定为 ASIC，并记录 `ASIC-DDR-01..08` 的获取顺序；工艺/foundry/package/PHY/DRAM/board/model/WDT 输入仍未登记，未授权 `ddr3_ctrl` RTL。报告：`build/unit_tb/ddr_contract_entry_asic_v1/ddr_contract_entry_report.md` |
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
| 2026-08-01 | `integration/function-contract` QSPI/XIP status observability slice | `make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=build/unit_tb/qspi_status_integration_try3` | PASS：`REGRESSION_TEST_SUCCESS qspi_status_integration` | 先完成正常 downstream read 证明不误报，再让真实 `axi_read_timeout_guard` 的 AR stall 经产品 peripheral APB decode 读回版本 `0x51535001`、controller-present、timeout sticky 和错误 `0x0001_0001`；W1C 清除状态/错误且不误清 present。该证据只覆盖故障观测，不代表完整 QSPI controller。 |
| 2026-08-01 | `integration/function-contract` vectored-interrupt slice | `tb/unit/cp0/run.sh`、`make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/product_vectored_interrupt_try4` | PASS：`cp0_timer: PASS`、`REGRESSION_TEST_SUCCESS product_vectored_interrupt` | CP0 验证 `Cause.IV`/`IntCtl.VS`、最高 enabled pending IP7、`VS=1` 的 `0x2E0` 和最大 `VS=31` 的 `0x1D20` 偏移；完整产品 SoC 仅加载 Boot ROM、无 SRAM preload，以软件 IP1、`VS=1`、`BEV=0` 进入 `0x8000_0220`，并观察物理 `0x0000_0220` 取指及 `EXL/INT` 状态。 |
| 2026-08-01 | 同上 | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/vectored_interrupt_aggregate_final`、`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/vectored_interrupt_smoke` | PASS：block aggregate、`REGRESSION_TEST_SUCCESS` | 新 CP0/vector 接口未回归 MDU、DMA、VIC、UART、WDT、L2/L2NB、L1 cache、ROB、SPI/XIP、Boot ROM/MMU；smoke `CPU_CP0_SUMMARY intr=11 syscall=1 ri=4 adel=1 eret=16`。smoke 中的 `RI=0xA` 输出来自显式非法指令/嵌套异常 stimulus。 |
| 2026-08-01 | `integration/function-contract@c7018b7` | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit/tlb_asid_policy_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/tlb_asid_aggregate` | PASS：独立 gate `REGRESSION_TEST_SUCCESS tlb_asid_policy`，原始 8 项检查通过；Boot ROM/MMU 聚合 `10/10` | 以 `SOC_MMU_ENABLE=1` 直接连接 `mips_tlb`/`mips_mmu`；证明 4KB 非 Global ASID 隔离、奇偶页选择、Global 跨 ASID，以及 matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified 分类。该历史 gate 未覆盖可变页、multi-hit、micro-TLB 或 OS 级压力；后续 `tlb_os_context` gate 已补充软件 context-switch 边界。 |
| 2026-08-01 | `integration/function-contract` UART pin/IRQ slice | `make uart-cpu-gate SOC_TEST_UART_CPU_DIR=build/soc_test/uart_pins_gate_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/uart_pins_aggregate` | PASS：UART CPU firmware gate；UART unit 检查 RX/TX IRQ 分离；DUT block aggregate `10/10` | `soc_top` 产品 wrapper 接出 UART/modem pins；PIC bit0 连接 RX-specific IRQ，bit1 保持历史 aggregate IRQ，`ENABLE_UART_PINS=0` 的 legacy/UVM tie-off 行为未改变。仍缺外部 RX waveform、pad-mux 和板级 gate。 |
| 2026-08-01 | `integration/function-contract` WDT APB/reset slice | `make wdt-unit-gate WDT_UNIT_DIR=build/unit_tb/wdt_try2`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_try1`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/wdt_compile_smoke` | PASS：`REGRESSION_TEST_SUCCESS wdt`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、默认 SoC smoke | WDT 已在 `0x4000_7000` 解码；外设 gate 通过 AXI/APB 写 LOAD/CTRL，观察一次性 reset pulse 拉低 aggregate reset 并在 reset 后读到 sticky STATUS。尚未验证 Boot ROM failure code/boot-status persistence。 |
| 2026-08-01 | `integration/function-contract` boot-status retention slice | `make boot-status-unit-gate`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_boot_status`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/boot_status_smoke` | PASS：`REGRESSION_TEST_SUCCESS boot_status`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、`REGRESSION_TEST_SUCCESS` | `0x4000_8000` 解码为 always-on APB block；`BOOT_STAGE`/`FAILURE` 在 WDT reset 后保持，`RESET_CAUSE[POR/WDT]` sticky 且 W1C。该 gate 只证明寄存器和 reset retention，不代表 Boot ROM failure firmware 已闭合。 |
| 2026-08-01 | `integration/function-contract` WDT boot-failure firmware slice | `make wdt-boot-failure-gate` | PASS：`wdt_boot_failure: REGRESSION_TEST_SUCCESS`、SoC mailbox `REGRESSION_TEST_SUCCESS` | 预加载 firmware 首次写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070001` 后 arm WDT；第二次入口读回 stage/failure 与 `POR|WDT` cause，清除状态后完成。该证据覆盖软件触发 reset/retention，不满足无 SRAM preload 的产品 boot gate。 |
| 2026-08-01 | `integration/function-contract` product WDT Boot ROM failure slice | `make product-wdt-boot-failure-gate PRODUCT_WDT_BOOT_FAILURE_DIR=build/unit_tb/product_wdt_boot_failure_try6` | PASS：`REGRESSION_TEST_SUCCESS product_wdt_boot_failure` | 不调用 `preload_sram_hex`；Boot ROM 在 `SOC_MMU_ENABLE=1` 下安装 5 个 wired APB TLB entries，写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070002`、arm WDT，第二次 `BFC0_0000` 入口校验 `POR|WDT` 与保留字段后写成功 mailbox。该 gate 证明 reset/retention 软件路径，不覆盖 manifest/QSPI/DDR 故障分类。 |
| 2026-08-02 | `integration/function-contract` RTL 前端统一 compile/elaboration gate | `make rtl-frontend-compile` | PASS：default `soc_top`、`SOC_PRODUCT_BOOT_ENABLE=1 + SOC_MMU_ENABLE=1`、独立 DDR4 behavioral PHY 共 `3/3`；报告：`build/unit_tb/rtl_frontend_compile/rtl_frontend_compile_report.md` | 当前基线的 clock/CPU/AXI/peripheral/cache/SoC RTL 均完成统一 VCS elaboration；DDR4 仍是 vendor-neutral F1 模型，不升级为真实 PHY/controller 证据。 |
| 2026-08-02 | `integration/function-contract` 仿真契约告警清理 | `make product-wdt-boot-failure-gate PRODUCT_WDT_BOOT_FAILURE_DIR=build/unit_tb/rtl_frontend_wdt_failure_fix2`；`make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/rtl_frontend_vectored_fix`；`make product-mmu-boot-gate PRODUCT_MMU_BOOT_DIR=build/unit_tb/rtl_frontend_mmu_fix` | PASS：三个 gate 均返回 `REGRESSION_TEST_SUCCESS`；product Boot ROM testbench 已显式 tie-off UART/modem ports；`axi_ddr_model` 无 `+FW_HEX` 时保持零初始化，不再探测不存在的默认文件 | 修复只涉及 testbench 端口连接和 behavioral model 的镜像加载诊断，不改变 `ENABLE_UART_PINS=0` 或显式 `+FW_HEX` 行为。toolchain 的 linker build-id warning 仍为非 RTL 诊断。 |
| 2026-08-02 | `integration/function-contract` MMU-enabled kseg0 data slice | `make product-kseg0-runtime-gate PRODUCT_KSEG0_RUNTIME_DIR=build/unit_tb/product_kseg0_runtime_multiword`；`make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_handoff_multiword`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/rtl_frontend_block_aggregate` | PASS：MMU-enabled handoff 的 stage-1 kseg0 instruction/data checks、valid manifest、11 个 rejection、XIP timeout 均通过；Boot ROM/block aggregate `10/10` | stage-1 在 `0x8000_7000` 和 `0x8000_7004` 写入，再从 `0x8000_7004` 读回并校验；TB 观察两个 VA->PA 映射和读回，仍不升级为完整 runtime data mapping、OS/page-table 或 cache-maintenance evidence。 |
| 2026-08-02 | `integration/function-contract` TLB ASID rollover slice | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit_tb/tlb_asid_policy_rollover` | PASS：`tlb_asid_policy`；同一 index 的旧 `ASID=0xfe` 映射在切换到 `0xff` 时 miss，重写后新 PFN 命中且旧 ASID 继续隔离 | 关闭硬件 lookup/replacement 的最小 rollover 证据；不覆盖 OS ASID allocator、TLB shootdown、page-table walk、multi-hit 或 context-switch 压力。 |
| 2026-08-02 | `integration/function-contract` OS page-table/context-switch slice | `make tlb-os-context-gate TLB_OS_CONTEXT_DIR=build/unit_tb/tlb_os_context_try2` | PASS：`REGRESSION_TEST_SUCCESS tlb_os_context` | 以真实 `mips_tlb + mips_mmu` 建立软件页表 fixture；覆盖同一 VA 的 ASID 1/2 不同 PFN、VPN pair even/odd、wired global 映射、ASID 1..255 分配、非 wired flush 和回卷后重新填充。仍不是 Linux page-table、IPI shootdown 或 demand paging 证据。 |
| 2026-08-02 | `integration/function-contract` SoC ASID/context/shootdown slice | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/product_mmu_asid_context_try3` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | Boot ROM kseg1 firmware 在真实 CPU/CP0/TLB/MMU/DDR behavioral SoC 上以软件 PTE 为 ASID 1/2 建立同 VA 不同 PFN，切回验证旧映射，使用 `TLBWI` 清除 index 1..63，验证 wired APB 映射仍在并触发 ASID 1 重新 refill；不覆盖 Linux allocator、TLB shootdown IPI、multi-core 或长时间调度压力。 |
| 2026-08-02 | `integration/function-contract` CacheErr exception slice | `make cpu-cache-error-gate CPU_CACHE_ERROR_DIR=build/unit_tb/cpu_cache_error` | PASS：`REGRESSION_TEST_SUCCESS mips_cpu_cacheerr` | D-cache cached-error sideband 使用 ExcCode=30，产品模式跳转 `EBase+0x100`，CP0 置 `ERL=1`、保持 `EXL=0` 并保存精确 `ErrorEPC`；uncached DBE policy 未改变。 |
| 2026-08-02 | `integration/function-contract` CacheErr production recovery slice | `make product-cacheerr-gate PRODUCT_CACHEERR_DIR=build/unit_tb/product_cacheerr`；`make rtl-frontend-compile`；`make product-mmu-asid-context-gate` | PASS：`REGRESSION_TEST_SUCCESS product_cacheerr`、`RTL frontend compile gate: PASS (3/3)`、`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | 新增 `mips_soc.ENABLE_APB_FAULT_INJECTOR` 仅供 directed test opt-in；真实 MMU `C=3` kseg2 APB refill 遇 `SLVERR` 后进入 `BFC0_0100`，handler 校验 `Cause=30`、写 `CACE0001` marker、递增 `ErrorEPC`、`ERET` 清 ERL 并完成 mailbox。D-cache 旧 0x4/0xA 物理地址 uncached heuristic 限定为 prototype，避免覆盖产品 TLB C 属性。该 slice 不覆盖 ECC、完整 cache maintenance、EIC/VEIC 或量产 ROM。 |
| 2026-08-02 | `integration/function-contract` CacheErr recovery integration tip | `b06bc74` (`feat: add product CacheErr recovery gate`)；block aggregate `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/dut_block_cacheerr_fix` | PASS：DUT block `10/10`；product CacheErr、CPU CacheErr、product MMU/ASID context、RTL frontend compile `3/3` 均在该 tip 重跑通过 | 当前功能线已提交；结论仍为 `RTL_FUNCTIONAL_SIM_READY`，不是 `PRODUCT_FUNCTION_READY`。ECC、完整 cache maintenance、EIC/VEIC、量产 ROM、QSPI production path 和真实 DDR4 仍未闭合。 |

## 10. 已知未决问题

| 优先级 | 问题 | 对计划的影响 | 处理条件 |
|---|---|---|---|
| P0 | 产品 boot、DDR 和 QSPI 尚未闭合：Boot ROM 复位、普通与 refill/invalid BEV-EBase vector、IP-based vectored interrupt、最小 BEV MMU firmware、单一 EBase `Mod` recovery、development manifest header/CRC-to-SRAM handoff、cached-refill CacheErr handler/recovery，以及 controller/AXI stall-to-DBE 和 QSPI timeout status 观测已通过；ASIC Profile C1 DDR4 已选但 `DDR4-IN-01..08` 仍未登记，旧 `DDR-IN-01..08` 仅为 legacy DDR3 边界，`ddr-contract-entry-audit` 已确认契约一致但 `DDR4_ENTRY_READY=0`；PHY/IP、DRAM part/timing file、real memory model、WDT budget 和 RTL 仍未实现；生产 ROM/signature、ECC/完整 cache-error policy、原始 SPI 无响应检测、外部 EIC/VEIC、QSPI/U-Boot/Linux 也未闭合 | SoC 已有受限的 reset-to-development-stage-1、behavioral DDR store/load、XIP transport-stall failure、软件可读 timeout 和 cached-refill recovery evidence，但无可发布的 secure boot 或产品主存，不能称商用 SoC | 先完成 `docs/ddr4_integration_inputs.md` 的 `DDR4-IN-01..08` 输入登记并使 `DDR4_ENTRY_READY=1`，重建 DDR4 controller/PHY contract；之后实现真实 PHY/controller、APB status、init/training/refresh、bounded AXI error path 和 no-preload boot gate；并继续实现 ECC/完整 runtime exception/cache-error policy、真正 QSPI command/FIFO/四线控制器、boot-status/WDT 与 production handoff，分别验证。 |
| P0 | 最小 Boot ROM kseg1 linker、BEV refill handler、wired mapping、4KB ASID/Global/Invalid/Modified gate、软件 page-table/context-switch 子集、SoC ASID 1/2 与 TLBWI shootdown slice、SRAM EBase `Mod` recovery、IP-based vectored interrupt、MMU-enabled kseg0 instruction/单次 data slice、硬件 ASID index replacement slice、CacheErr hardware vector/ERL/ErrorEPC 和注入式 handler/recovery gate 已通过；完整 SoC page-table allocator、multi-process/scheduler 压力、TLB shootdown IPI、ECC/外部 EIC policy 和 kernel firmware 未验收；历史 prototype smoke timeout 的 fetch-path 根因已修复 | MMU/TLB 有最小启动、4KB ASID/异常分类、软件/SoC context-switch 子集、`Mod` recovery、CacheErr hardware contract + recovery slice、CPU vector table、有限 kseg0 handoff 和 rollover boundary 证据，但不能作为可启动的产品 OS 功能 | 建立完整 kseg0 runtime linker/data layout、SoC page-table/ASID allocator 与多进程调度/shootdown 压力、ECC/production exception/cache-error policy 和 kernel firmware gate，再跑 exception regression。 |
| P0 | UART RTL pins/IRQ wiring 已接入 `soc_top`，但 pad-mux/板级电气绑定、真实外部 RX waveform 和 RX firmware 仍未验收；WDT APB/reset pulse、boot-status retention、预加载 firmware retention 和无 SRAM preload Boot ROM failure slice 已通过 | 对外 serial I/O 仍缺板级证据；WDT gate 只证明 deliberate Boot ROM failure/reset，不证明 manifest/QSPI/DDR 真实故障分类、量产 ROM 和板级 reset 观测 | 固化 UART pad contract 并补外部 RX gate；把真实 manifest/controller/DDR failure 映射到 failure code，并增加板级 watchdog/reset 观测。 |
| P3 | 当前 fresh VDB 执行 `refine_exclusions.py` 后，strict URG 仍报告 invalid condition/branch vector、illegal exclusion attempt 与 module checksum mismatch；合并 UVM 仅 SCORE `80.05`、COND `97.09`、TOGGLE `71.32`、FSM `53.33`、BRANCH `78.53`，product CPU/CP0 仅 SCORE `75.94`、LINE `83.84`、TOGGLE `69.05`、FSM `48.68`、BRANCH `78.33` | 当前功能行为证据有效，但 code-coverage 数字和 99% 入口均不能签收；不得提交本轮自动生成的 exclusion 文件 | 作为后续质量工作独立处理；不替代或阻塞本文件的产品功能 P0/P1。证据：`build/signoff/functional_completeness_20260801/coverage/urg.log`、`coverage_summary.json`。 |
| P2 | `dcache_nb` 与其 TB 是未提交 WIP，已通过块级 gate 但尚未接入 CPU/SoC | 只能标为 `BLOCK_VERIFIED`，不得计入当前 SoC 功能完成 | 完成 CPU 接入、hazard/forwarding 和 SoC stress 证据后再升级。 |
| P1 | crossbar 支持 cross-slave 并发，但 L2/APB/flash/DDR slave 仍限制同 slave outstanding；SPI serial boot、ECC/完整 cache-error policy、EIC/VEIC policy、MMU/Linux boot 均未纳入当前 RTL contract | 即使当前功能 gate 通过，也只能声明当前已文档化契约，不是商用 SoC 完整性结论 | 每项建独立 spec/RTL/firmware/UVM 变更集，并按本计划的五级状态推进。 |
| P3 | `tb/uvm_tb/cov.cfg` 仍包含 3 个不存在模块模式，VCS 每次 coverage compile 均发出 `VCM-HFUFR` warning | 不影响当前产品功能主线，但使 coverage scope 噪声和进度判读变差 | 在后续 coverage 专项中删除或更新过时 scope；再跑 coverage compile，要求该 warning 清零。 |

## 11. 当前剩余任务（仅 RTL 前端）

以下任务是当前阶段的实际清单；完成条件是 RTL 可编译、仿真可重复且行为证据完整，
不要求综合结果或工艺文件。

| 优先级 | 剩余任务 | 当前状态 | 关闭证据 |
|---|---|---|---|
| P0 | 固定唯一集成线，清理分支/WIP 归属；D-cache NB 保持独立，不与产品默认路径混合 | `integration/function-contract` 为功能线；`feature/dcache-nb-stage3` 仍有未提交 WIP | 干净工作区、每个变更集有独立 commit 和 owner |
| P0 | 完成全仓 RTL compile/elaboration，包含默认 SoC、Boot ROM/MMU 配置和 F1 DDR4 behavioral 配置 | 已完成：统一 gate `3/3` 通过；报告 `build/unit_tb/rtl_frontend_compile/rtl_frontend_compile_report.md` | 维护 `RTL_FRONTEND_COMPILE_READY`；后续新增 RTL 或参数配置必须重新运行 `make rtl-frontend-compile` |
| P0 | 完成 DDR4 vendor-neutral contract/model 仿真：初始化、training 成功/失败、refresh、读写、背压、reset、fatal/error | F1 behavioral gate 已通过；尚未成为真实 PHY/DDR4 product entry | `RTL_FUNCTIONAL_SIM_READY`；F1 证据保持 `BLOCK_VERIFIED (vendor-neutral)` |
| P0 | 补齐 CPU/MMU 前端功能缺口：完整 kseg0 runtime、SoC page-table/ASID allocator 与多进程调度/shootdown 压力、ECC/外部 EIC policy | 最小 refill/invalid/Modified/vector、CacheErr hardware contract + cached-refill recovery、软件/SoC page-table/context-switch 子集、单次 kseg0 data 和硬件 index replacement 子集已有证据 | firmware + SoC simulation 通过，并记录异常/恢复矩阵 |
| P1 | 补齐 QSPI production command/FIFO/四线 RTL 契约、UART RX/pad behavioral path 和 boot failure 分类 | 当前只有 development SPI XIP、UART wiring 和部分 WDT retention 证据 | unit + firmware + SoC negative/reset simulation 通过 |
| P1 | 将每个已实现模块登记为 `IMPLEMENTED`、`BLOCK_VERIFIED` 或 `SOC_INTEGRATED`，补齐测试日志和残余风险 | 持续进行；本轮新增统一 compile 证据，D-cache NB 仍独立 WIP | 功能登记表与基线 commit、仿真报告一一对应 |
| P2 | D-cache NB 完成 CPU 接入、hazard/forwarding 和 SoC stress 后再考虑合入 | 当前仅 block verified，仍是独立 WIP | 独立 branch gate + CPU/SoC simulation；此前不得升级状态 |

### 当前阶段退出条件

1. 目标 RTL 和 behavioral model 在固定集成线可重复编译/elaborate；
2. unit、firmware、SoC/UVM 仿真覆盖正常、复位、背压、错误和超时路径；
3. 每个 gate 都有命令、日志、基线 commit 和残余风险；
4. 发布结论使用 `RTL_FUNCTIONAL_SIM_READY`，不得写成 `PRODUCT_FUNCTION_READY` 或 tapeout ready。

### 明确后置任务

真实 Synopsys PHY、TSMC PDK/DDR IO、精确 DRAM 型号、package parasitic、板级 SI/PI/timing、
综合、STA、PPA、lint、CDC/RDC、formal、gate-level simulation 和 tapeout signoff 均移至后续阶段；
它们不阻塞当前 RTL 前端交付，但在产品 ASIC DDR4 入口前必须重新打开并签收。
