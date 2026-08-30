# SoC 功能完整性计划

> 版本：v1.47（2026-08-06）
>
> 当前目标：建立一条可复现、可审计的 RTL 实现与功能仿真验证主线。本文只覆盖 RTL 编写、前端编译/elaboration、unit/firmware/SoC/UVM 仿真及其功能证据。

## 1. 完成等级

每项功能必须逐级推进，禁止直接把块级通过标成 SoC 完成：

1. `IMPLEMENTED`：RTL 已提交，接口和非目标已写入 spec。
2. `BLOCK_VERIFIED`：块级 directed/negative/reset 测试通过。
3. `SOC_INTEGRATED`：接入产品 SoC，firmware 和 SoC UVM 通过。
4. `CONTRACT_CLOSED`：多 seed、错误路径、复位/背压、scoreboard、功能覆盖率和当前契约签收通过。
5. `PRODUCT_FUNCTION_READY`：不属于当前 RTL/仿真交付目标。

`CONTRACT_CLOSED` 仅表示当前文档化 RTL contract 的仿真证据闭合。

### 2026-08-29 opt-in L1 SYNC drain barrier

`SYNC` is now decoded to a private maintenance encoding and is accepted by the
opt-in L1 only after its MSHRs, response FIFO, writeback queue, and line-port
request are idle. The blocking dcache treats the encoding as an ordered no-op,
preserving the default path. `make l1-nonblocking-sync-gate`,
`make cpu-cache-tag-gate`, the CACHE/SYNC decoder gate, and isolated
`make rtl-frontend-compile` pass. This closes only
the bounded L1 drain contract; OS cache ABI, multicore ordering, and complete
MIPS memory-model compliance remain open.

### 2026-08-30 blocking MEM/IRQ precision directed slice

`make cpu-irq-mem-pending-gate` passes a direct `mips_cpu` test which accepts
the data address, delays the blocking load response for four cycles while IP2
is asserted, and proves that the interrupt is not accepted while the request
is live. The same run observes one architectural writeback of the load value
and a later interrupt acceptance. The gate is included in
`current-contract-signoff`; it closes this handshake slice only and does not
close Linux userspace boot, arbitrary reset-in-flight behavior, or full
exception recovery.

## 1A. 当前交付边界：RTL 前端

本阶段的明确目标是 **RTL 功能编写、前端编译/elaboration 和功能仿真**。
当前交付等级使用以下两个 gate：

1. `RTL_FRONTEND_COMPILE_READY`：目标 RTL、接口、参数和仿真模型可重复编译并完成 elaboration。
2. `RTL_FUNCTIONAL_SIM_READY`：块级和 SoC behavioral simulation 覆盖正常、复位、背压、错误和软件驱动路径。

本阶段包含：

- RTL 的功能实现和接口契约；
- 按冻结协议契约实现 DDR4 controller RTL；旧 behavioral 文件只作为历史对照，不是交付目标；
- unit test、firmware test、SoC/UVM behavioral simulation；
- reset、timeout、backpressure、非法输入和错误响应验证；
- 每项功能的 commit、测试命令、日志、功能覆盖率和残余风险登记。

本阶段不包含，也不作为当前 gate 的前置条件：

- 与 RTL/仿真无关的外部实现输入不属于当前功能计划。

## 1B. 冻结默认 RTL 功能基线（2026-08-03）

当前 `integration/function-contract` 的默认配置冻结如下；所有默认回归必须使用这组
配置，其他模式必须显式标注为 opt-in gate：

| 配置项 | 冻结默认值 | 说明 |
|---|---|---|
| L2 | blocking write-through (`SOC_L2_CACHING`，不定义 `SOC_L2_WRITEBACK`/`SOC_L2_NONBLOCKING`) | reset-safe 默认产品路径；WB/NB 仅做独立 gate |
| QSPI | x1 (`ENABLE_QSPI_QUAD=0`) | `soc_top`、`mips_soc`/legacy 和 UVM 默认 x1；quad 通过显式参数单独验证 |
| DDR4 | DDR4 协议级 controller RTL | 只验证 controller 的协议、AXI/APB、refresh、错误和 reset 行为 |
| CPU/MMU | bare-metal/development boot；`SOC_MMU_ENABLE=0` 默认 | 产品 MMU 使用 `SOC_PRODUCT_BOOT_ENABLE=1`、`SOC_MMU_ENABLE=1` 的独立 directed gates；不承诺 Linux/kernel boot |

当前 HEAD 的可复现证据命令：

```text
make rtl-frontend-compile
make soc-smoke
make phase3-complete
```

上述命令的日志和报告必须记录当前 commit；`L2_WRITEBACK=1`、`L2_NONBLOCKING=1`、
`ENABLE_QSPI_QUAD=1` 和产品 MMU 只允许作为显式 opt-in gate，不得覆盖默认 baseline。

## 1C. 一页执行看板（当前唯一有效计划）

只看本节即可判断进度；后面的长表是历史证据和追溯记录。

| 阶段 | 目标 | 状态 | 下一动作 | 完成标志 |
|---|---|---|---|---|
| A. 默认基线 | 固定默认配置并可重复编译/仿真 | **已完成** | 变更后重跑 3 条基线命令 | `rtl-frontend-compile`、`soc-smoke`、`phase2/3-complete` 通过 |
| B. 外设行为 | UART/QSPI RTL 功能和错误恢复 | **已完成当前 RTL 范围** | 只补新失败场景 | UART、QSPI block/SoC gates 通过 |
| C. CPU/MMU 行为 | ASID、TLB、异常、kseg0 runtime、双核 CPU/IPI、coherency、page-table walker、scheduler/OS 接入 | **当前 RTL/仿真范围 CONTRACT_CLOSED** | 保持 gate 回归；Linux/完整 OS 语义、长期压力和默认产品配置选择属于后续产品工作 | 基础子集、coherency v0.1、walker block/refill、CPU hardware-walker miss/refill/retry、scheduler block/timer/IPI、CPU scheduler PC/GPR/CP0 context integration 均有通过证据；默认 SoC 关闭 opt-in walker/scheduler 是已审定配置，不是未闭合项 |
| D. 系统功能扩展 | secure boot、完整 OS、长期压力和生产级软件策略 | **不属于当前 RTL 基础 contract** | 另立 RTL/firmware 需求后再推进 | 独立 spec 和功能 gate |
| E. 功能证据维护 | 复位、背压、错误、超时、覆盖率和报告可追溯性 | **持续维护** | 每次 RTL 修改后重跑相关 gate | 报告与 commit 对应 |

### 当前只执行这 3 类工作

1. **补 RTL 功能缺口**：按当前 contract 完成功能模块、接口、异常和错误处理。
2. **补功能证据**：unit、firmware、SoC gate；每项必须有命令、结果、commit。
3. **维护默认基线**：任何 RTL 改动后重跑 `make rtl-frontend-compile`、`make soc-smoke`、`make phase3-complete`。

### 当前明确不做

secure boot、Linux/U-Boot、完整 OS、长期压力和生产级软件策略不属于当前基础 RTL contract。

## 2. 当前基线快照

| 对象 | 状态 | 处理 |
|---|---|---|
| `master@6ecbbbc` | 当前产品基线，已包含 C3 crossbar 和 Phase 4 商用模块历史 | 作为集成基线 |
| `integration/function-contract` | 唯一功能集成线；已合入 C1 4-way I-cache、boot/memory 产品契约、Boot ROM/CP0 向量切片、kseg0 runtime ABI gate、UART 外部 RX waveform gate 和 SoC RX integration gate；QSPI command/APB、vendor-neutral flash、quad pad、standalone x1/quad AXI/XIP bridge、单线 shared-pin SoC 接入、quad XIP opt-in memory path 和 quad development handoff 均在此线收敛 | 当前验证和后续产品功能变更只在此线收敛，暂不直接推入 `master`；`soc_top`、`mips_soc`/legacy/UVM 默认均为 x1，quad 仅通过 `ENABLE_QSPI_QUAD=1` 显式选择 |
| IF/I-cache response PC alignment | `44d263a` 将 IF 请求改为 `pc`，与 I-cache hit 的上一请求响应和 IF/ID 的 `pc_plus_4` 标签不一致；修复恢复 `inst_addr=next_pc` | `BLOCK_VERIFIED`：默认 prototype 路径与产品 Boot ROM 路径均验证 reset branch、delay slot、两次写回和精确分支目标；反向改回 `pc` 时定向测试失败 |
| Boot ROM reset/vector slice | 独立 64-KB AXI S4 Boot ROM、`BFC0_0000 -> 1FC0_0000` 复位取指、产品 `BEV/ERL` 复位、`BFC0_0380` 与 `EBase+0x180` 普通异常路径已实现；`SOC_PRODUCT_BOOT_ENABLE` 默认仍为 `0` | `BLOCK_VERIFIED`，并有完整 SoC directed 证据；它不是可启动的产品 boot firmware，不能升级为 `SOC_INTEGRATED` 或产品启动完成 |
| Product TLB/MMU boot slice | `SOC_PRODUCT_BOOT_ENABLE=1` 与 `SOC_MMU_ENABLE=1` 下，CPU 保留 TLB lookup miss/invalid 的来源位；miss 选 `BFC0_0200`/`EBase`，invalid 保持 `BFC0_0380`/`EBase+0x180`；最小 Boot ROM linker、BEV refill handler、wired kseg2-APB 映射、动态 DDR refill，以及复制到 SRAM 的 EBase `Mod` handler 已新增 | 完整 SoC firmware directed 通过：I-side 覆盖两个 BEV 模式的 miss/invalid，D-side 覆盖 BEV=1 miss/invalid；两个 firmware gate 覆盖 `TLBWI`/`Wired`、DTLB refill/`ERET` retry、DDR/APB，以及 EBase `Mod` precise-state 检查、`D=1` 修复和 retry。独立 `tlb_asid_policy` gate 进一步验证 4KB ASID 隔离、Global 跨 ASID、Invalid/Modified 分类；`product-kseg0-runtime-gate` 证明 MMU 开启时 stage-1 VA `0x8000_1000` 取指映射到 PA `0x0000_1000`；另有独立 IP-based vectored interrupt gate。不含完整 kseg0 runtime、cache-error 或 kernel boot，不能标为 MMU 产品完成 |
| Development manifest handoff | Boot ROM 经实际单线 SPI XIP 读取固定 64-byte `SOC1` development manifest，CRC32 校验后把 stage-1 拷贝至 Boot SRAM 并跳转 `0x8000_1000`；MMU-enabled slice 额外确认 kseg0 入口取指 `0x8000_1000 -> 0x0000_1000`，stage-1 在 `0x8000_7000/0x8000_7004` 写入并读回数据，分别映射到 `0x0000_7000/0x0000_7004`；runtime-depth slice 进一步覆盖 20 个连续字、跨三条 cache line 的写读回和 `0x8000_8000` 栈访问；runtime-layout slice 新增 kseg0 `.rodata=0x8000_1100`、初始化 `.data=0x8000_1110`、显式清零/读回 `.bss=0x8000_1120..0x8000_112f` 及 linker stack top `0x8000_8000`（实际栈访问 `0x8000_7ff0`）；同时修复 SPI 读相位、MMU C=2 D-cache 属性路由和长路径镜像截断 | 完整 SoC directed gate 覆盖有效镜像，及 11 条单字段 header/CRC 失败镜像；runtime-depth 与 runtime-layout gate 均不预加载 SRAM、不使用 `axi_flash_image_model`，观察 kseg0 VA->PA 数据访问、区域读写和栈读回；均可由独立 Make target 重跑 | 仍为 `BLOCK_VERIFIED` 的 development boot 与有限 kseg0 runtime data-path 子集。runtime-layout 只证明一个 freestanding linker/初始化切片，不代表完整 runtime linker、cache maintenance、SoC page-table allocator/shootdown/ASID 压力、签名、QSPI 写擦/四线、DDR 软件交接、boot-status/WDT 或生产 ROM artifact |
| Kseg0 runtime loader ABI slice | 新增独立 runtime image：Boot ROM manifest/CRC 后搬运 stage-1；kseg0 runtime 复制 20-word exception handler 到 `EBase+0x180`，重定位 `.data` 指针到 `0x8000_1670`，清零/读回 `.bss=0x8000_1680..0x8000_168c`，并验证 heap `0x8000_7000/7004`、stack `0x8000_7ff0`、I-cache index tag maintenance、`syscall`/`ERET` | `make product-kseg0-runtime-abi-gate PRODUCT_KSEG0_RUNTIME_ABI_DIR=build/unit_tb/product_kseg0_runtime_abi`：PASS；无 SRAM preload、真实 SPI `0x03` XIP、CRC、kseg0 execution 和所有 ABI mailbox/assertion 通过。最终 payload `0x320` (800 bytes)，`stage1_runtime.bin` SHA256 `2baccdd04f36c69c413fe23d4971b980e2e230b9a962d46a1c2fe201e69a5f12`，flash image SHA256 `a3dae9449697172bf74e642980fda0de2f64902037292bfe77545e7e42adf84b` | `BLOCK_VERIFIED` 的单镜像 runtime ABI 功能切片，不是完整商用 loader：尚未覆盖 PIC/GOT/TLS、多段镜像/权限、未对齐/原子访问、嵌套异常、真实 allocator/page-table、签名/ECC、QSPI 写擦、DDR 软件交接 或 kernel/OS boot；RTL load-use 修正 `.fw_mem_val = mem_mem_read ? mem_rdata_fmt : mem_ex_out` 已由该 gate 覆盖 |
| XIP controller stall / bus error | 产品单线 `axi_spi_flash` 和 opt-in quad `qspi_axi_xip` 的 read AXI 通道均由 `axi_read_timeout_guard` 包装，默认 512 cycles 内必须完成下游 `ARREADY` 和每个下一拍 `RVALID`；超时返回 `SLVERR`、延迟 response drain 后恢复。uncached response 透传为 IBE/DBE；cached refill/writeback 通过独立 sideband 透传为 CacheErr (ExcCode=30)；Boot ROM 当前仍记录 DBE/IBE `DEAD_B007`；APB `0x4000_5000` 提供版本、controller-present、timeout sticky 和最后错误码，并支持 W1C。现有单线 AXI XIP 与 APB command 已由 `qspi_shared_pin_arbiter` 在 SoC 内共享接口；command engine 另有 reference-clock timeout、CTRL abort/disable、W1C 和 WDT/reset-in-flight recovery；`ENABLE_QSPI_QUAD=1` 通过 `soc_memory_subsystem` 接入同一 S2 memory path | guard unit 覆盖 AR/R timeout、late drain、恢复和 sticky；qspi status integration gate 覆盖 guard-to-APB decode、错误分类和 W1C；完整产品 manifest gate 以 4-cycle guard 验证 DBE 到 `DEAD_B007`；I/D cache error unit 与 CPU CacheErr/ERL directed gate 均通过；`qspi-cmd-behavioral-gate`/`qspi-status-integration-gate` 另覆盖 command timeout、abort、WDT reset；`qspi-axi-xip-gate`、`qspi-axi-xip-quad-gate` 和 `qspi-soc-memory-quad-xip-gate` 覆盖 x1/quad bridge 及 SoC S2 memory path 的 AXI 单拍/两拍 burst、ID/RLAST/RRESP、command sequencing、flash readback、写拒绝和 idle pins；SoC smoke 覆盖默认单线 XIP 读 | 已达到有限 `SOC_INTEGRATED` 的单线 AXI XIP + APB command arbitration，以及 vendor-neutral quad AXI/XIP opt-in memory integration |
| `phase-c2-l2-nonblocking@fcfc9c1` | 比 `master` 多 7 个提交；含已独立提交的 JTAG、firmware、gate 与本计划修复 | 已是集成线父线；L2-NB、ROB、DDR placeholder 的产品状态仍须分项判断 |
| `phase-c1-icache-4way@d695cb5` | 已由 merge commit `8b3dc6b` 合入集成线 | 保留为历史分支，不再重复 merge |
| `phase-c3-axi-crossbar`、`phase4-dut-block-commercial-closure` | 已为 `master` 祖先 | 只保留历史引用，禁止重复合并 |
| D-cache NB WIP（已废弃） | `dcache_nb.v`、对应 TB、spec/roadmap/checklist、gate 和 coverage WIP 已从当前工作区移除；`feature/dcache-nb-stage3` 已删除 | 不属于当前产品 baseline；保留阻塞式 `rtl/cache/dcache.v` 作为 D-cache 功能基线，不再安排 CPU/SoC 接入或合入 |
| 本轮功能修复/验证改动 | JTAG `7f74345`、firmware `1288681`、gate 隔离 `324d663`、原始计划 `fcfc9c1` 已分别提交 | 已进入集成线父线；不再与 D-cache NB WIP 关联 |
| Coverage 生成工件 | fresh current-contract VDB 上的 exclusion refinement 收敛，审计当前为 432 条规则；strict URG metadata hygiene 已由 fresh per-VDB/per-metric gate 闭合 | 生成工件仍不作为整体百分比 signoff；每次新 VDB 必须重跑 `make coverage-strict-clean-gate` |
| `stash@{0}` | C3 遗留 WIP，含旧 fabric/coverage 变更 | 审计后 apply 或归档，禁止盲删 |
| 最新 full signoff | fresh current-contract 功能阶段和 10-seed stress 全部通过；最终仍失败于 99% coverage threshold（UVM SCORE 61.74%，product SCORE 59.70%） | 当前 RTL/simulation contract 可发布为 `CONTRACT_CLOSED`；整体 coverage 百分比和产品级扩展仍单独跟踪 |

### DDR4 RTL 功能状态

当前 DDR4 范围只包含协议级 controller RTL 和功能仿真。`axi_ddr4_controller`
已接入 SoC S3，覆盖 AXI burst、地址/4KB 检查、open-row 调度、refresh、reset、
错误响应和命令观测。controller、fabric、SoC smoke 和前端编译均有可重跑证据。
controller、协议 checker、AXI/APB 错误路径和 burst/refresh 压力场景均有可重跑证据；
后续只在 RTL contract 变更时补充对应 gate，不引入功能计划之外的外部实现任务。

## 3. 商用 SoC 功能判断

**结论：当前项目不是功能完整的商用 SoC。** 它已经具备可执行的 MIPS32 原型 SoC、一套通过的当前 RTL 契约回归，以及有限的 UART/QSPI/MMU/DDR behavioral SoC 集成切片；但产品级 boot、真实主存/PHY、secure boot 和系统软件入口尚未闭合。块级 RTL 存在或 unit test 通过均不能替代该结论。

| 域 | 当前产品集成 | 已有测试证据 | 商用功能结论 |
|---|---|---|---|
| CPU/CP0 | 已接入；默认 `SOC_MMU_ENABLE=0`；产品模式区分 CacheErr、TLB miss refill、invalid/general、IP-based vectored interrupt 和 opt-in VIC/VEIC source vector 的 BEV/EBase 向量 | smoke 与 Phase 3A/3B CPU/CP0 gate 通过；CP0 timer/TLB 单测验证 `IV/VS`；产品 directed 覆盖 I-side BEV=1/0 miss/invalid、D-side BEV=1 miss/invalid、EBase `Mod` precise state/recovery、CacheErr `ExcCode=30`/`ERL`/`ErrorEPC`/`EBase+0x100`、软件 IP-based vector，以及真实 VIC source 8 -> Cause.IP2 -> `EBase+0x300`；`product-cacheerr-gate` 还覆盖真实 MMU/D-cache/APB SLVERR 到 handler/ERET；新增产品启动 I-cache 首笔 `SLVERR` -> `BFC0_0100`/`1FC0_0100` -> `ERET`/ErrorEPC 重取 gate | refill/invalid、最小 kernel-mode `Mod` recovery、CacheErr hardware contract、复位时 ERL=1 的首个 CacheErr ErrorEPC 捕获、注入式 production handler/recovery 和有限 EIC/VEIC source-vector slice 已验证；ECC/多级 cache recovery、完整 Modified policy、ISA reference/compliance 和 MMU 产品启动仍未闭合 |
| L1 cache | 阻塞式 D-cache 在 DUT；4-way I-cache 已合入 `integration/function-contract` | D-cache unit、`cache_sweep` 与 smoke 通过；IF/I-cache response-PC 的默认和 Boot ROM reset-branch directed tests、合入后 unit gate `10/10`、SoC smoke 和 seed 10 UVM stress 通过；`mips_core` CPU/AXI execution gate 覆盖六个同 set tag 的 refill/eviction、普通模式 `SLVERR`/CacheErr/ERL、产品启动首笔 `SLVERR`/vector/ERET retry，以及 320-line/5-tag-per-set/3-pass AR-backpressure stress；2026-08-09 parity unit 与五个 CPU I-cache gate 重跑通过 | I-cache parity 仅为仿真注入/CacheErr contract，不宣称硅上 ECC 或完整 OS cache ABI；此前动态二维 memory `force/release` 导致 VCS OOM，已由显式注入端口替换并确认无异常内存增长 |
| L2 cache | 默认 write-through L2 已接入；write-back 为 opt-in | L2 unit、L2 firmware、Phase 2/3 与 smoke 通过 | 当前 blocking L2 契约可用；不具备 coherency/ECC/生产性能闭合 |
| AXI fabric | C3 crossbar 已在 `master`；DDR 是 S3 slave；bounded RID/BID response matching 已接入 | fabric unit `5/5`（含 `tb_xbar_ooo`），Phase 2/3、10-seed stress 通过 | cross-slave 并发与 bounded 不同 ID 乱序已验证；端到端同一 slave 仍受单 outstanding L2/APB/flash 限制 |
| DMA | 已接入 APB/AXI | DMA unit、DMA firmware、DMA copy/IRQ UVM 通过；grant stability 修复已在 C2 集成父线 | 当前 direct-copy/IRQ 契约有证据；不可宣称 IOMMU/coherency 或完整系统 DMA 生态 |
| VIC/interrupt | 已接入 CPU 单 IRQ 线，源为 UART RX/TX、TIMER/DMA；CPU 侧支持按 `Cause.IP` 的 `Cause.IV/IntCtl.VS` 向量，`ENABLE_VEIC=1` 时支持 VIC source ID 向量 | VIC unit、VIC firmware、PIC mask UVM、IP-based vectored-interrupt SoC gate、真实 VIC source 8 -> IP2 -> VEIC vector SoC gate、四级优先级嵌套 unit gate 和 UART 外部 RX SoC gate 通过 | mask/active、CPU IP-based vector、UART RX source、四级 bounded 抢占和有限 EIC/VEIC source-vector contract 已验证；任意深度 OS 嵌套、外部 EIC/VEIC policy、全源 CPU/OS ABI 和完整 MIPS compliance 仍未闭合 |
| UART | `apb_uart_16550` 已接入 APB；`soc_top` 已暴露 UART TX/RX、RTS/CTS、DTR/DSR、DCD/RI 接口；PIC bit0 为 RX-specific IRQ，bit1 保留历史 aggregate IRQ 语义；legacy/UVM 配置仍可关闭接口 wiring | UART unit、UART CPU loopback gate、block aggregate `10/10`、`uart-external-rx-gate`、`uart-external-rx-soc-gate` 和 `uart-pad-wrapper-gate` 通过；UART unit Case 17 覆盖 FIFO 水位 4 的 auto-RTS 撤销/恢复；SoC gate 由 firmware 配置 FIFO/IER/VIC，testbench 注入异步 8N1 `0x5A`，CPU 读取 RBR 并确认 RX IRQ 清除 | 已达到 `SOC_INTEGRATED` 的 behavioral RX/TX/CTS/auto-RTS slice 和 vendor-neutral interface boundary |
| DDR | S3 已替换为 `axi_ddr4_controller` 协议级 RTL；内部包含初始化、ACT/READ/WRITE/PRE、open-row hit/miss、refresh、完整 AXI burst/4KB/地址检查、背压和错误响应；opt-in status 配置接入 SECDED 纠错/双 bit 检测状态，并路由 `ddr4_fatal_error || ddr4_ecc_uncorrectable_error` 至 PIC source 5 | `ddr4-controller-gate`、`ddr4-controller-stress-gate`、`ecc-secded-gate`、`ddr4-status-gate`、`ddr4-pic-integration-gate`、`fabric-unit-gate`、`soc-smoke` 和 `rtl-frontend-compile` 通过；controller gate 覆盖四 beat 读写、row hit、row miss 的 `PRE->ACT`、command pulse 顺序、非法地址/跨 4KB burst、错误 WLAST、reset flush、DECERR、refresh 背压/恢复；APB `0x4000_6000` status slice 覆盖 correctable/uncorrectable 分类与 W1C；`ddr4-pic-integration-gate` 覆盖 PIC source 5 raw/masked/CPU IRQ 与 APB status/W1C | 当前达到 `RTL_FUNCTIONAL_SIM_READY` 的 vendor-neutral controller 与 PIC IRQ escalation contract；DDR4 controller、ECC/APB status 与 PIC source 5 IRQ 范围已验证，物理 DRAM ECC timing、多 rank、低功耗状态和完整软件启动仍是明确边界 |
| Flash/boot | `axi_spi_flash` 支持默认单线 SPI read XIP；独立只读 Boot ROM 已作为 S4 接入产品配置。产品 XIP read 以 AXI guard 限时，uncached 非 OKAY response 经 CPU 转 IBE/DBE，cached refill/writeback 错误经 CacheErr sideband 转 ExcCode=30；开发 Boot ROM 可读取 manifest/payload、CRC 校验、拷贝 Boot SRAM 并转交 kseg0 stage 1。`qspi_apb_integration` 已接入外设 APB；`qspi_shared_pin_arbiter` 统一 command 与 memory owner。新增 `soc_memory_subsystem.ENABLE_QSPI_QUAD=1` opt-in 将 vendor-neutral `qspi_axi_xip` 接入同一 S2 AXI memory path、guard 和四线边界，默认仍保持 x1 | Boot ROM、XIP guard、CacheErr/ERL、manifest/CRC、command timeout/abort/WDT、x1/quad standalone bridge、SoC APB quad command、SoC S2 quad memory gate、quad endian ABI、quad no-preload manifest handoff、flash endpoint、SoC smoke 和 RTL frontend `3/3` 均有通过证据；manifest invalid 与 XIP bus/timeout 现分别写入 always-on boot-status `0xB0070003`/`0xB0070004`，并由 no-preload gate 检查；S2 gate 覆盖单拍/两拍 burst、ID/RLAST/RRESP、quad flash readback、AXI write `SLVERR` 和 idle pins；quad handoff 覆盖有效镜像、11 个 header/CRC 负例和 timeout-to-DBE | 当前可声明有限 `SOC_INTEGRATED` 单线 XIP/APB slice、vendor-neutral quad AXI/XIP opt-in memory integration、development boot handoff 和两类 failure-code mapping |
| MMU/TLB | RTL 与 unit TB 存在，默认关闭；产品 opt-in 具备 CacheErr、refill/invalid vector routing、最小 Boot ROM kseg1 linker、BEV refill handler、wired kseg2-APB map，以及复制到 SRAM 的 EBase `Mod` handler | MMU/CP0 unit、`make tlb-asid-policy-gate`、`make tlb-os-context-gate`、`make product-mmu-asid-context-gate`、`make product-mmu-process-pressure-gate`、`make product-mmu-pagemask-gate`、`make product-mmu-context-cpu-gate`、`make tlb-invalidate-gate`、`make cpu-cache-error-gate`、`make product-cacheerr-gate`、完整 SoC I/D vector directed、`make product-mmu-boot-gate` 和 `make product-mmu-ebase-modified-gate` 通过；ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified；OS-context gate 覆盖软件页表 walk、同 VA 不同 ASID/PFN、wired global 保留、非 wired flush 和 1..255 回卷；SoC gate 覆盖真实 firmware 的 ASID 1/2 映射、mailbox page/ASID shootdown、wired APB 保留和重新 refill；process-pressure gate 覆盖 ASID 1..4 round-robin、四个 PFN 隔离、动态清空后的 8 次 refill 和 wired 映射保留；PageMask gate 现覆盖真实 CPU/DDR behavioral path 的 4KB/16KB/64KB/256KB demand-refill/data-access、even/odd halves、非零页内偏移 PFN folding、ASID 和 TLB mask/PFN；后者覆盖 DTLB `Mod`、CP0 precise state、EBase handler relocation、`D` bit repair 和 `ERET` retry；`product-cacheerr-gate` 覆盖 cacheable kseg2 APB refill、AXI SLVERR、`Cause.ExcCode=30`、ERL/ErrorEPC、单次 handler marker 和 ERET；IP-based 和真实 VIC source-vector gate 均通过 | 最小 BEV 启动、4KB/16KB/64KB/256KB ASID/异常分类、软件管理 TLB context-switch/shootdown、真实单核 mailbox TLB invalidation/refill、bounded 4-ASID process-pressure、CacheErr hardware contract、注入式 handler/recovery、单一 EBase `Mod` recovery、CPU vector table 和有限 EIC/VEIC source-vector slice 已有证据；完整 kseg0 runtime、SoC page-table allocator、scheduler/多进程长期压力、真实多核 TLB shootdown IPI、ECC policy、kernel/OS boot、硬件 walker 的 4KB-only OS contract 仍未闭合 |
| WDT/clock/reset | `apb_wdt` 已映射到 APB `0x4000_7000`；到期产生一次性 `wdt_reset`，`mips_soc_impl` 以 `soc_rst_n = rst_n & ~wdt_reset` 复位 SoC；WDT 与 boot-status 均留在 always-on 域 | WDT unit、boot-status unit、外设子系统 AXI/APB retention gate、默认 SoC smoke、预加载 firmware retention 和无 SRAM preload 的 Boot ROM WDT failure gate 均通过；gate 验证 wired APB map、stage/failure、POR|WDT cause 和第二次 Boot ROM 入口 | APB/reset、stage/failure retention 和软件/Boot ROM reset path 已有证据；由 manifest/QSPI/DDR 真实故障触发的失败分类、外部系统 reset 观测和量产 ROM 仍未闭合 |
| Debug/JTAG | 产品 top 接入 JTAG | JTAG reset-recovery UVM 与合入后 seed 10 bus stress 通过；AXI payload 锁存修复为 `7f74345` | 当前仿真功能可用；产品级 debug security/authentication 和量产工具链仍未定义 |

本轮 QSPI failure/reset 语义已单独关闭：command `TIMEOUT`（非零 reference-clock
budget）、CTRL[2]/清 enable abort、timeout/abort W1C、standalone AXI command-error
到 `SLVERR`，以及外部/WDT reset-in-flight 的 `CS_N=1/SCLK=0/MOSI=0` pin-safe
恢复均有 block 或 SoC-peripheral gate。该结论只提升当前单线/shared-pin slice 的
功能完整性，不改变“非商用 QSPI/非 production boot”的总体判断。

## 4. 唯一集成与合并计划

当前不得直接向 `master` 混合提交。按下面顺序建立唯一集成线：

| 变更集 | 文件范围 | 当前状态 | 处理规则 |
|---|---|---|---|
| `fix(jtag-axi-contract)` | `rtl/perips/jtag_debug_top.v`、`tb/uvm_tb/checkers/axi_protocol_checker.sv`、`tb/uvm_tb/tb_top/tb_top.sv` | commit `7f74345`；seed 10 stress 已通过 | 已进入集成线父线，不与 firmware 或 cache WIP 混合 |
| `test(firmware-failures-and-div)` | `tb/soc_test/fw/tests/mdu_cpu/main.c`、`tb/soc_test/fw/tests/soc_smoke/main.c` | commit `1288681`；mdu_cpu DIV 与 smoke 已通过 | 已进入集成线父线；保留 raw `div` 指令和 failure mailbox 语义 |
| `test(clean-run-gates)` | 四个 `tb/uvm_tb/run_phase*_complete.sh` | commit `324d663`；`bash -n` 与 Phase 2 hardened run 通过 | 已进入集成线父线；这是证据可复现性修复，不是 RTL feature |
| `feat(dcache-nb-stage3)`（已废弃） | 原 `dcache_nb` RTL/TB、D-cache spec/roadmap/checklist、gate 与 coverage WIP | 历史 block gate 曾报告 `9/9`，但该实现未接入 CPU/SoC，现已删除源码、TB 和本地 WIP；feature branch 已删除 | 不再保留或合入；产品默认路径只使用阻塞式 `dcache.v` |
| `docs(functional-readiness)` | `docs/functional_completeness_plan.md` | `fcfc9c1` 为初版；本次集成证据以独立文档提交记录 | 文档不与 RTL feature 或 D-cache NB WIP 混合 |
| `coverage-generated-artifacts` | `tb/coverage/exclusion_manifest.json`、`product_exclusions.el`、`uvm_exclusions.el` | 自动生成；fresh VDB refinement 和 exclusion audit 通过，规则数随 VDB 变化；strict URG metadata gate 仍是独立验收项 | 不把生成工件当作整体 coverage 百分比 signoff；新 VDB 必须通过 strict gate 后才可用于证据 |

1. 已冻结并分类：已废弃的 D-cache NB WIP、JTAG/firmware/gate commits、coverage 生成工件和文档彼此隔离；D-cache NB 不再进入后续集成。
2. `integration/function-contract` 已从 `phase-c2-l2-nonblocking@fcfc9c1` 建立。C2 的 L2-NB、ROB skeleton、DDR placeholder、MMU 脚手架和 DMA 修复仍按产品接入状态分项判断，不能整体标记为“商用缓存/DDR/MMU完成”。
3. `phase-c1-icache-4way` 已以 `8b3dc6b` 合入；人工合并的文档和 unit gate 已通过 `bash -n` 及合并后 unit gate `9/9`。同一基线的 SoC smoke 与 seed 10 UVM stress 均通过。
4. JTAG AXI payload 锁存、protocol checker bind/packing 与 firmware failure-mailbox 已作为独立 commit 固化，并在集成基线重复 seed 10 bus stress。
5. D-cache NB 已从工作区和 `feature/dcache-nb-stage3` 移除；当前产品基线继续使用阻塞式 `dcache.v`，不依赖 hit-under-miss 优化。
6. `phase-c3-axi-crossbar` 与 `phase4-dut-block-commercial-closure` 均已是 `master` 祖先，只归档引用，禁止再次 merge。`stash@{0}` 只审计、不删除；其内容不进入集成线，除非被拆成可验证主题。

退出条件：存在一个干净的 integration branch；每个 WIP 有唯一主题与 commit 归属；每个已合入功能都有同一基线上的 block/firmware/SoC 证据。

## 5. 执行顺序

### Phase 0：状态冻结

- 以 `master@6ecbbbc` 建立唯一集成线；每个主题功能使用独立分支或提交。
- D-cache NB WIP 已废弃并移除；不再保存、恢复或接入 `mips_soc`，当前默认路径使用阻塞式 `dcache.v`。
- 对每项功能登记：spec、RTL commit、块级日志、firmware 日志、UVM 日志、coverage 报告和残余风险。
- 对旧分支和 stash 做一次归档决策，完成前不删除任何引用。

退出条件：工作区状态可解释，所有 WIP 都有归属，集成基线唯一。

### Phase 1：当前 RTL 契约恢复

本阶段按当前范围只要求 RTL 编译/elaboration、unit/firmware/SoC 仿真和
DDR4 controller RTL 协议 gate。`phase2-complete`、`phase3-complete`、
`phase3b/3c-complete` 及 `current-contract-signoff` 属于后续扩展回归；其中的
coverage threshold 不属于当前退出条件。

按以下顺序执行，任何一步失败都停止向后推进：

1. `make rtl-frontend-compile`
2. `make firmware`
3. `make ddr4-controller-gate`
4. `make dut-block-unit-gate`
5. `make fabric-unit-gate`
6. `make soc-smoke`
7. `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix`
8. `make phase2-complete`
9. `make phase3-complete`
10. `make phase3b-complete` 和 `make phase3c-complete`
11. `make current-contract-signoff`

Phase 1 当前关闭条件是：RTL compile/elaboration 成功，seed 10 无 checker/scoreboard/error，
DDR4 controller RTL 的协议 gate 通过，并生成可追溯的 unit/firmware/SoC 仿真报告。full signoff
和 coverage threshold 延后，不阻塞 `RTL_FUNCTIONAL_SIM_READY`。

本轮起始基线 `b77898e` 已满足 `RTL_FRONTEND_COMPILE_READY`，并已具备
`RTL_FUNCTIONAL_SIM_READY` 所需的 unit、firmware、SoC/UVM、Boot ROM/MMU、
XIP/WDT/UART、ASID context-switch 和 DDR4 controller 行为证据。
这不是 `PRODUCT_FUNCTION_READY`；完整 runtime/page-table、ECC policy、嵌套/全源 EIC、生产 QSPI 和软件错误策略仍未闭合。

### Phase 2：产品启动与主存闭合

- 已建立 `docs/boot_memory_contract.md` v1.6，冻结 reset/vector、地址图、镜像格式、失败行为和六个行为 gate；DDR4 controller RTL 的 AXI/APB/error contract 已由 `docs/block_specs/ddr4_spec.md` 冻结，`soc_config.vh` 固化 `SOC_APB_DDRCTRL_BASE` 及寄存器 offsets。该动作只关闭接口歧义，不替代 RTL gate。
- 第二至第十五个 RTL/firmware 垂直切片已完成：TLB lookup miss 与 matching-invalid 的 vector 分派覆盖 I-side 两个 BEV 模式和 D-side BEV=1；最小产品 Boot ROM linker/BEV refill handler 进一步覆盖 wired kseg2-APB 映射、DTLB refill、`TLBWR`、寄存器恢复、`ERET` retry、DDR store/load 和 APB write；独立 ASID gate 覆盖 4KB 非 Global 隔离、Global 跨 ASID、Invalid/Modified 分类以及同一 index 的 `0xfe -> 0xff` replacement/旧 ASID 隔离；新增 OS-context gate 以真实 `mips_tlb + mips_mmu` 验证软件页表查找、同一 VA 在两个 ASID 下的不同 PFN、wired global 保留、非 wired 清空和 8-bit ASID 1..255 回卷；独立 gate 还证明 Boot ROM 把通用 handler 复制到 SRAM `EBase+0x180`，处理 precise `Mod`、将 `D=0` 改为 `D=1` 并 `ERET` retry；IP-based `Cause.IV/IntCtl.VS` 及真实 VIC source-8 -> IP2 -> VEIC `EBase+0x300` gate 均已通过；development manifest gate 则经实际 SPI XIP 完成 CRC 校验、Boot SRAM 拷贝和 kseg0 stage-1 handoff，`product-kseg0-runtime-gate` 在 `SOC_MMU_ENABLE=1` 下确认入口取指 `0x8000_1000 -> 0x0000_1000` 和一次数据访问 `0x8000_7000 -> 0x0000_7000`；新增 runtime ABI gate 进一步覆盖可重定位 `.data`、`.bss` 清零/readback、heap、stack、20-word exception handler relocation、I-cache index tag maintenance 与 `syscall`/`ERET`；XIP guard 则将下游 AR/R stall 限时为 `SLVERR`，经 uncached cache/CPU DBE 路径由 Boot ROM 记录 `DEAD_B007`；新增 QSPI/XIP status integration gate 已证明 guard timeout 经产品 APB decode 可读出版本、controller-present、sticky timeout 和 `0x0001_0001` 错误码，并可由 W1C 清除；UART pins/IRQ slice、外部 RX waveform、SoC RX/PIC/RBR behavioral gate、WDT APB/reset path、boot-status retention、预加载 firmware reset-retention 和无 SRAM preload 的 Boot ROM WDT failure slice 已有独立 gate；`product-cacheerr-gate` 通过真实 MMU/D-cache/APB fault injector 验证 cacheable refill 的 AXI `SLVERR` 到 `Cause.ExcCode=30`、`Status.ERL=1`、精确 `ErrorEPC`、`BFC0_0100` handler marker、ErrorEPC+4/`ERET` 和成功 mailbox。当前已关闭有限向量路由、最小 BEV 启动链、4KB ASID/异常分类、软件 context-switch 子集、单一 `Mod` recovery、development handoff、有限 kseg0 instruction/data 与硬件 rollover 边界、runtime ABI 单镜像子集、AXI-side XIP stall/状态观测切片、manifest/DDR 故障到 failure code 的有限分类和有限 EIC/VEIC source-vector；完整 runtime loader/OS 语义、ECC policy、嵌套/全源 EIC/VEIC、生产 QSPI 和真实 DDR 仍不属于已闭合范围。
- 冻结 ROM boot 地址、异常向量和 firmware linker 规则；不能继续从 useg reset vector 启动。
- 当前阶段依据冻结的 DDR4 协议契约实现 controller RTL，完成 init、命令时序、refresh、AXI backpressure、reset 和错误路径仿真；controller gate、fabric gate、SoC smoke 和前端 compile 均已通过。
- `qspi_cmd_behavioral` 已通过 block gate，并由 `qspi_apb_integration` 接入 SoC APB/共享接口；`qspi-soc-quad-gate` 已关闭 vendor-neutral 四线 APB command read/write slice；standalone `qspi_axi_xip` 的 x1/quad AXI/XIP bridge 也已分别通过 vendor-neutral gate。新增 `qspi-soc-memory-quad-xip-gate` 已把 quad bridge 接入 `soc_memory_subsystem` 的 opt-in S2 path，并验证 AXI burst/response、quad readback、写拒绝和 idle pins。
- 在 Phase 2 完成前，禁止把 behavioral DDR 或 loadable flash-image 测试称为产品 boot/memory 闭合。

### Phase 3：CPU、缓存和总线功能闭合

- 4-way I-cache 已合入并完成通用 unit/SoC 证据；`mips_core` CPU/AXI execution gate 覆盖 reset 后真实取指、六个同 set tag 的 line refill、四路容量压力和后续 eviction/refill，error gate 覆盖指定 refill 的 `SLVERR` -> I-cache CacheErr -> CP0 `ExcCode=30/ERL`，产品 error gate 覆盖 `BFC0_0000`/`1FC0_0000` 首笔失败、`BFC0_0100`/`1FC0_0100` vector、精确 ErrorEPC、ERET 和重取，stress gate 覆盖 320 条 line、5 tags/set、3 passes 与 AR 背压；I-cache index TagLo ABI 也已接入并有 CPU/集成证据；parity/ECC 和更完整系统软件路径仍未闭合，不能标为 `CONTRACT_CLOSED`。
- 2026-08-09 I-cache OOM 修复收尾：`tb/unit/icache/tb_icache.v` 的 parity unit 输出 `REGRESSION_TEST_SUCCESS icache`；串行五个 CPU I-cache Make gate 分别通过，marker 为 `ar_count=7`、`ar_count=6`、`ar_count=3 boot_ar_count=2 vector_ar_count=1`、`ar_count=895 unique_lines=320 line_pc_count=960`、`ops=4 ar_count=2`。修复移除了动态二维 memory `force/release`，改为显式仿真 parity 注入端口，`mips_core` 生产实例全部 tie-off；五个 VCS gate 的最大 RSS 约 206--207 MB，未复现 OOM。该记录不引入 cgroup，也不改变其他 EDA gate 的启动方式。
- 将 C.2 变更拆成 L2-NB、ROB、DDR placeholder、DMA 修复四个可审阅主题。
- 当前 D-cache 产品路径使用阻塞式 `rtl/cache/dcache.v`；`dcache_nb.v` 及其 Stage 4 CPU/ROB 接入计划已废弃，不作为功能完整性前置条件。
- CACHE 六种 D-cache maintenance operation、I/D-cache 有限 TagLo 读写、TagHi 读写和 SYNC ordered-no-op 已有独立 CPU/block/集成证据；parity/ECC、复杂 outstanding/store-buffer 的 SYNC 语义和生产 OS ABI 仍未闭合。

### Phase 4：外设与系统软件功能闭合

- `SOC_MMU_ENABLE=1`：最小 Boot ROM kseg1 linker、BEV refill handler、wired mapping、4KB ASID/Global/Invalid/Modified policy gate、软件页表/context-switch 子集、4-ASID process-pressure、EBase `Mod` handler relocation/retry gate、stage-1 kseg0 指令交接、20-word/stack kseg0 runtime-depth gate、`.rodata/.data/.bss/stack` runtime-layout slice、runtime ABI 单镜像（可重定位 `.data`/`.bss`、heap/stack、exception relocation/ERET、I-cache tag maintenance）以及cached-refill CacheErr handler/recovery gate 已通过；CACHE 六种 D-cache maintenance op、I/D-cache 有限 TagLo/TagHi CP0 读写和 SYNC ordered-no-op 已有 CPU/块/集成证据；I-cache 已有 CPU/AXI execution/refill/eviction、普通 `SLVERR`/CacheErr/ERL、产品启动 vector/ErrorEPC/ERET retry、320-line AR-backpressure stress 和 index tag ABI slice；继续完成多段/PIC/TLS/权限与真实 allocator/page-table 语义、SoC page-table allocator/多进程压力、ECC/外部 EIC policy 和 kernel-mode firmware gate。refill/invalid 的 EBase/BEV 向量路由、CacheErr hardware vector 及 IP-based vectored interrupt 已有 directed 证据。
- CPU/CP0：补 MIPS ISA compliance 与 reference-model lockstep；现有 exception smoke 只作为子集证据。
- 外设：为已接入的 UART TX/RX/flow-control 完成 RTL 接口 mux、外部系统 gate 和端到端软件 driver；`uart-external-rx-gate` 与 `uart-external-rx-soc-gate` 已关闭 RTL/behavioral 外部波形及 SoC RX/PIC/RBR 切片；为 WDT 补无预加载 Boot ROM failure firmware、自动重启和外部系统 reset 观测；补齐 GPIO/timer 产品软件驱动。
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
- 跨时钟与复位分析
- 其他非 RTL 功能分析
- 实现/时序
- 性能评估

## 8. 当前执行点

历史 full signoff 的功能阶段均通过；本轮 strict URG metadata hygiene 已闭合，整体 coverage 百分比仍作为独立质量指标跟踪。当前执行优先级已改为
**RTL 前端编译和功能仿真**：不把实现、时序或性能评估混入当前 gate。Boot ROM/向量、
有限 MMU/TLB、SPI XIP、manifest handoff、WDT retention、UART RX behavioral path 和
DDR4 controller RTL 协议证据已按当前 contract 管理；完整 kernel/runtime、demand paging、
MESI/directory、ISA/FPU、ECC/cache-error policy、全源 EIC/VEIC、QSPI production path
和真实外部 PHY 仍未完成。**

## 9. 执行记录

| 时间 | 基线 | 命令 | 结果 | 结论 |
|---|---|---|---|---|
| 2026-08-01 | `phase-c2-l2-nonblocking@4baf139`，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_dma_fix` | FAIL：14.49 us 时 SRAM/S0 AR payload 在 `ARVALID && !ARREADY` 期间变化，14.51 us 时 `ARVALID` 提前撤销；随后 CPU memory stall 直至 watchdog | `4baf139` 未关闭该 SoC blocker。暂停 Phase 1 的后续 gate，先定位 S0 AR 驱动路径。日志：`build/uvm/seed10_dma_fix/vcs_uvm.log` |
| 2026-08-01 | 当前工作区，firmware SHA256 `6e413366bc7d91feafaba9edfa416a177f504eb225345fd2b5827a1ae387317e` | `make uvm UVM_TEST=soc_bus_stress_test UVM_SEED=10 UVM_RUN_DIR=build/uvm/seed10_jtag_payload_fix` | PASS：`REGRESSION_TEST_SUCCESS`，无 UVM error/fatal 或 `$error` | 根因是 TCK 域命令寄存器在 AXI 请求等待期间直接改变 master payload。JTAG 启动请求时锁存地址/写数据到 `clk` 域后，S0 和 JTAG master 的 AXI checker 均通过。日志：`build/uvm/seed10_jtag_payload_fix/vcs_uvm.log` |
| 2026-08-01 | 历史 D-cache NB WIP 基线 | `make dut-block-unit-gate` | 历史 PASS：MDU、DMA、VIC、UART、WDT、L2NB、D-cache、mini-ROB、D-cache NB 共 9/9 | 仅作已删除 WIP 的历史 block evidence；`dcache_nb` 未接入 CPU/SoC，不属于当前 baseline。报告目录：`build/unit_tb/dut_block_readiness` |
| 2026-08-01 | 当前工作区 | `make fabric-unit-gate FABRIC_UNIT_DIR=build/unit_tb/fabric_ddr_contract` | PASS：crossbar core、QoS、multi-outstanding、DDR 共 4/4 | DDR evidence 仅覆盖 `SOC_DDR_BASE` 映射、128-MB/FLASH 边界、behavioral read-after-write 和 unmapped `DECERR`；不覆盖 controller/接口 init/校准/refresh。独立报告目录：`build/unit_tb/fabric_ddr_contract` |
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
| 2026-08-03 | `integration/function-contract` QSPI boot-status failure-code mapping | `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_boot_status` | PASS：valid image、11 条 manifest rejection、`product_manifest_handoff_xip_timeout`；每条 failure path 均检查 boot-status 写入 | Boot ROM 对 malformed manifest 写 `BOOT_STAGE=0x20/FAILURE=0xB0070003`，对 XIP DBE/timeout 写 `BOOT_STAGE=0x20/FAILURE=0xB0070004`；testbench 通过 kseg1 APB 地址 `0xA000_8000/8004` 观察，未使用 SRAM preload 或内部 force。该切片只闭合两类 vendor-neutral failure mapping，不代表完整 production error taxonomy。 |
| 2026-08-01 | 同上 | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/xip_timeout_smoke_final` | PASS：`REGRESSION_TEST_SUCCESS`，CPU/CP0 `intr=11 syscall=1 ri=4 adel=1 eret=16` | 修复 smoke 在兼容身份映射下误用 `0xB000_0000` kseg1 flash alias，改从 fabric-visible `0x1000_0000` XIP window 读取；此前每轮的正确 DECERR/DBE 不再被误报为异常。 |
| 2026-08-01 | 同上 | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/xip_timeout_aggregate_final` | PASS：`10/10` | guard、XIP timeout manifest handoff、I/D cache error 回归及九类既有 block contract 均通过。 |
| 2026-08-01 | `integration/function-contract` QSPI/XIP status observability slice | `make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=build/unit_tb/qspi_status_integration_try3` | PASS：`REGRESSION_TEST_SUCCESS qspi_status_integration` | 先完成正常 downstream read 证明不误报，再让真实 `axi_read_timeout_guard` 的 AR stall 经产品 peripheral APB decode 读回版本 `0x51535001`、controller-present、timeout sticky 和错误 `0x0001_0001`；W1C 清除状态/错误且不误清 present。该证据只覆盖故障观测，不代表完整 QSPI controller。 |
| 2026-08-01 | `integration/function-contract` vectored-interrupt slice | `tb/unit/cp0/run.sh`、`make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/product_vectored_interrupt_try4` | PASS：`cp0_timer: PASS`、`REGRESSION_TEST_SUCCESS product_vectored_interrupt` | CP0 验证 `Cause.IV`/`IntCtl.VS`、最高 enabled pending IP7、`VS=1` 的 `0x2E0` 和最大 `VS=31` 的 `0x1D20` 偏移；完整产品 SoC 仅加载 Boot ROM、无 SRAM preload，以软件 IP1、`VS=1`、`BEV=0` 进入 `0x8000_0220`，并观察物理 `0x0000_0220` 取指及 `EXL/INT` 状态。 |
| 2026-08-01 | 同上 | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/vectored_interrupt_aggregate_final`、`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/vectored_interrupt_smoke` | PASS：block aggregate、`REGRESSION_TEST_SUCCESS` | 新 CP0/vector 接口未回归 MDU、DMA、VIC、UART、WDT、L2/L2NB、L1 cache、ROB、SPI/XIP、Boot ROM/MMU；smoke `CPU_CP0_SUMMARY intr=11 syscall=1 ri=4 adel=1 eret=16`。smoke 中的 `RI=0xA` 输出来自显式非法指令/嵌套异常 stimulus。 |
| 2026-08-01 | `integration/function-contract@c7018b7` | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit/tlb_asid_policy_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/tlb_asid_aggregate` | PASS：独立 gate `REGRESSION_TEST_SUCCESS tlb_asid_policy`，原始 8 项检查通过；Boot ROM/MMU 聚合 `10/10` | 以 `SOC_MMU_ENABLE=1` 直接连接 `mips_tlb`/`mips_mmu`；证明 4KB 非 Global ASID 隔离、奇偶页选择、Global 跨 ASID，以及 matching-invalid 的 TLBL/TLBS 和 clean-store 的 Modified 分类。该历史 gate 未覆盖可变页、multi-hit、micro-TLB 或 OS 级压力；后续 `tlb_os_context` gate 已补充软件 context-switch 边界。 |
| 2026-08-01 | `integration/function-contract` UART pin/IRQ slice | `make uart-cpu-gate SOC_TEST_UART_CPU_DIR=build/soc_test/uart_pins_gate_try1`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/uart_pins_aggregate` | PASS：UART CPU firmware gate；UART unit 检查 RX/TX IRQ 分离；DUT block aggregate `10/10` | `soc_top` 产品 wrapper 接出 UART/modem pins；PIC bit0 连接 RX-specific IRQ，bit1 保持历史 aggregate IRQ，`ENABLE_UART_PINS=0` 的 legacy/UVM tie-off 行为未改变。外部 waveform 另由下一条 gate 关闭。 |
| 2026-08-02 | `integration/function-contract` UART external RX waveform slice | `make uart-external-rx-gate UART_EXTERNAL_RX_DIR=/tmp/uart_external_rx`；`make rtl-frontend-compile`；`make uart-cpu-gate` | PASS：`REGRESSION_TEST_SUCCESS uart_external_rx`；RTL frontend `3/3`；UART CPU firmware gate PASS | 独立实例化 `apb_uart_16550`，以 divisor=1 的 16 个 SoC clock/bit 驱动异步 8N1 `A5`，检查 RBR/LSR.DR、`rx_irq`/`tx_irq` 分离和 RBR pop 清中断；再发送低 stop bit 的 `3C`，检查 `LSR.FE/RFE` 和 RX line-status interrupt。该 gate 只证明 RTL waveform、RX 错误分类和 software path。 |
| 2026-08-02 | `integration/function-contract` UART external RX SoC integration slice | `make uart-external-rx-soc-gate SOC_TEST_UART_EXTERNAL_RX_DIR=/tmp/uart_external_rx_soc3 UART_EXTERNAL_RX_FW_DIR=/tmp/uart_external_rx_fw3` | PASS：`tb_mips_soc: injecting external UART RX frame 0x5A`；firmware mailbox `REGRESSION_TEST_SUCCESS`；firmware SHA256 `adf850db84750cb435b10f385ebdfacf784acbbd48bc42475f6ca5bd48598889` | SoC firmware 将 UART 配置为 8N1/FIFO/RX IER，testbench 注入 `0x5A`；firmware 检查 `LSR.DR`、PIC raw bit0、无 `PE/FE/OE`，读取 RBR 并确认 RX source 清除。该 gate 关闭 SoC RX/PIC/RBR RTL/仿真路径。 |
| 2026-08-01 | `integration/function-contract` WDT APB/reset slice | `make wdt-unit-gate WDT_UNIT_DIR=build/unit_tb/wdt_try2`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_try1`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/wdt_compile_smoke` | PASS：`REGRESSION_TEST_SUCCESS wdt`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、默认 SoC smoke | WDT 已在 `0x4000_7000` 解码；外设 gate 通过 AXI/APB 写 LOAD/CTRL，观察一次性 reset pulse 拉低 aggregate reset 并在 reset 后读到 sticky STATUS。尚未验证 Boot ROM failure code/boot-status persistence。 |
| 2026-08-01 | `integration/function-contract` boot-status retention slice | `make boot-status-unit-gate`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=build/unit_tb/wdt_peripheral_boot_status`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/boot_status_smoke` | PASS：`REGRESSION_TEST_SUCCESS boot_status`、`REGRESSION_TEST_SUCCESS wdt_peripheral`、`REGRESSION_TEST_SUCCESS` | `0x4000_8000` 解码为 always-on APB block；`BOOT_STAGE`/`FAILURE` 在 WDT reset 后保持，`RESET_CAUSE[POR/WDT]` sticky 且 W1C。该 gate 只证明寄存器和 reset retention，不代表 Boot ROM failure firmware 已闭合。 |
| 2026-08-01 | `integration/function-contract` WDT boot-failure firmware slice | `make wdt-boot-failure-gate` | PASS：`wdt_boot_failure: REGRESSION_TEST_SUCCESS`、SoC mailbox `REGRESSION_TEST_SUCCESS` | 预加载 firmware 首次写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070001` 后 arm WDT；第二次入口读回 stage/failure 与 `POR|WDT` cause，清除状态后完成。该证据覆盖软件触发 reset/retention，不满足无 SRAM preload 的产品 boot gate。 |
| 2026-08-01 | `integration/function-contract` product WDT Boot ROM failure slice | `make product-wdt-boot-failure-gate PRODUCT_WDT_BOOT_FAILURE_DIR=build/unit_tb/product_wdt_boot_failure_try6` | PASS：`REGRESSION_TEST_SUCCESS product_wdt_boot_failure` | 不调用 `preload_sram_hex`；Boot ROM 在 `SOC_MMU_ENABLE=1` 下安装 5 个 wired APB TLB entries，写 `BOOT_STAGE=0x20`/`FAILURE=0xB0070002`、arm WDT，第二次 `BFC0_0000` 入口校验 `POR|WDT` 与保留字段后写成功 mailbox。该 gate 证明 reset/retention 软件路径，不覆盖 manifest/QSPI/DDR 故障分类。 |
| 2026-08-02 | `integration/function-contract` RTL 前端统一 compile/elaboration gate | `make rtl-frontend-compile` | PASS：default `soc_top`、`SOC_PRODUCT_BOOT_ENABLE=1 + SOC_MMU_ENABLE=1`、独立 DDR4 behavioral 共 `3/3`；报告：`build/unit_tb/rtl_frontend_compile/rtl_frontend_compile_report.md` | 当前基线的 clock/CPU/AXI/peripheral/cache/SoC RTL 均完成统一 VCS elaboration；DDR4 仍是 vendor-neutral F1 模型，不升级为外部接口/controller 证据。 |
| 2026-08-02 | `integration/function-contract` 仿真契约告警清理 | `make product-wdt-boot-failure-gate PRODUCT_WDT_BOOT_FAILURE_DIR=build/unit_tb/rtl_frontend_wdt_failure_fix2`；`make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/rtl_frontend_vectored_fix`；`make product-mmu-boot-gate PRODUCT_MMU_BOOT_DIR=build/unit_tb/rtl_frontend_mmu_fix` | PASS：三个 gate 均返回 `REGRESSION_TEST_SUCCESS`；product Boot ROM testbench 已显式 tie-off UART/modem ports；`axi_ddr_model` 无 `+FW_HEX` 时保持零初始化，不再探测不存在的默认文件 | 修复只涉及 testbench 端口连接和 behavioral model 的镜像加载诊断，不改变 `ENABLE_UART_PINS=0` 或显式 `+FW_HEX` 行为。toolchain 的 linker build-id warning 仍为非 RTL 诊断。 |
| 2026-08-02 | `integration/function-contract` MMU-enabled kseg0 data slice | `make product-kseg0-runtime-gate PRODUCT_KSEG0_RUNTIME_DIR=build/unit_tb/product_kseg0_runtime_multiword`；`make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_handoff_multiword`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/rtl_frontend_block_aggregate` | PASS：MMU-enabled handoff 的 stage-1 kseg0 instruction/data checks、valid manifest、11 个 rejection、XIP timeout 均通过；Boot ROM/block aggregate `10/10` | stage-1 在 `0x8000_7000` 和 `0x8000_7004` 写入，再从 `0x8000_7004` 读回并校验；TB 观察两个 VA->PA 映射和读回，CACHE maintenance 另有独立 unit evidence，但仍不升级为完整 runtime data mapping、OS/page-table 或 kernel evidence。 |
| 2026-08-02 | `integration/function-contract` TLB ASID rollover slice | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit_tb/tlb_asid_policy_rollover` | PASS：`tlb_asid_policy`；同一 index 的旧 `ASID=0xfe` 映射在切换到 `0xff` 时 miss，重写后新 PFN 命中且旧 ASID 继续隔离 | 关闭硬件 lookup/replacement 的最小 rollover 证据；不覆盖 OS ASID allocator、TLB shootdown、page-table walk、multi-hit 或 context-switch 压力。 |
| 2026-08-02 | `integration/function-contract` OS page-table/context-switch slice | `make tlb-os-context-gate TLB_OS_CONTEXT_DIR=build/unit_tb/tlb_os_context_try2` | PASS：`REGRESSION_TEST_SUCCESS tlb_os_context` | 以真实 `mips_tlb + mips_mmu` 建立软件页表 fixture；覆盖同一 VA 的 ASID 1/2 不同 PFN、VPN pair even/odd、wired global 映射、ASID 1..255 分配、非 wired flush 和回卷后重新填充。仍不是 Linux page-table、IPI shootdown 或 demand paging 证据。 |
| 2026-08-02 | `integration/function-contract` SoC ASID/context/shootdown slice | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/product_mmu_asid_context_try3` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | Boot ROM kseg1 firmware 在真实 CPU/CP0/TLB/MMU/DDR behavioral SoC 上以软件 PTE 为 ASID 1/2 建立同 VA 不同 PFN，切回验证旧映射；历史版本使用 `TLBWI` 清除 index 1..63，验证 wired APB 映射仍在并触发重新 refill。真实 mailbox shootdown 已在后续 gate 更新。 |
| 2026-08-02 | `integration/function-contract` CacheErr exception slice | `make cpu-cache-error-gate CPU_CACHE_ERROR_DIR=build/unit_tb/cpu_cache_error` | PASS：`REGRESSION_TEST_SUCCESS mips_cpu_cacheerr` | D-cache cached-error sideband 使用 ExcCode=30，产品模式跳转 `EBase+0x100`，CP0 置 `ERL=1`、保持 `EXL=0` 并保存精确 `ErrorEPC`；uncached DBE policy 未改变。 |
| 2026-08-02 | `integration/function-contract` CacheErr production recovery slice | `make product-cacheerr-gate PRODUCT_CACHEERR_DIR=build/unit_tb/product_cacheerr`；`make rtl-frontend-compile`；`make product-mmu-asid-context-gate` | PASS：`REGRESSION_TEST_SUCCESS product_cacheerr`、`RTL frontend compile gate: PASS (3/3)`、`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | 新增 `mips_soc.ENABLE_APB_FAULT_INJECTOR` 仅供 directed test opt-in；真实 MMU `C=3` kseg2 APB refill 遇 `SLVERR` 后进入 `BFC0_0100`，handler 校验 `Cause=30`、写 `CACE0001` marker、递增 `ErrorEPC`、`ERET` 清 ERL 并完成 mailbox。D-cache 旧 0x4/0xA 物理地址 uncached heuristic 限定为 prototype，避免覆盖产品 TLB C 属性。该 slice 不覆盖 ECC、CACHE TagLo/TagHi/SYNC、EIC/VEIC 或量产 ROM。 |
| 2026-08-02 | `integration/function-contract` CacheErr recovery integration tip | `b06bc74` (`feat: add product CacheErr recovery gate`)；block aggregate `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/dut_block_cacheerr_fix` | PASS：DUT block `10/10`；product CacheErr、CPU CacheErr、product MMU/ASID context、RTL frontend compile `3/3` 均在该 tip 重跑通过 | 当前功能线已提交；结论仍为 `RTL_FUNCTIONAL_SIM_READY`，不是 `PRODUCT_FUNCTION_READY`。ECC、完整 cache ordering、EIC/VEIC、量产 ROM、QSPI production path 和真实 DDR4 仍未闭合。 |
| 2026-08-02 | `integration/function-contract` bounded multi-ASID process-pressure slice | `1e6cd3a` (`test(mmu): add multi-ASID process pressure gate`)；`make product-mmu-process-pressure-gate PRODUCT_MMU_PROCESS_PRESSURE_DIR=build/soc_test/product_mmu_process_pressure` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8` | 真实产品 MMU/CP0/TLB/DDR behavioral SoC 验证 ASID 1..4 的同 VA 不同 PFN、正向与反向 round-robin 访问、动态槽 `TLBWI` shootdown、wired 映射保留，以及四个上下文清空后重新 refill。该 gate 不代表完整 allocator、scheduler、IPI shootdown 或长期 OS 压力。 |
| 2026-08-02 | `integration/function-contract` kseg0 runtime depth slice | `0db229a` (`test(mmu): deepen kseg0 runtime data gate`)；`make product-kseg0-runtime-depth-gate PRODUCT_KSEG0_RUNTIME_DEPTH_DIR=build/unit_tb/product_kseg0_runtime_depth`；`make product-kseg0-runtime-gate` | PASS：depth valid handoff；原有 valid、bad-CRC、11 条 manifest rejection 和 XIP-timeout regression 通过 | 新增 stage-1 depth payload 写读 20 个连续 kseg0 VA `0x8000_7000..0x8000_704C`，验证对应 PA `0x0000_7000..0x0000_704C`、跨三条 cache line、kseg0 stack `0x8000_8000 -> 0x0000_8000` 读回；仅证明 runtime data-path slice，不覆盖 `CACHE` maintenance、完整 linker/layout 或 kernel。 |
| 2026-08-02 | `integration/function-contract` CACHE maintenance slice | `make rtl-frontend-compile`；`make cpu-cache-op-gate CPU_CACHE_OP_DIR=build/unit_tb/cpu_cacheop_gate`；`vcs rtl/cache/dcache.v tb/unit/dcache/tb_dcache.v` | PASS：RTL frontend `3/3`；CPU pipeline `REGRESSION_TEST_SUCCESS mips_cpu_cacheop`；D-cache unit `REGRESSION_TEST_SUCCESS dcache` | CPU 已解码并在 MEM 阶段停住执行首批四种 `Hit/Index` maintenance op；覆盖 clean invalidate、dirty writeback、writeback+invalidate、index way/set 选择、AXI 写回背压/`SLVERR` 后 CacheErr sideband 和写回后的内存可见性。后续 TagLo/TagHi/SYNC slice 已在下一条记录补齐 `Index_Load_Tag_D`/`Index_Store_Tag_D`。 |
| 2026-08-02 | `integration/function-contract` kseg0 runtime linker/data layout slice | `make product-kseg0-runtime-layout-gate PRODUCT_KSEG0_RUNTIME_LAYOUT_DIR=build/unit_tb/product_kseg0_runtime_layout`；`make rtl-frontend-compile` | PASS：`REGRESSION_TEST_SUCCESS product_manifest_handoff_valid`；payload `288` bytes，小于 Boot SRAM stage-1 上限 `32 KiB`；RTL frontend `3/3` | 新增 `stage1_layout.ld/.s` 和独立 layout flash image；真实 SPI XIP、manifest CRC、无 SRAM preload、MMU kseg0 直映射下，TB 观察 `.rodata`/`.data` 读、四个 `.bss` word 的显式清零写、清零前读与写后读回，以及 linker stack top 派生的 `0x8000_7ff0 -> 0x0000_7ff0` 访问。修复 `%hi/%lo` 低半字 `0x8000` 的 MIPS stack 地址构造错误；该切片仍不覆盖完整 runtime ABI、page-table allocator、kernel 或 `TagLo/TagHi/SYNC`。 |
| 2026-08-02 | `integration/function-contract` kseg0 runtime loader ABI slice | `make product-kseg0-runtime-abi-gate PRODUCT_KSEG0_RUNTIME_ABI_DIR=build/unit_tb/product_kseg0_runtime_abi` | PASS：`REGRESSION_TEST_SUCCESS product_manifest_handoff_runtime_abi`；payload `0x320` (800 bytes)；`stage1_runtime.bin` SHA256 `2baccdd04f36c69c413fe23d4971b980e2e230b9a962d46a1c2fe201e69a5f12`；flash image SHA256 `a3dae944969717bf74e642980fda0de2f64902037292bfe77545e7e42adf84b` | 无 SRAM preload、真实 SPI XIP 和 MMU kseg0 execution 下，gate 检查 manifest CRC/payload handoff、`.data` 从 link `0x8000_12D0` 重定位到 `0x8000_1670`、`.bss=0x8000_1680..168c` 清零/readback、heap `0x8000_7000/7004`、stack `0x8000_7ff0`、20-word handler 到 `EBase+0x180`、I-cache index tag maintenance、`syscall`/`ERET` 和 pass mailbox。为修复 load-use forwarding，MEM-stage load 使用 `mem_rdata_fmt`，ALU 写回仍使用 `mem_ex_out`。证据等级为 `BLOCK_VERIFIED` 的单镜像 ABI slice；不覆盖 PIC/GOT/TLS、多段/权限、未对齐/原子访问、嵌套异常、真实 allocator/page-table、签名/ECC 或 kernel/OS。 |
| 2026-08-02 | `integration/function-contract` CACHE TagLo/TagHi/SYNC CPU contract slice | `make cpu-cache-tag-gate CPU_CACHE_TAG_DIR=build/unit_tb/cpu_cachetag`；`make cpu-cache-op-gate CPU_CACHE_OP_DIR=build/unit_tb/cpu_cacheop_tag_ports`；`make rtl-frontend-compile`；D-cache unit gate | PASS：`REGRESSION_TEST_SUCCESS mips_cpu_cachetag`、既有 `mips_cpu_cacheop`、D-cache unit `REGRESSION_TEST_SUCCESS dcache`、RTL frontend `3/3` | CPU directed test 覆盖 MTC0 TagLo -> Index_Store_Tag_D 的 tag write data、Index_Load_Tag_D -> MFC0 TagLo readback、MTC0/MFC0 TagHi、SYNC 不触发 RI/异常；D-cache unit 验证 valid/dirty/tag tuple 的 index load/store。该 slice 定义 D-cache TagLo bit[22:0] 和顺序 no-op 语义，I-cache tag ABI 在下一条集成记录补齐。 |
| 2026-08-02 | `integration/function-contract@0c95d71` I-cache index tag ABI slice | `make cpu-icache-tag-gate CPU_ICACHE_TAG_DIR=build/unit_tb/mips_core_icache_tag`；`make rtl-frontend-compile`；既有 D-cache/CACHE/I-cache gates | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_tag ops=2 ar_count=1`；RTL frontend `3/3`；既有 I-cache execution/stress 与 D-cache TagLo/CACHE gates 保持 PASS | `Index_Store_Tag_I=5'b01000` 和 `Index_Load_Tag_I=5'b00100` 已由 CPU 解码，经 `mips_core` I/D sideband 互斥路由到 I-cache；I-cache TagLo 定义为 bit[22]=valid、bit[21]=0、bit[20:0]=tag，操作期间 CPU 保持 stall，完成和 readback 回到 CP0；测试确认 D-cache 未接收 I op、无额外 AXI transaction、TagLo 回读正确。该 slice 不覆盖 parity/ECC、完整 SYNCI/cache ordering、复杂 outstanding 或 kernel cache ABI。 |
| 2026-08-05 | `integration/function-contract` I-cache invalidate CPU/AXI slice | `make cpu-icache-tag-gate CPU_ICACHE_TAG_DIR=build/unit_tb/mips_core_icache_invalidate` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_tag ops=4 ar_count=2` | CPU 已解码 `Index_Invalidate_I=5'b00000` 和 `Hit_Invalidate_I=5'b10000` 并路由至 I-cache。gate 先写入 index tag，再执行 index invalidate 和 index load，验证 TagLo 回读为零；随后对已缓存指令 line 执行 hit invalidate，验证 next fetch 引发第二次 line refill。I-cache maintenance 不会路由到 D-cache，也不发 AXI 写事务。完整 SYNCI/cache ordering、parity/ECC 和 OS cache ABI 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` SYNCI decode/invalidate slice | `make cpu-icache-tag-gate CPU_ICACHE_TAG_DIR=build/unit_tb/mips_core_icache_synci`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_synci` | PASS：CPU/I-cache gate `ops=4, ar_count=2`；RTL frontend `3/3` | MIPS32 `SYNCI offset(base)`（REGIMM `rt=31`）已解码为 `Hit_Invalidate_I`，沿用 I-cache maintenance stall/完成握手；gate 使用真实 `0x041f0000` SYNCI 编码，确认无 RI、无 D-cache sideband，且后续取指发生 refill。复杂 outstanding/order 和完整 OS cache ABI 仍 deferred。 |
| 2026-08-02 | `integration/function-contract` I-cache CPU/AXI execution eviction slice | `make cpu-icache-exec-gate CPU_ICACHE_EXEC_DIR=build/unit_tb/mips_core_icache_exec`；已有 D-cache/RTL frontend gates | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_exec ar_count=7` | 直接实例化 `mips_core`、真实 `icache` 和单 outstanding AXI instruction model；测试程序跳转访问 `0x0000_0000`、`0x0000_0800`、`0x0000_1000`、`0x0000_1800`、`0x0000_2000`、`0x0000_2800` 六个同 `index[10:5]` 的 tag，确认四路容量压力后的重复 AR/refill。该 slice 不覆盖完整 SoC reset/error/long-stress、I-cache maintenance/tag ABI 或 parity/ECC。 |
| 2026-08-02 | `integration/function-contract` I-cache CPU/AXI error slice | `make cpu-icache-error-gate CPU_ICACHE_ERROR_DIR=build/unit_tb/mips_core_icache_error` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_exec_error ar_count=6` | 在同一 `mips_core` execution harness 对 `0x0000_1000` refill 注入 AXI `SLVERR`，确认 I-cache `cpu_cache_error` sideband、CPU IF CacheErr 分类及 CP0 `Cause.ExcCode=30`/`Status.ERL`。该 slice 不覆盖完整产品 SoC reset/long-stress、ErrorEPC handler recovery、I-cache maintenance/tag ABI 或 parity/ECC。 |
| 2026-08-02 | `integration/function-contract` product-boot I-cache CacheErr vector/recovery slice | `make cpu-icache-product-error-gate CPU_ICACHE_PRODUCT_ERROR_DIR=build/unit_tb/mips_core_icache_product_error`；`make rtl-frontend-compile`；`make cpu-cache-error-gate CPU_CACHE_ERROR_DIR=build/unit_tb/cpu_cache_error_after_product_icache`；`make product-cacheerr-gate PRODUCT_CACHEERR_DIR=build/unit_tb/product_cacheerr_after_cp0_valid` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_product_error ar_count=3 boot_ar_count=2 vector_ar_count=1`；受影响 gate 均 PASS | 产品模式复位 `BFC0_0000` 的首笔物理 AR `1FC0_0000` 注入一次 `SLVERR`，确认 I-cache CacheErr、`Cause.ExcCode=30`、`ERL=1`、精确 `ErrorEPC=BFC0_0000`，向量虚拟/物理地址 `BFC0_0100`/`1FC0_0100` 只取一次，执行 `ERET` 清 ERL 并重取 Boot ROM。修复 CP0 `cp0_errorepc_valid`，使产品复位初始 `ERL=1` 时首个 CacheErr 仍捕获 ErrorEPC，同时避免嵌套错误覆盖；该 slice 不覆盖长期压力、I-cache maintenance/tag ABI、ECC 或量产 ROM。 |
| 2026-08-02 | `integration/function-contract` I-cache multi-set long-stress slice | `make cpu-icache-stress-gate CPU_ICACHE_STRESS_DIR=build/unit_tb/mips_core_icache_stress` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_stress ar_count=895 unique_lines=320 line_pc_count=960` | `mips_core` 运行确定性 320-line jump ring（64 sets × 5 tags/set）三轮，覆盖全部 line、四路容量后的重复 refill，并在 AXI instruction AR 通道周期性施加背压；检查 AR line alignment/len/size/burst/prot 和无死锁。该 slice 不覆盖 I-cache maintenance/tag ABI、parity/ECC、AXI R-channel fault 或长期 SoC firmware/kernel 压力。 |
| 2026-08-03 | `integration/function-contract` branch/WIP audit | `git worktree list`；`git branch -avv`；`git -C /home/admin/mips32-soc status --short` | PASS：`integration/function-contract@0205c3f` 为 clean commit；主工作区已在该 integration 分支；`feature/dcache-nb-stage3` 已删除；`master@6ecbbbc` 仍未合入该功能线；`/tmp/mips32-soc-baseline`、`/tmp/mips32-soc-smoke-preboot` 两个 detached worktree 仍存在 | D-cache NB 分支/WIP 已移除，当前功能线不依赖它；剩余分支事项是 integration 与 `master` 的后续合并决策，以及两个 detached worktree 的归档/清理，不影响当前 RTL 功能线。 |
| 2026-08-02 | `integration/function-contract` QSPI command/FIFO/quad behavioral slice | `make qspi-cmd-behavioral-gate QSPI_CMD_BEHAVIORAL_DIR=/tmp/qspi_cmd_behavioral13`；`make rtl-frontend-compile`；`make spi-flash-unit-gate SPI_FLASH_UNIT_DIR=/tmp/spi_flash_unit_qspi`；`make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=/tmp/qspi_status_qspi` | PASS：`REGRESSION_TEST_SUCCESS qspi_cmd_behavioral`、RTL frontend `3/3`、`REGRESSION_TEST_SUCCESS axi_spi_flash`、`REGRESSION_TEST_SUCCESS qspi_status_integration` | `qspi_cmd_behavioral` 覆盖 APB LUT、status `0x05` -> RX `0xA5`、RX/TX FIFO、24-bit address serialization、`0x32` x4 data、CS/SCLK、busy retrigger error、IRQ W1C 和 soft reset；状态为 `BLOCK_VERIFIED (vendor-neutral)`。不等于 `SOC_INTEGRATED`：未接 `soc_top`/AXI XIP/flash behavioral model/quad pad/接口/erase-program/boot。 |
| 2026-08-02 | `integration/function-contract` QSPI APB/SoC x1 command integration slice | `make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=/tmp/qspi_soc_integration3`；`make rtl-frontend-compile`；`make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_qspi_integration2`；`make qspi-cmd-behavioral-gate QSPI_CMD_BEHAVIORAL_DIR=/tmp/qspi_cmd_after_soc`；`make spi-flash-unit-gate SPI_FLASH_UNIT_DIR=/tmp/spi_flash_after_soc`；`make wdt-peripheral-gate WDT_PERIPHERAL_DIR=/tmp/wdt_qspi_compile` | PASS：QSPI status/command integration、RTL frontend `3/3`、SoC smoke、QSPI block、SPI XIP、WDT peripheral | `0x4000_5000` legacy status map 保持兼容；`0x4000_5020` command CTRL、`0x4000_5040` LUT0、`0x4000_5120` trigger 经真实 AXI→APB bridge 发出 `0x06`，共享 SPI pins 捕获 8 bit，command done status `0xC` 与 IRQ W1C 通过；SoC mux 只在 command CS active 时接管 pins。证据等级为有限 `SOC_INTEGRATED` APB/x1 slice，不覆盖 AXI XIP/quad pad/真实 flash/erase-program/boot。 |
| 2026-08-02 | `integration/function-contract` QSPI vendor-neutral flash endpoint slice | `make qspi-flash-behavioral-gate QSPI_FLASH_BEHAVIORAL_DIR=/tmp/qspi_flash_behavioral7` | PASS：`REGRESSION_TEST_SUCCESS qspi_flash_behavioral` | `qspi_apb_integration` 通过共享 x1 pins 连接 `spi_flash_behavioral`；`0x03` 读回 `DE AD BE EF`，`0x06` 保持 WEL，`0x05` 返回 WEL，`0x02` 对空白页执行 NOR `1->0` page-program，再次读回 `CA FE BA BE`，重新 WREN 后 `0x20` sector erase 再读回全 `FF`。模型仅为 vendor-neutral 仿真 endpoint，不能升级为外部 flash 器件/接口/AXI XIP 或 production erase/program 证据。 |
| 2026-08-02 | `integration/function-contract` QSPI standalone quad pad boundary slice | `make qspi-pad-wrapper-gate QSPI_PAD_WRAPPER_DIR=/tmp/qspi_pad_wrapper5` | PASS：`REGRESSION_TEST_SUCCESS qspi_pad_wrapper` | `qspi_pad_wrapper` 将 command engine 的 x4 `spi_io_o/io_oe/io_i` 映射到 `inout[3:0]`；gate 捕获 x4 read `A5`、x4 write `A1B2C3D4` 的 8 nibble，并确认 CS deassert 后高阻。状态为 `BLOCK_VERIFIED (vendor-neutral)`，不等于 SoC 四线 pad mux、接口、外部时序或商用 QSPI 完成。 |
| 2026-08-02 | `integration/function-contract` QSPI standalone AXI/XIP bridge slice | `make qspi-axi-xip-gate QSPI_AXI_XIP_DIR=/tmp/qspi_axi_xip2`；`make rtl-frontend-compile` | PASS：`REGRESSION_TEST_SUCCESS qspi_axi_xip`；RTL frontend `3/3` | `qspi_axi_xip` 通过内部 APB sequencer 配置 LUT0/地址/长度/trigger，轮询 done 并读取四个 RX byte；单拍读回 `DE AD BE EF`，两拍 burst 读回 `DE AD BE EF`/`11 22 33 44`，检查 AXI ID/RLAST/RRESP、AXI write `SLVERR` 和 SPI pins idle。状态为 `BLOCK_VERIFIED (vendor-neutral)`；尚未接 `soc_memory_subsystem`，APB command 与 AXI/XIP 共享 pins 的仲裁/abort/timeout/reset contract 仍未闭合。 |
| 2026-08-02 | `integration/function-contract` QSPI shared-pin arbiter contract slice | `make qspi-shared-pin-arbiter-gate QSPI_SHARED_PIN_ARBITER_DIR=/tmp/qspi_shared_pin_arbiter`；`make rtl-frontend-compile` | PASS：`REGRESSION_TEST_SUCCESS qspi_shared_pin_arbiter`；RTL frontend `3/3` | `qspi_shared_pin_arbiter` 验证 memory owner 保持、command request 不抢占 active memory、release 后切换、idle 时 command priority、同时 claim 的 conflict、未获 grant 不驱动 pins，以及 `SCLK=0/CS_N=1/MOSI=0` idle 值。随后已接入 SoC mux，并由 QSPI APB command、单线 XIP 和 quad S2 gates 覆盖触发/AXI acceptance；timeout/abort/reset-in-flight 另有独立 gate。状态为 `SOC_INTEGRATED (vendor-neutral)`，不等同外部接口/外部 flash 器件。 |
| 2026-08-02 | `integration/function-contract` SoC single-lane XIP/APB shared-pin integration | `make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_qspi_arbiter_final`；`make qspi-status-integration-gate`；`make qspi-flash-behavioral-gate`；`make qspi-pad-wrapper-gate`；`make qspi-axi-xip-gate`；`make qspi-shared-pin-arbiter-gate`；`make rtl-frontend-compile` | PASS：SoC `REGRESSION_TEST_SUCCESS`；QSPI gates pass；RTL frontend `3/3` | `mips_soc_impl` now instantiates the shared-pin arbiter; APB command trigger and AXI XIP request/grant are latched without preemption. Memory downstream `ARVALID` is grant-gated together with fabric `ARREADY`, preserving crossbar response accounting; the prior SoC smoke timeout was reproduced and then cleared. Evidence is limited `SOC_INTEGRATED` single-lane XIP/APB arbitration, not the standalone `qspi_axi_xip` bridge or a 完整 QSPI/boot path. |
| 2026-08-04 | `integration/function-contract` active-MMU translated-segment permission slice | `make mmu-active-gate` | PASS：`mmu-active: PASS` | 在 `SOC_MMU_ENABLE=1`、`SOC_PRODUCT_BOOT_ENABLE=1` 下，独立 `mips_mmu` gate 覆盖 sseg/kseg3 TLB hit 的 PFN+offset 翻译、C 属性、Invalid load/store 的 TLBL/TLBS 分类、clean-page store 的 Mod，以及 clean-page load 成功；sideband VA/ASID 也保持可见。该证据仍是 block-level `BLOCK_VERIFIED`，不代表完整 page-table allocator、PIC/TLS、scheduler 或 OS。 |
| 2026-08-04 | `integration/function-contract` MMU context APB status boundary | `make mmu-context-status-gate` | PASS：`mmu-context-status: PASS` | 验证 `0x4000_9000` 状态窗口的 ASID/generation、VPN、scope 写读及 sticky event/W1C 清除、APB ready/无 PSLVERR；allocator 接线和 command 行为由同日 APB integration 记录补充。该 gate 仍不代表 CPU/CP0 firmware 控制面。 |
| 2026-08-04 | `integration/function-contract` ASID allocator APB control integration | `make mmu-context-status-gate`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_allocator_apb` | PASS：allocator lease/reject/event/W1C；RTL frontend `3/3` | `0x4000_9014` 写 bit0 发起 bounded 4-slot ASID allocate，返回 ASID/generation；`0x4000_9018` 写 bit31 发起 release（[7:0] ASID、[15:8] generation），stale generation 进入 reject event。该 APB contract 已由后续 CPU firmware gate 覆盖；仍不代表真实 OS allocator 或 scheduler。 |
| 2026-08-04 | `integration/function-contract` shootdown mailbox APB integration | `make mmu-context-status-gate`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_shootdown_apb`；`make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=build/unit_tb/qspi_status_after_shootdown` | PASS：shootdown busy/done/timeout；RTL frontend `3/3`；QSPI status integration | `0x4000_901c` 提交当前 `{ASID, VPN, scope}`，`0x4000_9020` 发送逻辑 target ack，`0x4000_9024` 读 busy/invalidate/done/timeout/rejected sticky status；后续 CPU firmware gate 已覆盖真实 CPU uncached submit/ack/readback。target 仍固定为单核逻辑 endpoint，`invalidate_valid` 尚未连接TLB/IPI。 |
| 2026-08-04 | `integration/function-contract` CPU firmware context-control attempt | `make product-mmu-asid-context-gate`（临时 allocator/shootdown firmware image） | SUPERSEDED：后续 context-control gate 已通过 | 初始失败由 wired odd-page PFN 与 CPU/APB 事务观察边界造成；后续 `product-mmu-context-cpu-gate` 已修正映射并通过完整 allocator/shootdown/readback/release 流程，本条保留为历史诊断记录，不再作为当前阻塞项。 |
| 2026-08-04 | `integration/function-contract` AXI2APB write timing isolation | `make axi2apb-write-timing-gate` | PASS：`axi2apb-write-timing: PASS` | 独立 bridge gate 确认一个 AXI 写请求产生一个 setup、至少一个 enable，`pwrite/paddr/pwdata` 在 APB 阶段保持稳定并返回 OKAY；当前实现允许 enable 在 pready 采样边界多保持一个周期。CPU firmware 失败因此继续定位在 SoC TLB/APB 地址映射或事务观察边界，不再归因于 bridge 基本写时序。 |
| 2026-08-04 | `integration/function-contract` direct SoC AXI MMU context access | `make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=build/unit_tb/qspi_status_context_direct_axi` | PASS：direct AXI allocator lease、shootdown busy/done；原有 QSPI status integration 仍 PASS | 在真实 `soc_peripheral_subsystem -> axi2apb_bridge -> APB decode -> apb_mmu_context_status` 路径上，外部 AXI master 直接访问 `0x4000_9014/9000/901c/9024/9020`，验证 allocator lease、shootdown submit、busy、ack/done。由此排除 peripheral/APB 集成故障；CPU firmware 失败剩余范围为 CPU TLB wired page、MMU translation 或 CPU AXI request path。 |
| 2026-08-04 | `integration/function-contract` product D-cache C=2 uncached attribute gate | `make dcache-attr-gate` | PASS：`dcache-attr: PASS` | `ENABLE_LEGACY_ADDR_HEURISTIC=0` 下，对物理地址 `0x4000_9014` 显式输入 `cpu_uncacheable=1`，D-cache 发出单拍 AXI `ARLEN=0`、`ARCACHE=0000`，读回数据且不分配 cache line。该 block 证据确认 C=2 属性路径本身正常；CPU firmware 剩余问题仍在 MMU/CPU request wiring 或 response 返回。 |
| 2026-08-04 | `integration/function-contract` CPU/MMU uncached wiring audit | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/product_mmu_asid_context_trace_baseline` | PASS：原有 ASID/CPU gate `refills=3`；静态链路审计完成 | 确认 RTL 链路为 `mips_mmu.cache_attr -> mips_cpu.data_uncacheable -> mips_core.cpu_data_uncacheable -> dcache.cpu_uncacheable`，且产品 D-cache 关闭 legacy heuristic；原有 CPU/TLB context gate 无回归。新增 context firmware 仍未验收，下一步需在 CPU 实际发出 `C000_9014` 事务时捕获 `data_awaddr/data_araddr` 与 response。 |
| 2026-08-04 | `integration/function-contract` CPU MMU context transaction trace | `make product-mmu-context-cpu-gate` | PASS：`product-mmu-context-cpu: PASS`；trace 显示 `VA C000_9014 -> AXI 4000_9014`、`uncached=1`、APB select/write 有效 | 新增最小 CPU firmware/TLB trace gate，直接观察 `mem_vaddr`、`data_uncacheable`、D-cache `data_awaddr` 和 APB select/write。初始 trace 暴露 wired odd-page PFN 配置错误（错误地址 `0x4000_A014`）；修正 EntryLo pair 为 even `0x4000_8000` / odd `0x4000_9000` 后闭合 CPU->MMU->D-cache->AXI->APB 写链路。该 gate 只验证 allocator command write，不代表完整 CPU readback、scheduler 或 OS。 |
| 2026-08-04 | `integration/function-contract` CPU/MMU context-control firmware gate | `make product-mmu-context-cpu-gate` | PASS：allocator lease readback、event/W1C、page shootdown busy/invalidate/ack/done、stale-generation release reject 和 valid release 均通过 | 在真实 CPU/CP0/TLB、uncached D-cache、AXI2APB 和 MMU context APB window 上闭合控制面事务。集成 mailbox timeout 调整为 64 cycles，以覆盖合法 uncached read/ack bridge latency；standalone mailbox 仍保留 16-cycle timeout unit contract。该 gate 仍是单核 bounded firmware slice，不代表真实 page-table allocator、IPI、scheduler、OS 或 production boot。 |
| 2026-08-04 | `integration/function-contract` default SoC smoke after context-control integration | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_after_context_gate` | PASS：`REGRESSION_TEST_SUCCESS`，CPU/CP0 summary `intr=11 syscall=1 ri=4 adel=1 eret=16` | 默认 write-through L2、behavioral DDR/QSPI 配置下的实现 SoC smoke 在 APB MMU context 参数化后无回归；该 smoke 仍是既有开发/behavioral 平台证据，不提升 DDR/QSPI/OS 的产品完成度。 |
| 2026-08-04 | `integration/function-contract` Phase 3A closure re-run at current HEAD | `make phase3-complete` | PASS：directed `8/8`、coverage directed `8/8`、CPU/CP0 firmware gate；报告 `build/uvm/phase3_complete/phase3_completion_report.md` | 当前 HEAD 的 UART IRQ、APB fault/wait、flash-image read、AXI attribute、JTAG/cache/CP0、coverage directed 与 CPU/CP0 firmware 均通过。URG 仍报告历史 exclusion checksum/invalid-ID warnings；这些是 coverage metadata hygiene 问题，不改变功能 gate 结果，也不在当前阶段作为 lint/形式化分析/coverage closure 目标。 |
| 2026-08-05 | `integration/function-contract` Phase 3A closure after RDHWR/CP0 fixes | `make phase3-complete` | PASS：directed `8/8`、coverage directed `8/8`、CPU/CP0 firmware gate；报告 `build/uvm/phase3_complete/phase3_completion_report.md` | CP0 read serialization、标准 RDHWR `$0..$3/$29` 编码/映射修复后，UART/APB/flash/AXI/cache/CP0 全部保持通过；URG 仍仅有历史 coverage exclusion warnings。 |
| 2026-08-05 | `integration/function-contract` MMU process-pressure re-signoff | `make product-mmu-process-pressure-gate PRODUCT_MMU_PROCESS_PRESSURE_DIR=build/soc_test/product_mmu_process_pressure_current` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8` | 当前 HEAD 重跑 ASID 1..4 round-robin、四 PFN 隔离、动态清空后的 8 次 refill 和 wired 映射保留；仍不等同于 page-table walker、scheduler 或长期多进程 OS 压力。 |
| 2026-08-05 | `integration/function-contract` MMU EBase Modified recovery re-signoff | `make product-mmu-ebase-modified-gate PRODUCT_MMU_EBASE_MODIFIED_DIR=build/soc_test/product_mmu_ebase_modified_current` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_ebase_modified` | 当前 HEAD 重跑 DTLB clean-page store -> `Mod` exception、SRAM-relocated EBase handler、D-bit repair 和 `ERET` retry；异常精确状态保持通过。 |
| 2026-08-05 | `integration/function-contract` product CacheErr recovery re-signoff | `make product-cacheerr-gate PRODUCT_CACHEERR_DIR=build/soc_test/product_cacheerr_current` | PASS：`REGRESSION_TEST_SUCCESS product_cacheerr` | 当前 HEAD 重跑 cached refill AXI `SLVERR` -> CacheErr (`ExcCode=30`)、ERL/ErrorEPC、单次 handler marker 和 `ERET` retry；完整 ECC escalation/production policy 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` product I-cache error recovery re-signoff | `make cpu-icache-product-error-gate PRODUCT_ICACHE_PRODUCT_ERROR_DIR=build/unit_tb/icache_product_error_current` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_product_error ar_count=3 boot_ar_count=2 vector_ar_count=1` | 当前 HEAD 重跑产品启动 I-cache 首笔 `SLVERR`，验证 BEV CacheErr vector、`ErrorEPC`/ERL、handler 重取和 `ERET` 恢复；完整 parity/ECC policy 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` I-cache stress re-signoff | `make cpu-icache-stress-gate CPU_ICACHE_STRESS_DIR=build/unit_tb/icache_stress_current` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_stress ar_count=895 unique_lines=320 line_pc_count=960` | 当前 HEAD 重跑 320 条 unique instruction lines、跨 line refill、AXI AR backpressure 和重复取指一致性；复杂 outstanding/reordering、parity/ECC 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` CPU CACHE maintenance re-signoff | `make cpu-cache-op-gate CPU_CACHE_OP_DIR=build/unit_tb/cache_ops_current` | PASS：`REGRESSION_TEST_SUCCESS mips_cpu_cacheop` | 当前 HEAD 重跑 D-cache 六类 `CACHE` maintenance operation、CPU stall/complete handshake 和错误返回路径；coherence、parity/ECC 和完整 OS cache ABI 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` consolidated RTL functional batch | `make phase2-complete phase3-complete phase3b-complete phase3c-complete`；统一前端编译；CPU/MMU、Cache、QSPI、DDR4 behavioral、SoC smoke gates | PASS：Phase 2 `16/16`、Phase 3A `8/8`、Phase 3B/3C `1/1`，其余批量 gate 全部 PASS，`BATCH_VALIDATION_PASS` | 一次性重跑当前 RTL 功能主线：前端 compile、MMU context/process/Mod/CacheErr/vector、I-cache error/stress、CACHE op/tag、QSPI x1/quad/status/command、DDR4 entry/behavioral/status 和默认 SoC smoke。URG exclusion/checksum warnings 仍是既有 coverage metadata 问题，不影响功能 gate。 |
| 2026-08-05 | `integration/function-contract` dual-core IPI/shootdown contract step 1 | `make mmu-ipi-shootdown-gate` | PASS：`REGRESSION_TEST_SUCCESS mmu_ipi_shootdown` | 新增 vendor-neutral `mmu_ipi_shootdown` standalone RTL，验证 target/payload/generation latch、one-cycle invalidate issue、stale ack rejection、busy re-entry rejection、target-loss timeout 和 valid ack；尚未接入双核 SoC 或 real cache coherency。 |
| 2026-08-05 | `integration/function-contract` CPU/MMU consolidated gate repair | `make mmu-active-gate` | PASS：`mmu-active: PASS`；CPU/MMU batch 其余 gate 均已返回 `RC=0` | 修复 `tb/unit/mmu/tb_mips_mmu_active.sv` 未连接新增 `tlb_lookup_multi_hit` 输入导致的 VCS elaboration error；这是 testbench 接口同步修复，不是 RTL 行为失败。 |
| 2026-08-04 | `integration/function-contract` Phase 3B/3C closure re-run at current HEAD | `make phase3b-complete`；`make phase3c-complete` | PASS：Phase 3B CPU/CP0 directed `1/1`、Phase 3C PIC mask directed `1/1`，各自 coverage gate 通过 | 当前 HEAD 的 CPU/CP0 exception-entry/return 和 PIC multi-source mask arbitration 均无回归；报告分别位于 `build/uvm/phase3b_complete/phase3b_completion_report.md`、`build/uvm/phase3c_complete/phase3c_completion_report.md`。coverage 仍仅作既有 gate 证据，不改变当前功能范围边界。 |
| 2026-08-04 | `integration/function-contract` MMU context status reconciliation | 文档审计（对应 `make product-mmu-context-cpu-gate` 已通过） | PASS：纠正 context APB/allocator/shootdown 条目之间的状态矛盾 | 文档现在区分三层证据：vendor-neutral allocator/mailbox、真实单核 CPU 到 APB 控制面再到 `mips_cp0 -> mips_tlb` 的 invalidation/refill、尚未实现的真实多核 IPI/page-table walker；不把单核 APB invalidation 脉冲升级为多核 TLB shootdown。 |
| 2026-08-04 | `integration/function-contract` TLB invalidate sideband unit slice | `make tlb-invalidate-gate`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_tlb_invalidate`；`make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit_tb/tlb_asid_policy_after_invalidate` | PASS：page/ASID/all dynamic invalidation；wired floor/global handling；existing ASID policy and RTL frontend regression | `mips_tlb` 新增可选旁路 invalidate 端口，scope 0/1/2 分别清除匹配 page、ASID 或所有 dynamic entries，并保留 `inv_wired_floor` 以下 wired entries；page scope 正确处理 global entry。当前仅为 TLB array unit evidence，尚未从 APB mailbox 接入 `mips_cp0`/CPU/SoC。 |
| 2026-08-04 | `integration/function-contract` SoC TLB invalidate wiring slice | `make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_tlb_connected`；`make product-mmu-context-cpu-gate` | PASS：frontend `3/3`；CPU/MMU context firmware PASS | APB mailbox `invalidate_valid/{VPN,ASID,scope}` 现已通过 `soc_peripheral_subsystem -> mips_soc_impl -> soc_core_subsystem -> mips_core -> mips_cpu -> mips_cp0 -> mips_tlb` 连接，默认 wired floor 为 2；随后由 real CPU mailbox shootdown/refill gate 覆盖动态 entry 清除和重新 refill。仍未实现真实多核 IPI/page-table walker。 |
| 2026-08-04 | `integration/function-contract` real CPU mailbox shootdown/refill gate | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/product_mmu_asid_context_tlb_shootdown` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | 真实 CPU firmware 建立 ASID 1/2 同 VA 不同 PFN，切回命中后通过 `0x4000_9000` mailbox 设置 VPN/ASID/scope、submit/ACK，清除 ASID 1 dynamic TLB entry；再次访问触发第三次 refill，同时验证 wired APB mapping 保留。仍不代表多核 IPI、完整 page-table walker 或 scheduler。 |
| 2026-08-04 | `integration/function-contract` MMU real-shootdown regression | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/mmu_asid_context_after_real_shootdown`；`make product-mmu-process-pressure-gate PRODUCT_MMU_PROCESS_PRESSURE_DIR=build/soc_test/mmu_pressure_after_real_shootdown`；`make product-mmu-context-cpu-gate`；`make tlb-invalidate-gate` | PASS：ASID context `refills=3`、process pressure `refills=8`、CPU context、TLB invalidate unit | 新增 TLB sideband 连接后重跑完整相关回归，确认真实单核 shootdown/refill、四 ASID 压力、APB context control 与 TLB unit 均无回归。 |
| 2026-08-15 | `integration/function-contract` TLB invalidate + micro-TLB stale-entry slice | `RUN_DIR=build/unit_tb/tlb_invalidate_micro2 tb/unit/tlb/run_tlb_invalidate.sh` | PASS：`REGRESSION_TEST_SUCCESS tlb_invalidate`；I/D micro-TLB page-scope invalidation、ASID/all-dynamic invalidation、wired/global preservation 和 context-flush recovery | invalidate gate 现在以 `SOC_MICRO_TLB_ENABLE=1` 编译，先形成 I/D 两侧 cached translation，再验证 architectural invalidation 不保留 stale hit；context flush 保留主 TLB entry 并允许 I/D micro miss 从主 TLB重新填充。该 unit 证据不等同于 PTE 修改后 CPU refill handler 穿过 D-cache/L2 的系统级闭合。 |
| 2026-08-03 | `integration/function-contract` MMU refill script entry audit | `RUN_DIR=/tmp/soc_mmu_refill_qspi_arbiter_fix tb/soc_test/run_mmu_refill.sh`；baseline comparison `RUN_DIR=/tmp/soc_mmu_refill_baseline` | PARTIAL：补齐 `axi_boot_rom.v` 后 VCS compile/elaboration 通过，但 legacy `mmu_refill` firmware 在本线和未接仲裁基线均于 5 ms timeout，未产生 `mmu_refill: PASS` | 该入口原先漏列 Boot ROM 源文件，现已修复；仿真 timeout 是既有 MMU refill gate 问题，不归因于本轮 QSPI arbiter，也不作为当前 MMU 产品证据。继续使用已通过的 `product-mmu-boot-gate`、ASID/context 和 process-pressure gates。 |
| 2026-08-03 | `integration/function-contract` UVM image-model regression smoke | `make uvm UVM_RUN_DIR=/tmp/uvm_qspi_arbiter_smoke` | PASS：`REGRESSION_TEST_SUCCESS` | `ENABLE_FLASH_IMAGE_MODEL=1` 配置下的 UVM `soc_bus_stress_test` 通过，确认 grant-gated image-model `ARVALID/ARREADY` 没有回归默认 UVM smoke。 |
| 2026-08-03 | `integration/function-contract` QSPI command timeout/abort/reset-in-flight slice | `make qspi-cmd-behavioral-gate QSPI_CMD_BEHAVIORAL_DIR=/tmp/qspi_cmd_timeout_v1`；`make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=/tmp/qspi_status_timeout_v2`；`make qspi-flash-behavioral-gate QSPI_FLASH_BEHAVIORAL_DIR=/tmp/qspi_flash_timeout_v1`；`make qspi-pad-wrapper-gate QSPI_PAD_WRAPPER_DIR=/tmp/qspi_pad_timeout_v1`；`make qspi-axi-xip-gate QSPI_AXI_XIP_DIR=/tmp/qspi_axi_timeout_v1`；`make qspi-shared-pin-arbiter-gate QSPI_SHARED_PIN_ARBITER_DIR=/tmp/qspi_arb_timeout_v1`；`make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_qspi_timeout_v1`；`make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_qspi_timeout_v1` | PASS：QSPI command/status/flash/pad/AXI/arbiter gates、RTL frontend `3/3`、SoC smoke | `qspi_cmd_behavioral` 新增非零 `TIMEOUT` budget、CTRL[2]/清 enable abort、timeout/abort W1C 和 reset-in-flight pin-safe semantics；状态位保持 busy/tx/rx/done/error，并增加 timeout bit5、aborted bit6。`qspi_axi_xip` 将 command timeout/error 转为 AXI `SLVERR`；SoC-peripheral gate 验证 command timeout、W1C、WDT 中断 active command 后 `CS_N=1/SCLK=0` 和 WDT expiry retention。证据关闭 `SOC_INTEGRATED` 的 command failure/reset slice，但仍不是商用 QSPI/接口/flash/boot。 |
| 2026-08-03 | `integration/function-contract` SoC vendor-neutral four-lane pad boundary | `make qspi-soc-RTL 接口 mux-gate QSPI_SOC_PAD_MUX_DIR=/tmp/qspi_soc_pad_mux_gate2`；`make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_qspi_pad_mux`；`make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_qspi_pad_mux2`；受影响的 QSPI gates | PASS：`REGRESSION_TEST_SUCCESS qspi_soc_pad_mux`、RTL frontend `3/3`、SoC smoke、既有 QSPI gates | `qspi_soc_pad_mux` 已在 `mips_soc_impl` 接入共享 owner；`mips_soc/soc_top` 新增可选 `ENABLE_QSPI_QUAD` 与 `qspi_io[3:0]`，默认配置仍保持 legacy x1。gate 验证 command 四 lane output/oe、memory lane-0 兼容、command 优先级、读阶段高阻和 idle 安全值。该证据是 vendor-neutral pad boundary/RTL wiring，不覆盖四线 command/AXI functional boot、外部接口、外部时序、外部 flash 器件 或 production boot。 |
| 2026-08-03 | `integration/function-contract` SoC four-lane APB command gate | `make qspi-soc-quad-gate QSPI_SOC_QUAD_DIR=/tmp/qspi_status_quad_soc_v1` | PASS：`REGRESSION_TEST_SUCCESS qspi_status_integration` | 打开 `ENABLE_QSPI_SHARED_ARB=1` 和 `ENABLE_QSPI_QUAD=1`，从真实 AXI→APB command window 触发 x4 read（外部 pad 返回 `0xC3`）和 x4 write（捕获 8 个 nibble，`A1B2C3D4`），同时保留 status/timeout/WDT/reset-in-flight 检查。该 gate 关闭 SoC 四线 APB command wiring；不覆盖四线 AXI XIP、外部接口/外部时序、外部 flash 器件 或 production boot。 |
| 2026-08-03 | `integration/function-contract` standalone quad AXI/XIP bridge slice | `make qspi-axi-xip-gate QSPI_AXI_XIP_DIR=/tmp/qspi_axi_xip_x4_default_v2`；`make qspi-axi-xip-quad-gate QSPI_AXI_XIP_QUAD_DIR=/tmp/qspi_axi_xip_quad_v2`；`make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_qspi_quad_v2` | PASS：x1/quad `REGRESSION_TEST_SUCCESS qspi_axi_xip`；RTL frontend `3/3` | `qspi_axi_xip` 的 `ENABLE_QUAD_IO=1` 以 `0x6B + 24-bit x1 address + x4 data` 驱动 `qspi_cmd_behavioral`；quad behavioral flash model 修正地址到 data phase 首个 nibble 的边沿对齐。两条 gate 均覆盖 AXI 单拍/两拍 burst、ID/RLAST/RRESP、APB sequencing、flash readback、AXI write `SLVERR` 和 pins idle。状态为 `BLOCK_VERIFIED (vendor-neutral)`；未接 `soc_memory_subsystem`，不覆盖 SoC 四线 AXI XIP、外部接口、外部时序、外部 flash 器件、erase/program 或 production boot。 |
| 2026-08-03 | `integration/function-contract` SoC memory quad XIP opt-in integration | `make qspi-soc-memory-quad-xip-gate QSPI_SOC_MEMORY_QUAD_XIP_DIR=/tmp/qspi_soc_memory_quad_xip_v1`；`make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_after_memory_quad_v2`；`make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_soc_quad_xip_v3` | PASS：`REGRESSION_TEST_SUCCESS soc_memory_quad_xip`；SoC smoke 退出码 `0`；RTL frontend `3/3` | `soc_memory_subsystem.ENABLE_QSPI_QUAD=1` 将 `qspi_axi_xip` 放入 S2 AXI path，并保留 `axi_read_timeout_guard`、shared grant 和 `qspi_io[3:0]` tri-state boundary。S2 gate 覆盖 quad 单拍/两拍 burst、AXI ID/RLAST/RRESP、flash readback、AXI write `SLVERR`、controller-present 和 idle pins；默认 SoC 配置仍为 x1。该证据是 vendor-neutral RTL/behavioral integration，不覆盖无 SRAM preload 的 CPU boot、外部接口、外部 flash 器件 或 production boot。 |
| 2026-08-03 | `integration/function-contract` quad no-preload development manifest handoff | `make product-manifest-handoff-quad-gate PRODUCT_MANIFEST_HANDOFF_QUAD_DIR=/tmp/product_manifest_handoff_quad_final`；对照 `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=/tmp/product_manifest_handoff_x1_final`；`make qspi-soc-memory-quad-xip-gate QSPI_SOC_MEMORY_QUAD_XIP_DIR=/tmp/qspi_soc_memory_quad_endian_final`；`make qspi-axi-xip-gate QSPI_AXI_XIP_DIR=/tmp/qspi_axi_xip_endian_final`；`make soc-smoke SOC_TEST_RUN_DIR=/tmp/soc_smoke_quad_endian_final`；`make rtl-frontend-compile RUN_ROOT=/tmp/rtl_frontend_quad_boot_final` | PASS：quad handoff 有效镜像、11 个 header/CRC 负例、timeout-to-DBE；x1 对照同样 PASS；SoC quad S2、standalone AXI/XIP、SoC smoke、RTL frontend `3/3` 均 PASS | 无 SRAM preload、无 `axi_flash_image_model` 的 vendor-neutral quad endpoint 通过真实 `qspi_io[3:0]` 完成 `0x6B` command/address、payload/CRC、Boot SRAM copy 和 kseg0 stage-1 handoff；timeout 返回 `SLVERR` 并到 DBE。`ENDIAN_SWAP=1` 固化 SoC little-endian AXI word ABI，默认配置仍保持 x1。证据等级为 `SOC_INTEGRATED` / vendor-neutral development boot；不代表外部接口、外部 flash 器件、外部系统 外部时序、量产启动软件/signature、erase/program、DDR init 或 `PRODUCT_FUNCTION_READY`。 |
| 2026-08-03 | `integration/function-contract@bc3d6c8` frozen default baseline | `make rtl-frontend-compile`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/frozen_default_x1`；`make phase3-complete UVM_PHASE3_COMPLETE_DIR=build/uvm/frozen_phase3_complete` | PASS：RTL frontend `3/3`；默认 SoC `REGRESSION_TEST_SUCCESS`；Phase 3A directed `8/8`、coverage `8/8`、CPU/CP0 `1/1` | 冻结默认 L2 write-through、QSPI x1、DDR4 behavioral、bare-metal/default MMU 配置；`soc_top` 的 `ENABLE_QSPI_QUAD` 已改为 `0`，quad/WB/NB/产品 MMU 只能显式 opt-in。RTL 报告：`build/unit_tb/rtl_frontend_compile/rtl_frontend_compile_report.md`；Phase 3 报告：`build/uvm/frozen_phase3_complete/phase3_completion_report.md`。Coverage exclusion 仍有既有 URG checksum/invalid-item warnings，不作为 signoff 依据。 |
| 2026-08-03 | `integration/function-contract` UART CTS flow-control slice | `vcs ... rtl/perips/apb_uart_16550.v tb/unit/uart/tb_uart_16550.v`；运行目录 `build/unit_tb/uart_cts_only` | PASS：`REGRESSION_TEST_SUCCESS uart_16550`（Case 16） | MCR[5] 启用硬件 CTS 门控；CTS inactive 时保持 TX idle 且保留 FIFO 数据，释放 CTS 后才启动 frame。修复此前 TX idle 状态仍递增 `tx_rd`、导致被 CTS 阻塞字节丢失的问题。该证据关闭 UART RTL flow-control behavioral slice；RTL 接口 mux、外部接口/外部系统 timing、软件 driver 仍 deferred。 |
| 2026-08-03 | `integration/function-contract` post-CTS default SoC smoke | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/after_uart_cts` | PASS：`REGRESSION_TEST_SUCCESS`；默认 L2 write-through | 修复 smoke 编译源列表遗漏 `apb_mmu_context_status.v`，并确认 CTS RTL 变更不影响默认 SoC 行为。URG 既有 exclusion checksum/invalid-vector warnings 仍不作为功能 signoff 依据。 |
| 2026-08-03 | `integration/function-contract` UART pad/CTS re-run | `make uart-pad-wrapper-gate`；`make uart-cts-soc-gate SOC_TEST_UART_CTS_DIR=build/soc_test/uart_cts_pad_after UART_CTS_FW_DIR=build/firmware/uart_cts_pad_after` | PASS：`uart_pad_wrapper` unit；UART CTS SoC gate；`REGRESSION_TEST_SUCCESS` | 复核 disabled pad 安全 idle/inactive、enabled signal passthrough，以及真实 `mips_soc_impl -> uart_pad_wrapper -> apb_uart_16550` CTS hold/release。仍不覆盖 外部接口单元、接口行为、接口时序、外部系统模型或软件 driver。 |
| 2026-08-03 | `integration/function-contract` QSPI development manifest failure-policy re-run | `make product-manifest-handoff-gate PRODUCT_MANIFEST_HANDOFF_DIR=build/unit_tb/product_manifest_qspi_next` | PASS：valid handoff、manifest rejection matrix、XIP timeout-to-DBE；failure codes `0xB007_0003` (manifest) / `0xB007_0004` (XIP timeout) | 在当前 HEAD 重跑 vendor-neutral SPI boot，确认坏镜像不进入 stage-1，XIP timeout 进入 DBE，并通过 always-on boot-status 发布稳定分类码。外部接口、外部 flash 器件 和 production secure-boot policy 仍 deferred。 |
| 2026-08-03 | `integration/function-contract` CPU/MMU allocator/shootdown contract re-run | `make tlb-asid-allocator-gate`；`make tlb-shootdown-mailbox-gate`；`make mmu-context-contract-gate` | PASS：`tlb_asid_allocator`、`tlb_shootdown_mailbox`、`mmu_context_contract` | 验证四槽 ASID lease、generation stale-release reject、pool exhaustion、page/ASID/all shootdown payload、ack/timeout、busy 重入拒绝及 allocator+mailbox 组合路径；随后由 `product-mmu-context-cpu-gate` 验证真实单核 CPU/CP0/TLB invalidation/refill。状态为 `SOC_INTEGRATED (single-core, vendor-neutral)`；多核 IPI、page-table walker 和 scheduler 仍 deferred。 |
| 2026-08-03 | `integration/function-contract` bounded MMU process-pressure re-run | `make product-mmu-process-pressure-gate PRODUCT_MMU_PROCESS_PRESSURE_DIR=build/soc_test/mmu_pressure_after_contract` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8` | 最新 HEAD 重跑 ASID 1..4 round-robin、同 VA 不同 PFN、动态 TLBWI shootdown、wired mapping 保留和四上下文清空后重新 refill；仍属于 bounded single-core behavioral evidence。 |
| 2026-08-03 | `integration/function-contract` CPU/CP0 ASID context re-run | `make product-mmu-asid-context-gate PRODUCT_MMU_ASID_CONTEXT_DIR=build/soc_test/mmu_asid_context_after_contract` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_asid_context refills=3` | 最新 HEAD 验证真实 CPU/CP0/TLB/MMU 的 ASID 1/2 映射隔离、切回命中、动态 `TLBWI` 清除和 wired APB 映射保留；不代表完整 allocator、IPI 或 OS。 |
| 2026-08-03 | `integration/function-contract` MMU user/kernel permission slice | `RUN_DIR=build/unit_tb/mmu_permissions tb/unit/mmu/run.sh` | PASS：`mmu: PASS` | 新增 standalone `mips_mmu` directed checks：user-mode 对 kseg0/kseg1 的 load 产生 `AdEL`，store 产生 `AdES`；该分段权限规则独立于 `SOC_MMU_ENABLE`。仍未覆盖完整 page permissions、PIC/TLS 或 kernel runtime。 |
| 2026-08-03 | `integration/function-contract` kseg0 runtime ABI re-run | `make product-kseg0-runtime-abi-gate PRODUCT_KSEG0_RUNTIME_ABI_DIR=build/unit_tb/product_kseg0_runtime_abi_after_permissions` | PASS：`REGRESSION_TEST_SUCCESS product_manifest_handoff_runtime_abi` | 最新 HEAD 重跑真实 SPI XIP、manifest CRC、MMU kseg0 execution、可重定位 `.data`、`.bss` 清零、heap/stack、exception relocation、`syscall`/`ERET` 和 I-cache tag maintenance。仍是单镜像 runtime slice。 |
| 2026-08-03 | `integration/function-contract` CPU/MMU exception regression re-run | `make tlb-os-context-gate TLB_OS_CONTEXT_DIR=build/unit_tb/tlb_os_context_after_permissions`；`make product-mmu-ebase-modified-gate PRODUCT_MMU_EBASE_MODIFIED_DIR=build/unit_tb/mmu_ebase_modified_after_permissions`；`make product-cacheerr-gate PRODUCT_CACHEERR_DIR=build/unit_tb/product_cacheerr_after_permissions` | PASS：`tlb_os_context`、`product_mmu_ebase_modified`、`product_cacheerr` | 权限切片后重新确认软件 context-switch、EBase `Mod` handler/D-bit repair/ERET，以及 cacheable refill `SLVERR -> CacheErr/ERL/ErrorEPC/ERET` recovery 无回归。 |
| 2026-08-03 | `integration/function-contract` QSPI retry/status re-run | `make qspi-retry-policy-gate`；`make qspi-status-integration-gate QSPI_STATUS_INTEGRATION_DIR=build/unit_tb/qspi_status_after_retry` | PASS：`qspi_retry_policy`、`qspi_status_integration` | 确认 bounded retry 的 timeout/init retry、exhaustion、CRC no-retry，以及 QSPI APB status sticky/W1C、command timeout/abort/WDT/reset-in-flight；同时修复 status gate 遗漏 `apb_mmu_context_status.v` 编译依赖。 |
| 2026-08-04 | `integration/function-contract` QSPI command/flash/XIP re-run | `make qspi-cmd-behavioral-gate`；`make qspi-flash-behavioral-gate`；`make qspi-axi-xip-gate` | PASS：`qspi_cmd_behavioral`、`qspi_flash_behavioral`、`qspi_axi_xip` | 当前 HEAD 重跑 FIFO/command sequencing、timeout/abort、vendor-neutral flash read/write behavior、AXI single/two-beat XIP、ID/RLAST/RRESP 和 write rejection；仍不覆盖外部接口、外部 flash 器件 或 production erase/program。 |
| 2026-08-04 | `integration/function-contract` UART CPU firmware driver re-run | `make uart-cpu-gate SOC_TEST_UART_CPU_DIR=build/soc_test/uart_cpu_after_qspi` | PASS：`SUCCESS: UART CPU FIRMWARE GATE PASSED` | 当前默认 L2/QSPI 配置下重跑 UART CPU TX/RX、FIFO/IRQ 和 APB driver mailbox；覆盖 RTL behavioral driver path，不代表 Linux 8250、软件 driver 或外部系统 serial electrical behavior。 |
| 2026-08-04 | `integration/function-contract` Phase 3 closure re-run | `make phase3-complete UVM_PHASE3_COMPLETE_DIR=build/uvm/phase3_complete_after_continuous` | PASS：Phase 3A directed `8/8`、coverage run、CPU/CP0 firmware gate；报告 `build/uvm/phase3_complete_after_continuous/phase3_completion_report.md` | 最新 HEAD 重跑默认 L2 write-through 下 UART IRQ、APB fault stress、flash image、AXI attributes、ISA/cache/CP0 sweeps 和 CPU/CP0 firmware；URG exclusion checksum/invalid-vector warnings 仍不作为 signoff 依据。 |
| 2026-08-04 | `integration/function-contract` Phase 2 closure re-run | `make phase2-complete UVM_PHASE2_COMPLETE_DIR=build/uvm/phase2_complete_after_continuous` | PASS：directed `16/16`、coverage directed `16/16`、required functional groups `100%`；报告 `build/uvm/phase2_complete/phase2_completion_report.md` | 最新 HEAD 重跑 DMA/timer/PIC、APB models/bursts、SRAM integrity、AXI ID/overlap、JTAG recovery、fabric/unmapped/flash write errors、bus stress 和 base test；覆盖率数值不作为当前功能 signoff 门槛。 |
| 2026-08-04 | `integration/function-contract` CPU vectored-interrupt re-run | `make product-vectored-interrupt-gate PRODUCT_VECTORED_INTERRUPT_DIR=build/unit_tb/vectored_interrupt_after_plan` | PASS：`REGRESSION_TEST_SUCCESS product_vectored_interrupt` | 当前 HEAD 重跑 `Cause.IV/IntCtl.VS` 的 IP-based vector path、EBase vector entry、handler mailbox 和 `ERET` 返回；外部 VIC source-8 -> IP2 -> VEIC `EBase+0x300` path 已由后续 directed gate 补齐，嵌套中断和完整优先级策略仍 deferred。 |
| 2026-08-04 | `integration/function-contract` product I-cache error re-run | `make cpu-icache-product-error-gate PRODUCT_ICACHE_PRODUCT_ERROR_DIR=build/unit_tb/icache_product_error_after_vectored` | PASS：`REGRESSION_TEST_SUCCESS mips_core_icache_product_error ar_count=3 boot_ar_count=2 vector_ar_count=1` | 取指 `SLVERR` 触发 product vector，验证 ERL/ErrorEPC、handler 重取和 ERET 恢复；与 vectored interrupt gate 组合后仍通过。 |
| 2026-08-04 | `integration/function-contract` CPU/cache contract re-run | `make cpu-icache-stress-gate`；`make cpu-cache-op-gate`；`make cpu-cache-tag-gate` | PASS：I-cache stress `ar_count=895 unique_lines=320 line_pc_count=960`；CACHE op；TagLo/TagHi | 重跑 320-line AR backpressure/refill stress、六类 CACHE maintenance operation 和有限 TagLo/TagHi/SYNC contract；不代表完整 cache coherence、ECC 或 OS cache management。 |
| 2026-08-04 | `integration/function-contract` DDR4 controller/status contract re-run | `make ddr4-controller-gate`；`make ddr4-status-gate` | PASS：controller gate；`REGRESSION_TEST_SUCCESS apb_ddr4_status` | controller/status 通过 init、refresh/backpressure、读写、fatal/非法命令和 APB sticky/W1C；证据限定为 RTL/仿真。 |
| 2026-08-03 | `integration/function-contract` UART CTS SoC integration slice | `make uart-cts-soc-gate SOC_TEST_UART_CTS_DIR=build/soc_test/uart_cts_gate UART_CTS_FW_DIR=build/firmware/uart_cts`；`make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/uart_cts_block_aggregate`；`make rtl-frontend-compile` | PASS：SoC gate `REGRESSION_TEST_SUCCESS`，并打印 `UART CTS inactive held TX idle` 与 `UART CTS release allowed TX frame`；DUT block aggregate `10/10`；RTL frontend `3/3` | 新增 `uart_cts` firmware 经真实 CPU/APB 配置 UART 8N1/FIFO/divisor、打开 MCR[5] 并写 TX FIFO；SoC TB 从外部保持 `uart_cts_n=1`，确认 `uart_tx` 不启动，再释放 CTS 并确认 TX frame 出现和 firmware 完成。该证据关闭 `soc_top -> mips_soc -> APB UART -> external CTS/TX pin` 的 behavioral flow-control 集成；不覆盖 接口单元、外部接口/外部系统 timing、接口行为、真实线缆/收发器或软件 driver policy。 |
| 2026-08-03 | `integration/function-contract` UART auto-RTS watermark slice | `make dut-block-unit-gate DUT_BLOCK_UNIT_DIR=build/unit_tb/uart_rts_block_aggregate`；UART unit log `build/unit_tb/uart_rts_block_aggregate/uart/sim.log` | PASS：UART Case 17 与 block aggregate `10/10`；`REGRESSION_TEST_SUCCESS uart_16550` | UART loopback 在 MCR[1]/MCR[5] 开启、FIFO trigger=4 时，验证 RX FIFO 达到阈值后 `uart_rts_n` 由有效低撤销为高，读空 FIFO 后重新有效；该证据关闭 RTL auto-RTS 水位行为，不覆盖 接口单元、外部接口/外部系统 timing、接口行为 或软件 driver policy。 |
| 2026-08-08 | `integration/function-contract` DUT block readiness rerun after testbench observer fixes | `source /etc/profile.d/modules.sh && module load vcs && RUN_ROOT=build/unit_tb/dut_block_readiness_fixed2_20260808 tb/unit/run_dut_block_unit_gate.sh`；`RUN_DIR=build/unit_tb/product_tlb_data_vectors_fixed_20260808 tb/unit/bootrom/run_product_tlb_data_vectors.sh` | PASS：DUT block gate `10/10`；`REGRESSION_TEST_SUCCESS dcache`；`REGRESSION_TEST_SUCCESS product_tlb_data_vectors` | D-cache unit TB 将新增 coherency 输入显式 tie-off，消除未连接输入造成的 X 状态；product TLB data-vector TB 改观察 MEM-side `dmem_translate_req`，覆盖 translation fault 抑制外部 cache request 的当前 CPU contract。该记录是验证/observer 修复，不扩大 D-cache ECC/coherency、完整 MMU 或产品启动承诺。 |
| 2026-08-08 | `integration/function-contract` BPU opt-in IF redirect closure slice | `make bpu-redirect-gate`；`VCS_EXTRA_ARGS='+define+SOC_BPU_ENABLE=1' FW_HEX=build/firmware/soc_smoke/firmware.hex RUN_DIR=build/soc_test/bpu_opt_in2 tb/soc_test/run.sh`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_after_bpu` | PASS：BPU unit；frontend opt-in `4/4`；BPU opt-in SoC smoke；默认 SoC smoke | BPU 的 BTB/BHT/RAS 预测经 IF delay-slot pending path 接入，ID resolve 作为架构真值，wrong direction/target 通过 recovery target 修正；J/JAL、JR/JALR 分类和 not-taken BHT 更新已接线。CoreMark/Dhrystone 命中率、fetch queue、多在途分支、完整 mispredict 性能和 formal 仍 deferred。 |
| 2026-08-23 | `integration/function-contract` CPU performance workload observation slice | `make perf-workloads-gate`；`build/soc_test/perf_workloads/sim.log` | PASS：真实 CPU/APB `SOC_PERF_COUNTERS=1`；四条 sequential/strided/branch-mixed/MDU workload 均输出 cycle、retire、I/D miss、branch 和 MDU delta，版本 `0x50430001`，并达到 `REGRESSION_TEST_SUCCESS` | 这是可重复的微架构观测基线，不是官方 CoreMark/Dhrystone/STREAM 成绩、CPI 精度保证或商用性能 signoff；标准 benchmark 源码/性能目标仍 deferred。 |
| 2026-08-03 | `integration/function-contract` UART vendor-neutral pad wrapper | `make uart-pad-wrapper-gate` | PASS：`REGRESSION_TEST_SUCCESS uart_pad_wrapper` | 固化 UART pin enable contract：disabled 时 TX/RTS/DTR 为安全 idle，RX/CTS/DSR/DCD/RI 返回 inactive；enabled 时双向信号透传。该 gate 只覆盖 RTL pad boundary，不覆盖 外部接口单元、接口行为、IO 外部时序或外部系统模型。 |
| 2026-08-03 | `integration/function-contract` UART pad wrapper SoC integration | `make uart-cts-soc-gate SOC_TEST_UART_CTS_DIR=build/soc_test/uart_cts_pad_integrated UART_CTS_FW_DIR=build/firmware/uart_cts_pad_integrated` | PASS：UART CTS SoC gate；RTL/SoC compile and simulation completed | `ENABLE_UART_PINS=1` 的真实 `mips_soc_impl` 路径已经过 `uart_pad_wrapper`，CTS hold/release 行为保持通过；`ENABLE_UART_PINS=0` 仍走 legacy bypass。该集成仍不覆盖 外部接口单元、接口行为、接口时序 或外部系统模型。 |
| 2026-08-03 | `integration/function-contract` UART pad wrapper RX integration | `make uart-external-rx-soc-gate SOC_TEST_UART_EXTERNAL_RX_DIR=build/soc_test/uart_external_rx_pad_integrated UART_EXTERNAL_RX_FW_DIR=build/firmware/uart_external_rx_pad_integrated`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_uart_pad_integrated` | PASS：external RX SoC gate、默认 SoC smoke | 异步 8N1 `0x5A` 经过 `uart_pad_wrapper`、RX synchronizer/FIFO/PIC/RBR 后由 CPU 读回；默认 smoke 无回归。修正 `uart-external-rx-soc-gate` firmware 输出目录使用相对路径导致的错误。 |
| 2026-08-03 | `integration/function-contract` Phase 2 baseline re-signoff after UART/DDR changes | `make phase2-complete` | PASS：directed `16/16`、coverage `16/16`、required functional groups `100%`、error scan clean；报告 `build/uvm/phase2_complete/phase2_completion_report.md` | 修正 `axi_apb_burst_stress_seq` 对 `0x4000_5000` 的陈旧“unused slot”假设；该地址现在是 QSPI status，unused burst 改用 `0x4000_9000`。确认近期 UART pad 与 DDR status 变更未破坏默认 Phase 2 contract。 |
| 2026-08-04 | `integration/function-contract` CP0 UserLocal/TLS pointer slice | `RUN_DIR=build/unit/cp0_userlocal tb/unit/cp0/run.sh`；`make rtl-frontend-compile` | PASS：`cp0_timer: PASS`；RTL frontend `3/3` | CP0 `(4,2)` UserLocal 复位为零，MTC0/MFC0 可保存和恢复线程本地指针，且不影响 Context `(4,0)`；Config3.ULRI 置 1。该 slice 关闭 kernel context-switch 的 UserLocal 存储契约；RDHWR `$29` 用户态读取和完整 TLS runtime/linker 仍为后续任务。 |
| 2026-08-04 | `integration/function-contract` RDHWR `$29` UserLocal decode slice | `RUN_DIR=build/unit/cp0_rdhwr tb/unit/cp0/run.sh`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_rdhwr` | PASS：CP0 regression、RTL frontend `3/3` | SPECIAL3 `RDHWR rt,$29` 已解码为 CP0 `(4,2)` 回写路径；用户态仅当 `HWREna[29]` 置位时允许，禁止时走 CpU=0，kernel/CU0 路径保持可用。 |
| 2026-08-07 | `integration/function-contract` PIC/GOT-style runtime relocation | `make product-kseg0-runtime-multi-gate PRODUCT_KSEG0_RUNTIME_MULTI_DIR=build/unit_tb/product_kseg0_runtime_multi_picgot_two` | PASS：`REGRESSION_TEST_SUCCESS product_manifest_handoff_valid`；`REGRESSION_TEST_SUCCESS product_manifest_handoff_multi_wx` | RW segment 携带指向 R-only 数据和 RX 函数的两个 link-time alias，stage-1 按独立 source/runtime delta 修正，复制后的 RX text 经重定位函数指针调用并间接读取 rodata；W+X 负例仍在 handoff 前拒绝。完整 ELF GOT/PLT、动态 linker 和 PIC ABI 仍未闭合。 |
| 2026-08-07 | `integration/function-contract` RDHWR `$29` CPU firmware TLS linker/runtime gate | `make cp0-rdhwr-gate` | PASS：`SUCCESS: RDHWR USERLOCAL FIRMWARE GATE PASSED`；`build/soc_test/cp0_rdhwr/sim.log` | `cp0_sweep` 专用 linker script 导出 `.tdata`/`.tbss` 的 `__tls_start`/`__tbss_start`；真实 SoC firmware 以 linker TLS 基址安装 UserLocal，用户态通过 `RDHWR $29` 读取初始化槽、确认 tbss 清零并写回第二槽。完整 TLS relocation/model 和多线程调度 ABI 仍未闭合。 |
| 2026-08-07 | `integration/function-contract` CP0 MTC0 `rt` forwarding and UserLocal context-switch closure | `make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_cp0_mtc0_forward`；`make cp0-rdhwr-gate`；`make tlb-asid-allocator-gate`；`make mmu-context-contract-gate` | PASS：RTL frontend `3/3`、`SUCCESS: RDHWR USERLOCAL FIRMWARE GATE PASSED`、`REGRESSION_TEST_SUCCESS tlb_asid_allocator`、`REGRESSION_TEST_SUCCESS mmu_context_contract` | `mips_id_stage` 将 COP0/MTC0 的 `rt` 纳入通用 GPR forwarding/hazard 判定；真实 firmware 以无显式 `nop` 连续写入 UserLocal A->B->A 并由 RDHWR 验证顺序。 |
| 2026-08-07 | `integration/function-contract` bounded page-table root allocator | `make mmu-page-table-allocator-gate` | PASS：`REGRESSION_TEST_SUCCESS mmu_page_table_allocator` | 四个固定 4KB 对齐 root lease、耗尽、stale generation reject、释放后递增并复用均通过；PTE population、demand paging 和 production OS allocator 仍 deferred。 |
| 2026-08-05 | `integration/function-contract` RDHWR `$1` SYNCI_Step gate | `make cp0-rdhwr-gate RUN_DIR=/home/admin/mips32-soc/build/soc_test/cp0_rdhwr_synci FW_DIR=/home/admin/mips32-soc/build/firmware/cp0_rdhwr_synci`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_rdhwr_synci` | PASS：`SUCCESS: RDHWR USERLOCAL FIRMWARE GATE PASSED`；RTL frontend `3/3` | SPECIAL3 `RDHWR rt,$1`（标准编码 `0x7c08083b`，`rs=0, rd=1`）已接入 CP0-backed readback，返回 32-byte I-cache line step；kernel/user 权限由 `HWREna[1]` 控制。标准 HWR `$0..$3` 的统一 gate 见下一条 correction 记录。 |
| 2026-08-05 | `integration/function-contract` RDHWR permission/readback correction | `make cp0-rdhwr-gate CP0_RDHWR_DIR=build/soc_test/cp0_rdhwr_fixed CP0_RDHWR_FW_DIR=build/firmware/cp0_rdhwr_fixed`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_rdhwr_fixed` | PASS：真实 `$0..$3/$29` 编码、kernel readback、user HWREna 禁止/允许矩阵和连续流水读回均通过；RTL frontend `3/3` | 修正标准 `rs=0` 且 `rd` 分别为 0/1/2/3/29 的真实编码，修正 `$1` selector→CP0 `(7,1)`、`$3` address→CP0 `(9,1)`；增加 CP0 read hazard 串行化，避免相邻 MFC0/RDHWR 地址滞留。标准 RDHWR 0..3 与 UserLocal `$29` 现已闭合。 |
| 2026-08-04 | `integration/function-contract` 单核 LL/SC reservation contract | `make llsc-gate`；`make rtl-frontend-compile` | PASS：LL/SC firmware `REGRESSION_TEST_SUCCESS`；reserved SC、无 reservation SC、普通 store 清 reservation 三路径通过；RTL frontend `3/3` | `LL (opcode 0x30)` / `SC (opcode 0x38)` 已接入 CPU 控制、MEM 对齐和写回；SC 成功返回 `1`，失败返回 `0` 且不写内存。当前契约明确为单核、kseg1 非缓存行为模型：任意完成的普通 store 清 reservation；无外部 snoop/coherency 或多核原子性。 |
| 2026-08-05 | `integration/function-contract` CP0 LLAddr observability slice | `RUN_DIR=build/unit/cp0_lladdr tb/unit/cp0/run.sh`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_lladdr` | PASS：CP0 timer/MMU block gate；RTL frontend `3/3` | CP0 `(17,0)` `LLAddr` 现只读映射 CPU 单核 LL/SC reservation 的对齐地址；MFC0 可读，MTC0 不改变 reservation。该 slice 不扩展外部 snoop/coherency、多核原子性或 LLAddr 软件写入语义。 |
| 2026-08-05 | `integration/function-contract` LLAddr CPU firmware path | `make llsc-gate SOC_TEST_LLSC_DIR=/home/admin/mips32-soc/build/soc_test/llsc_lladdr LLSC_FW_DIR=/home/admin/mips32-soc/build/firmware/llsc_lladdr` | PASS：`SUCCESS: LL/SC FIRMWARE GATE PASSED` | 在真实 SoC firmware 中，`LL 0xA0002000` 后 `MFC0 $17` 读回对齐 reservation 地址；随后 `MTC0 $17, 0xDEADBEEF` 不改变读回值或后续 SC 成功。`llsc-gate` 入口改为将 firmware 输出路径绝对化，使调用者传入相对 build 路径时也可复现。 |
| 2026-08-04 | `integration/function-contract` CPU load retirement / VIC VEC_ID read fix | `make vic-cpu-gate`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_after_pic_load_fix`；`make rtl-frontend-compile` | PASS：VIC CPU firmware `REGRESSION_TEST_SUCCESS`；SoC smoke；RTL frontend `3/3` | 修复 blocking AXI/APB load 在 D-cache `data_data_ok` 边界被旧 WB 数据覆盖的问题：CPU 锁存完成 load data，WB 使用完成值；ID 增加 WB 边界 hazard bubble；当前 blocking D-cache 回退到已验证 single-entry ROB。VIC `VEC_ID` reset/priority/tie-break 读回恢复正确。ROB depth-2 late-response capture 仍 deferred。 |
| 2026-08-04 | `integration/function-contract` VIC CPU soft-IRQ clear/ERET and dual-source priority | `make vic-cpu-gate` | PASS：真实 CPU `Cause.IP` -> handler -> `VEC_ID=9` 高优先级 -> `ACK/SOFT_CLR`/ERET -> `VEC_ID=8` 低优先级 -> 清零 `ACTIVE/SOFT`；VIC CPU gate `REGRESSION_TEST_SUCCESS` | 修复两项中断竞态：soft pending 必须先于 CP0 IE 置位；handler 临时屏蔽 IE 后必须恢复原 Status，才能在 ERET 后服务第二个 pending source。当前闭合单核双源顺序/清除/ERET contract；真实 source-vector gate 另行覆盖 VEIC source-8，嵌套和多核中断仍 deferred。 |
| 2026-08-05 | `integration/function-contract` VIC source-8 VEIC vector integration | `make product-vectored-interrupt-gate` | PASS：`REGRESSION_TEST_SUCCESS product_vectored_interrupt`；TB 观察 `cpu_int=1`、`vec_id=8`、Cause.IP2、CPU 取指 `0x8000_0300` / PA `0x0000_0300` | testbench 在 VIC source-8 上施加 enable/soft pending/priority，验证真实 `apb_vic` arbitration -> CPU IRQ -> CP0 IP2 -> VEIC source-ID vector；只覆盖 opt-in source-8 路径，不代表嵌套抢占、所有源或完整 ISA compliance。 |
| 2026-08-04 | `integration/function-contract` PageMask-aware TLB even/odd lookup | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit_tb/tlb_asid_policy_pagesizes_final2`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_pagemask_pa`；`make soc-smoke` | PASS：TLB gate；RTL frontend `3/3`；SoC smoke `REGRESSION_TEST_SUCCESS` | `mips_tlb` lookup 现在根据命中 entry 的连续 MIPS PageMask 选择偶/奇 EntryLo，并将大页额外页内偏移折入有效 PFN：`0x0000->VA[12]`、`0x0003->VA[14]`、`0x000f->VA[16]`、至 `0x3fff->VA[26]`；gate 已覆盖 4 KiB、16 KiB、64 KiB、256 KiB、1 MiB、4 MiB、16 MiB 以及扩展 64 MiB 编码的半页选择和高位页内偏移保留。该证据仍是 block-level 变量页选择，未覆盖这些页尺度的 SoC/OS 压力、TLB multi-hit 或硬件 walker。 |
| 2026-08-04 | `integration/function-contract` TLB multi-hit MCheck path | `tb/unit/cp0/run.sh`；`make cpu-cp0-gate SOC_TEST_CPU_CP0_DIR=build/soc_test/cpu_cp0_after_ts`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_ts` | PASS：CP0 timer/MMU block gate；CPU/CP0 firmware gate；RTL frontend `3/3` | 重叠 valid TLB 项被独立检测，不再静默采用优先级项；`mips_mmu` 输出 fault `110`，CPU 映射到 MIPS `MCheck=0x18`，且不被判为 TLB refill；CP0 `Status[21]=TS` 在 MCheck 时 sticky 置位，MTC0 Status 不能清除。软件恢复策略、micro-TLB 和长期 OS 压力仍未闭合。 |
| 2026-08-05 | `integration/function-contract` TLBP duplicate-hit detection and reset recovery | `make tlb-asid-policy-gate TLB_ASID_POLICY_DIR=build/unit_tb/tlb_asid_policy_probe_mcheck`；`tb/unit/cp0/run.sh`；`make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_probe_mcheck` | PASS：TLB gate；CP0 timer gate；RTL frontend `3/3` | `TLBP` 现在同时报告 `probe_multi_hit`；CP0 在重复 probe 时置位 sticky `Status.TS`，同时保留最低索引作为诊断值。CP0 gate 验证 MTC0 不能清 TS、复位可清 TS；lookup/probe multi-hit 语义一致。micro-TLB/OS 级恢复策略仍 deferred。 |
| 2026-08-05 | `integration/function-contract` MMU/TLB baseline reconciliation | 文档审计：`docs/block_specs/mmu_tlb_spec.md` 与 `mips_tlb` RTL 对照 | PASS：规格明确当前为 direct dual-lookup 主 TLB；micro-TLB 不再被误标为已采用 | 修正规格中的架构状态：当前功能基线没有独立 micro-TLB，也没有 micro-TLB flush bubble；I/D 两端直接组合查询主 TLB。micro-TLB 仅作为后续性能/功耗优化，不影响当前 `RTL_FUNCTIONAL_SIM_READY` 结论。 |
| 2026-08-06 | `integration/function-contract` SoC 16KB PageMask runtime slice | `make product-mmu-pagemask-gate PRODUCT_MMU_PAGEMASK_DIR=build/soc_test/product_mmu_pagemask_pass` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_pagemask refills=1` | 真实 CPU/SoC 固件写入 PageMask[28:13]=`0x0003`，验证 ASID 7 下同一 32KB pair 的 even/odd 16KB EntryLo、页内偏移 PFN folding、数据读写完整性和成功/失败 mailbox；硬件 walker 仍保持当前明确的 4KB-only 合约。 |
| 2026-08-23 | `integration/function-contract` SoC PageMask four-size data-path recheck | `make product-mmu-pagemask-gate PRODUCT_MMU_PAGEMASK_DIR=build/soc_test/product_mmu_pagemask_current` | PASS：`REGRESSION_TEST_SUCCESS product_mmu_pagemask refills=3` | 当前 HEAD 的真实 CPU/SoC firmware 在 4KB/16KB/64KB/256KB 四个 demand-refill/data-access 阶段完成后才写入最终成功 mailbox；覆盖 distinct ASID、even/odd half、非零页内偏移和 PFN folding。Linux VM/page-table ownership、硬件 walker 的 4KB-only contract 和完整 OS 压力仍未闭合。 |
| 2026-08-23 | `integration/function-contract` QEMU system MMU PageMask RTL retire differential | `make qemu-system-mmu-pagemask-gate` | PASS：`TRACE_COMPARE_PASS records=276`；`QEMU system MMU PageMask architectural gate: PASS` | 同一份 PageMask firmware 在 RTL boot-ROM testbench 和 `mips32-soc-ref` 之间逐条 retire 比较通过，使用 BFC00200 RTL-compatible exception vector，覆盖 4KB/16KB/64KB/256KB、ASID 4-7、even/odd half、非零偏移、PFN folding 和显式 PageMask completion marker。为闭合该差异修复了 RTL address-exception 的 EntryHi.VPN2 更新，并通过 `cpu-cp0-gate`、`tlb-invalidate-gate` 回归。状态升级为 `SYSTEM_DIFFERENTIAL`（bounded corpus）；Linux VM ownership、多核 shootdown、完整 privileged/MMU 和 full ISA/QEMU differential 仍未闭合。 |
| 2026-08-23 | `integration/function-contract` QEMU system MMU process-pressure RTL retire differential | `make qemu-system-mmu-process-pressure-gate` | PASS：`TRACE_COMPARE_PASS records=1555`；RTL `REGRESSION_TEST_SUCCESS product_mmu_process_pressure refills=8` | standalone boot-ROM testbench 接入统一 retire schema；同一 firmware 在 RTL/QEMU 之间逐条比较通过，覆盖四个 software ASID、distinct PFN、context reuse、dynamic TLB shootdown、wired retention 和 post-shootdown refill。状态升级为 `SYSTEM_DIFFERENTIAL`（single-core bounded corpus）；OS scheduler/page-table ownership、多核 shootdown、Linux VM 和 full privileged/MMU differential 仍未闭合。 |
| 2026-08-24 | `integration/function-contract` QEMU system MMU context/shootdown RTL retire differential | `make qemu-system-mmu-contract-gate` | PASS：`TRACE_COMPARE_PASS`；`build/isa_ref/qemu_system_mmu_contract/completion_report.md` | 同一 ASID context firmware 在 RTL 与 `mips32-soc-ref` 之间逐条 retire 比较通过，覆盖 ASID-specific refill、ASID reuse、wired APB mapping、sticky invalidate+done、shootdown ACK 后架构 TLB 清除及 post-shootdown refill。修复 QEMU custom machine 在 ACK 时只清 host translation cache、未清 architecture TLB 的差异；保留 global/wired 项。状态升级为 `SYSTEM_DIFFERENTIAL`（single-core bounded corpus）；OS page-table ownership、scheduler、多核 IPI、Linux VM 和 full privileged/MMU 仍未闭合。 |
| 2026-08-24 | `integration/function-contract` QEMU system MMU OS page-table pressure differential | `make qemu-system-mmu-os-pressure-gate` | PASS：`TRACE_COMPARE_PASS`；RTL `mmu_os_pressure: PASS`；`refills=0x15`、`page_allocs=6`、task0/1/2 各 2 页 | 新增 opt-in `SOC_MMU_OS_PRESSURE` workload：三套独立 root/L2 页表、同一虚拟页的 task-specific PFN、三 ASID context switch、每次切换清理软件 pair snapshot，以及当前 task shootdown 后重新 demand refill；RTL 与 `mips32-soc-ref` 逐条 retire 比较通过。状态升级为 `SYSTEM_DIFFERENTIAL`（single-core bounded OS-style pressure）；Linux VM、production allocator/scheduler ABI、多核 shootdown、full privileged/MMU 仍未闭合。 |
| 2026-08-24 | `integration/function-contract` dual-core MMU shootdown target ACK | `make dual-core-soc-gate mmu-ipi-shootdown-pressure-gate rtl-frontend-compile` | PASS：dual-core SoC firmware、standalone IPI pressure、RTL frontend `8/8` | 修正双核 IPI ACK 语义：发送端不再直连自发 ACK，而是由目标侧 invalidate 事件打一拍后返回原 target/generation；双向 APB alias、target-1/target-0 路径和现有 stale/busy/timeout pressure 均通过。状态为 `SOC_INTEGRATED`（opt-in handshake）；Linux page-table owner/scheduler、完整多核 coherency protocol、Linux VM 与 full privileged/MMU 仍未闭合。 |
| 2026-08-24 | `integration/function-contract` L1 nonblocking real DDR + RTL/QEMU differential | `make l1-nonblocking-ddr-gate qemu-system-l1-ddr-differential-gate l1-nonblocking-cpu-stress-gate l1-nonblocking-cpu-two-error-reset-gate rtl-frontend-compile` | PASS：real CPU/L1/AXI/DDR4 controller、QEMU `mips32-soc-ref` retire differential、3-seed stress、two-error/reset recovery、frontend `8/8` | 新增 `SOC_L1_NONBLOCKING_DDR_ENABLE=1` 并修复 nonblocking CPU/ROB 在 IF-side stall 下重复 allocation 的提交 bug；firmware 覆盖两条 store、同 line merge/readback、第二条 line refill、最终 hit、late response/error/reset。状态为 `SYSTEM_DIFFERENTIAL`（opt-in bounded DDR path）；完整 maintenance/coherency、物理 PHY timing、Linux cache ABI 仍未闭合。 |
| 2026-08-07 | `integration/function-contract` hardware walker permission fault integration | `make cpu-hardware-walker-gate CPU_HARDWARE_WALKER_DIR=build/unit_tb/cpu_hardware_walker_permission`；`make page-table-walker-gate` | PASS：`REGRESSION_TEST_SUCCESS cpu_hardware_walker permission_faults=1`；`REGRESSION_TEST_SUCCESS page_table_walker` | CPU opt-in hardware walker 在成功 refill 后切换到无 X 权限 leaf，验证 permission fault 被锁存、不会重复发起同一 walker request，并进入 TLBL fault路径；walker 单测补齐 kernel/user load/store allow/deny 矩阵；CPU demand paging 及 OS page-table ownership 仍需独立 gate。 |
| 2026-08-05 | `integration/function-contract` TLB duplicate-write semantic fix | `make rtl-frontend-compile`；`make soc-smoke`；`make tlb-asid-policy-gate`；`make product-mmu-process-pressure-gate`；`make product-mmu-asid-context-gate` | PASS：RTL frontend `3/3`；SoC smoke；TLB policy；process pressure；ASID context (`refills=3`) | 修正 TLB multi-hit 判定：CPU refill 过程中产生的完全相同 VPN/ASID/PageMask/EntryLo 重复项视为幂等副本，不触发 MCheck；只有匹配范围或物理映射不同的冲突项才触发 lookup/probe multi-hit、MCheck 和 sticky `Status.TS`。移除临时 debug 输出并恢复 TLBP 的 TS 置位逻辑。 |
| 2026-08-05 | `integration/function-contract` dual-core IPI APB control slice | `make mmu-ipi-shootdown-gate`；`make apb-mmu-ipi-status-gate` | PASS：standalone IPI controller；APB register/control gate | 新增 vendor-neutral APB IPI 控制面：目标核/代次、ASID/VPN/scope 配置，send 命令，busy/pending/done/timeout/rejected/stale-ack 状态和 W1C 清除；外部 target-present/ack 端点验证 payload、匹配 ACK 与目标不存在超时。该切片尚未接入 `soc_peripheral_subsystem`/双核 CPU，不升级为 SoC 多核功能完成。 |
| 2026-08-05 | `integration/function-contract` IPI APB optional SoC wiring recheck | `make rtl-frontend-compile RUN_ROOT=build/unit_tb/rtl_frontend_ipi_integration`；`make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_after_ipi_apb`；`build/cpu_mmu_ipi_recheck_20260805.log` | PASS：RTL frontend `3/3`；default SoC smoke；CPU/MMU/IPI recheck all gates | `soc_peripheral_subsystem` 增加 `ENABLE_DUAL_CORE_IPI=0` 默认关闭的 `0x4000_A000` APB 窗口和外部 target/ack/invalidate 端点；默认单核 CPU、MMU context window 和既有 firmware 不变。重跑 IPI、APB IPI、TLB policy/invalidate、CPU context、ASID context、process pressure、EBase Mod、CacheErr gates 均通过。该证据仍不等同于双核 CPU、共享内存一致性或 OS scheduler 完成。 |
| 2026-08-05 | `integration/function-contract` full functional closure batch | `build/functional_closure_20260805.log` | PASS：CPU/CP0、TLB/MMU、IPI、cache-error、kseg0 runtime、DDR4 behavioral、QSPI/XIP behavioral 共 `38` 个 gate | 从干净编译状态重新执行当前 RTL 功能范围内的 CPU/MMU、Boot、cache、DDR4 behavioral 和 QSPI/XIP gate；期间修复 `tb_mmu_context_status.sv` 的 `.*` 输出声明缺失，避免旧 sim 日志掩盖当前 HEAD 的编译失败。该批次闭合当前 vendor-neutral RTL/仿真范围，不改变双核一致性与 production boot 等未纳入范围。 |
| 2026-08-08 | `integration/function-contract` MDU flush-to-IDLE closure | `make mdu-flush-gate`；后续 `make rtl-frontend-compile mdu-cpu-gate soc-smoke` | PASS：MDU flush gate；乘法/除法在途取消、HI/LO 保持、`done_pulse` 抑制及取消后重新发射均通过 | `mips_mdu.flush` 已接入 `mips_ex_stage`，由 CPU 当前 `exception_flush | ctx_restore_req` 驱动；该证据闭合异常/ERET/IRQ/上下文恢复期间的未提交 MDU 取消。BPU 无独立 flush 输入；Booth/radix-4、低延迟除法和 workload 性能仍 deferred。 |
| 2026-08-05 | `integration/function-contract` Phase closure rerun | `build/phase_closure_20260805.log`；`make phase2-complete`；`make phase3-complete`；`make phase3b-complete`；`make phase3c-complete` | PASS：Phase 2、3A、3B、3C 全部完成 | 汇总回归在当前 HEAD 重新通过，确认 APB IPI 接入和 context-status TB 修复没有破坏既有 DMA/timer/PIC、UART/flash/APB stress、CPU/CP0、PIC arbitration 和 firmware gates。覆盖率数值仍不是本阶段功能完整性判据。 |
| 2026-08-05 | `integration/function-contract` CPU/MMU unified completion gate | `make cpu-mmu-complete` | PASS：统一报告中的 21 个已冻结 CPU/MMU gate 全部通过；报告 `build/cpu_mmu_complete/cpu_mmu_completion_report.md` | 当前单核 MIPS32 software-managed MMU/TLB RTL contract、CP0 异常/返回、ASID/context/shootdown、MMU boot/kseg0 runtime、CacheErr/CacheOp/Tag、vectored interrupt、MDU、LL/SC 及 standalone dual-core IPI/APB contract 已闭合。Linux/OS boot、硬件 page-table walker、双核 CPU/共享内存 coherency、ECC、production EIC/VEIC 和 full ISA compliance 尚未实现，需求归属与架构规格待确认。 |
| 2026-08-05 | `integration/function-contract` dual-core CPU opt-in RTL integration | `make dual-core-frontend-compile` | PASS：`soc_top.ENABLE_DUAL_CORE=1` VCS elaboration；报告 `build/dual_core_frontend/dual_core_frontend_report.md` | 新增核 1 CPU/MMU/L1 实例、核 1 I/D read arbitration、dual-core opt-in 参数和核 0 APB IPI 到核 1 local invalidate/interrupt 接线；默认单核配置不变。双核 firmware execution、反向 shootdown、shared-memory coherency 和 scheduler 仍未签收。 |
| 2026-08-05 | `integration/function-contract` dual-core SoC execution gate | `make dual-core-soc-gate` | PASS：`DUAL_CORE_CORE1_ACTIVE pc=000004a8`；`REGRESSION_TEST_SUCCESS`；日志 `build/soc_test/dual_core/sim.log` | 双核 opt-in 下核 0/核 1 共享 Boot ROM/DDR behavioral 路径均可运行现有 smoke firmware，核 1 PC 已进入 firmware；核 0 APB IPI 到核 1 的 local invalidate/interrupt 具备接线。该 gate 尚未覆盖双核专用 firmware 的双向 shootdown、stale generation/timeout、共享内存 coherency 或 scheduler。 |
| 2026-08-05 | `integration/function-contract` dual-core IPI firmware gate and AXI routing fixes | `make dual-core-soc-gate RUN_DIR=build/soc_test/dual_core_gate_final` | PASS：`DUAL_CORE_CORE1_ACTIVE pc=00000020`；`REGRESSION_TEST_SUCCESS`；wrapper 输出 `dual-core SoC gate: PASS`；日志 `build/soc_test/dual_core_gate_final/sim.log` | 双核专用 firmware 在核 0 -> 核 1 路径完成 target/generation/payload/send/status，testbench 观察核 1 local invalidate 后接受 mailbox success；同时修正核 1 AXI BREADY 方向、D-only AR 请求字段选择和过早 marker 检查。该 gate 仍不覆盖反向 shootdown、stale generation/timeout/busy re-entry、异常隔离、共享内存 coherency 或 scheduler。 |
| 2026-08-05 | `integration/function-contract` dual-core dual-target IPI firmware gate | `make dual-core-soc-gate RUN_DIR=build/soc_test/dual_core_bidirectional2` | PASS：`DUAL_CORE_CORE1_ACTIVE pc=00000020`；`REGRESSION_TEST_SUCCESS`；wrapper 输出 `dual-core SoC gate: PASS`；日志 `build/soc_test/dual_core_bidirectional2/sim.log` | firmware 依次发送 generation 1 -> target 1、generation 2 -> target 0；testbench 分别观察核 1/核 0 local invalidate 后才接受 mailbox success。补齐 target-0 local invalidate 和 target-0 ack。该 gate 仍不代表独立 core-1 软件 IPI master，也未覆盖 stale generation/timeout/busy re-entry、异常隔离、共享内存 coherency 或 scheduler。 |
| 2026-08-05 | `integration/function-contract` independent core IPI-master alias gate | `make dual-core-soc-gate RUN_DIR=build/soc_test/dual_core_independent_ipi2` | PASS：`DUAL_CORE_CORE1_ACTIVE pc=00000020`；`REGRESSION_TEST_SUCCESS`；wrapper 输出 `dual-core SoC gate: PASS`；日志 `build/soc_test/dual_core_independent_ipi2/sim.log` | 核 0 使用 `0x4000_A000`、核 1 通过 AXI alias 使用 `0x4000_B000` 独立 controller；两个 controller 分别完成 generation/target/ack 和核 0/核 1 local invalidate。双核 SoC stale generation/timeout/busy、异常隔离、共享内存 coherency 或 scheduler 仍未闭合。 |
| 2026-08-05 | `integration/function-contract` dual-core SoC timeout fault-injection gate | `make dual-core-soc-gate RUN_DIR=build/soc_test/dual_core_timeout` | PASS：`DUAL_CORE_CORE1_ACTIVE`；`REGRESSION_TEST_SUCCESS`；日志 `build/soc_test/dual_core_timeout/sim.log` | 双核 firmware 先完成 target 1/target 0 的真实 IPI transaction，再通过 opt-in `0x4000_B03C` 目标不可见注入使两路 controller 均进入 sticky timeout，恢复目标并清除状态后写成功 mailbox。该寄存器是仿真故障入口，不是生产功能；stale-ack/busy-reentry 和独立复位/异常隔离仍保持 OPEN。 |
| 2026-08-05 | `integration/function-contract` QSPI quad development handoff failure classification and fix | `QSPI_QUAD=1 RUN_DIR=build/unit_tb/product_manifest_handoff_quad_fixed tb/unit/bootrom/run_product_manifest_handoff.sh`；x1 对照 `make product-manifest-handoff-gate` | PASS：quad 有效镜像、坏 CRC、11 个 manifest header/CRC 负例和 XIP timeout-to-DBE 全部通过；日志 `build/unit_tb/product_manifest_handoff_quad_fixed/sim_valid.log`、`sim_bad_crc.log`、`sim_xip_timeout.log` | 根因是 quad behavioral flash model 的 time-0 `0xff` 初始化与 testbench `$readmemh` 并发，覆盖了已加载 image，导致 Boot ROM 读回 `0xffffffff`；移除会覆盖外部加载镜像的初始化循环后恢复正确 payload/CRC handoff。model 仍是 vendor-neutral endpoint，不覆盖真实 flash 电气/时序、erase/program、签名 secure boot 或板级验证。 |
| 2026-08-05 | `integration/function-contract` CPU/MMU closure rerun after SoC timeout slice | `make apb-mmu-ipi-status-gate cpu-mmu-complete dual-core-frontend-compile`；`RUN_DIR=build/soc_test/dual_core_timeout_final tb/soc_test/run_dual_core_gate.sh` | PASS：APB IPI unit、CPU/MMU unified gate、dual-core frontend 和 dual-core SoC timeout gate 全部通过 | APB unit 新增 `0x3c` target-absent readback/clear 与 injected timeout 检查；CPU/MMU report `build/cpu_mmu_complete/cpu_mmu_completion_report.md`；dual-core SoC log `build/soc_test/dual_core_timeout_final/sim.log`。既有 URG exclusion/checksum warnings 仍按 P3 跟踪。 |
| 2026-08-05 | `integration/function-contract` dual-core stale-ack and busy-reentry gate | `RUN_DIR=build/soc_test/dual_core_faults tb/soc_test/run_dual_core_gate.sh`；`make apb-mmu-ipi-status-gate` | PASS：`REGRESSION_TEST_SUCCESS`；wrapper 输出 `dual-core SoC gate: PASS`；APB unit PASS | 双核 firmware 通过 `0x3c` 注入 ACK generation mismatch，验证 stale-ack 与后续 timeout；再屏蔽 ACK，在 busy 期间重复发送并验证 rejected 与 timeout。`0x3c` 为仿真专用 fault control，默认值为 0，不是生产功能。 |
| 2026-08-05 | `integration/function-contract` dual-core exception-isolation gate | `RUN_DIR=build/soc_test/dual_core_exception_isolation tb/soc_test/run_dual_core_gate.sh` | PASS：`DUAL_CORE_CORE1_EXCEPTION_INJECTED code=0A`；`REGRESSION_TEST_SUCCESS` | 通过默认关闭的仿真专用 core-1 RI stimulus 触发 core-1 CP0 异常采样；testbench 要求 core-1 异常可观测且 core-0 仍完成 IPI/reset 后的 `0xDEADBEEF` mailbox。 |
| 2026-08-05 | `integration/function-contract` dual-core core-1 reset isolation gate | `RUN_DIR=build/soc_test/dual_core_reset_isolation tb/soc_test/run_dual_core_gate.sh` | PASS：`REGRESSION_TEST_SUCCESS`；wrapper 输出 `dual-core SoC gate: PASS` | `0x3c[3]` 请求仅复位 core 1；testbench 观察 core 1 reset request，同时确认 core 0 继续完成成功 mailbox。该入口只覆盖 RTL reset isolation。 |
| 2026-08-05 | `integration/function-contract` default single-core regression after core-1 reset slice | `make soc-smoke SOC_TEST_RUN_DIR=build/soc_test/smoke_after_core1_reset` | PASS：`REGRESSION_TEST_SUCCESS`；`CPU_CP0_SUMMARY intr=10 syscall=1 ri=4 adel=1 eret=15` | 新增 core-1 reset request、IPI fault-control bit 扩展和 reset isolation testbench 检查未改变默认 `ENABLE_DUAL_CORE=0` 路径。既有 URG exclusion/checksum warnings 仍按 P3 跟踪。 |
| 2026-08-05 | `integration/function-contract` MMU fault retirement and CPU/MMU closure rerun | `make product-mmu-ebase-modified-gate`；`make cpu-mmu-complete` | PASS：Modified fault -> EBase handler -> D-bit repair -> ERET retry；CPU/MMU unified report 全部通过 | 修正 MEM 阶段在 MMU fault 时继续等待 cache `data_ok` 的死锁：translation fault 阻断 cache 请求并直接进入 CP0 异常路径。ASID pressure firmware 的过程页明确使用 dirty/valid、cacheable C=3 属性，避免把 uncached DDR response 路径混入 ASID/shootdown gate；该 gate 仍不声明 uncached DDR backend 完整性。 |
| 2026-08-06 | `integration/function-contract` P0 closure rerun | `source /etc/profile.d/modules.sh && module load vcs && make phase3-complete dual-core-soc-gate isa-r2-gate`；前置 `make rtl-frontend-compile cpu-mmu-complete ddr4-complete-gate` | PASS：Phase 3A `8/8`、Phase 3 coverage directed、CPU/CP0 firmware、双核 SoC、ISA R2 implemented subset 全部通过；联合命令退出码 `0`。报告：`build/uvm/phase3_complete/phase3_completion_report.md`、`build/cpu_mmu_complete/cpu_mmu_completion_report.md`、`build/soc_test/dual_core/sim.log`、`build/soc_test/isa_r2_sweep/sim.log` | 当前 P0 RTL/仿真 contract 的功能证据已重跑闭合。URG exclusion/checksum 和 coverage hierarchy 警告仍为 P3，不作为 RTL 功能失败；不扩展为物理实现、后端、Linux/OS 或完整 ISA 合规承诺。 |
| 2026-08-06 | `integration/function-contract` CPU/firmware LL/SC peer store coherency gate | `make llsc-coherency-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`LLSC_COHERENCY_PEER_NOTIF_INJECTED`；`LLSC_COHERENCY_PEER_INVALIDATED_SC_FAILED` | 验证在 dual-core opt-in + `SOC_COHERENCY_LL_SC` 下注入 peer store notification 时，core 0 的 LL/SC reservation 被正确清除，后续 SC 返回 0 且内存未写。不宣称 MESI/MOESI 或全共享内存 coherency。 |
| 2026-08-24 | `integration/function-contract` LL/SC exception-boundary and peer-notification recheck | `make llsc-gate llsc-coherency-gate`；`make dcache-coherency-gate`；`make rtl-frontend-compile` | PASS：单核 `LL -> SYSCALL -> ERET -> SC=0`；双核 peer notification `SC=0` 且内存保持；D-cache coherency `v0.3`；RTL frontend 通过 | CPU reservation 在 accepted exception/interrupt flush、context restore、普通 store 和 peer line notification 时清除。修正 coherency testbench 原先在第 3 次 LL 后注入、实际第 4 次 coherency LL 尚未建立的同步错误，避免误报；完整 memory ordering、原子性和 MESI/directory 仍未闭合。 |
| 2026-08-24 | `integration/function-contract` CPU load-return forwarding boundary | `make cpu-load-return-gate rtl-frontend-compile` | PASS：`CPU helper load-return forwarding gate: PASS`；RTL frontend `8/8` | 默认 blocking CPU/SoC 真实执行 helper 内 MMIO `LW`、返回后首个 caller consumer，并以 pass mailbox 证明 load-return 数据路径无软件 bubble；这是 bounded load-use/return 证据，不扩展为任意多在途 load forwarding、完整 ISA 或 Linux ABI。 |
| 2026-08-24 | `integration/function-contract` VIC full 32-source priority/ACK differential | `make vic-full-sources-gate qemu-system-vic-full-sources-differential-gate` | PASS：RTL `VIC_FULL_SOURCES_PASS sources=32 tie=lower-id`；QEMU `TRACE_COMPARE_PASS records=1166` | 真实 RTL 与 `mips32-soc-ref` guest 覆盖 32 个 software-pending source、4-bit priority、最高优先级选择、同优先级 lower-ID deterministic tie-break、ACTIVE/RUNNING_PRIO、ACK/W1C drain 和 source 31 enable mask。任意深度嵌套、多核 IRQ ownership、外部电气时序和 Linux IRQ ABI 仍未闭合。 |
| 2026-08-26 | `integration/function-contract` VIC bounded nested-priority and P1 recheck | `make vic-nested-gate interrupt-priority-gate p1-current-complete isa-implementation-audit` | PASS：真实 SoC `vic_nested: sequence 9->8->7->6 reverse-ACK PASS`；VIC unit `REGRESSION_TEST_SUCCESS vic`；`P1 current RTL/simulation extension gate: PASS`；`ISA_IMPLEMENTATION_AUDIT_PASS rows=19` | 真实 CPU/SoC firmware 新增四级 `9 -> 8 -> 7 -> 6` strict-priority preemption、每层 EPC 保存/恢复和 reverse ACK/SOFT_CLR unwind；P1 aggregate 在当前 HEAD 重跑 coherency stress、MMU/walker/scheduler、ISA R2 和 DDR4 closure。该证据只关闭 bounded 4-level nesting，不升级为任意深度 OS IRQ、完整 EIC/VEIC 或 full ISA。 |
| 2026-08-24 | `integration/function-contract` D-cache parity/CacheErr propagation | `make dcache-parity-gate` | PASS：`REGRESSION_TEST_SUCCESS dcache`；D-cache parity/CacheErr gate PASS | 显式仿真注入覆盖 D-cache tag parity 与 256-bit data-line parity；检测到 fault 时抑制 `cpu_data_ok`、拉起 `cpu_cache_error` 并进入 error response，清除注入后可重新读取 line。仅为 single-fault parity/error propagation contract，不宣称 SECDED correction、multi-bit ECC、L2 propagation、silicon reliability 或 OS cache-error policy。 |
| 2026-08-24 | `integration/function-contract` LL/SC interrupt-boundary directed slice | `make llsc-interrupt-boundary-gate` | PASS：`REGRESSION_TEST_SUCCESS llsc_interrupt_boundary`；`build/unit_tb/llsc_interrupt_boundary/sim.log` | 真实 CPU `interrupt_accept` 驱动 common exception flush，预置 reservation 在中断接受后清除；与 syscall exception gate 共同覆盖同步/异步边界。完整中断嵌套、memory ordering、原子性和 MESI/directory 仍未闭合。 |
| 2026-08-06 | `integration/function-contract` dcache coherency v0.3 ordering/reset/refill-collision slice | `make dcache-coherency-gate` | PASS：`REGRESSION_TEST_SUCCESS dcache_coherency_v03 notifications=4` | directed gate 覆盖双向同 line store visibility、accepted notification 顺序、partial-byte store、reset 后双核重新 refill、refill collision stale-line suppression 和 AXI error no-notification；仍不覆盖完整并发总序、写回 coherency 或 MESI/directory。 |

## 10. 已知未决问题

### 本轮执行证据（2026-08-03）

| 项目 | 命令 | 结果 | 结论 |
|---|---|---|---|
| CPU/MMU 四 ASID 压力 | `make product-mmu-process-pressure-gate` | PASS，`refills=8` | 已验证现有软件 context-switch、四 ASID 映射隔离和 shootdown 标记；尚不等同于 allocator/generation/真实 IPI shootdown |
| QSPI status 兼容性 | `make qspi-status-integration-gate` | PASS | 原 timeout/APB/quad shared-pin 行为未回归；command timeout/abort/busy 现在统一上报 canonical APB ERROR 并验证 W1C |
| QSPI taxonomy | `make qspi-error-taxonomy-gate`、`make qspi-retry-policy-gate` | PASS | canonical class/code、sticky、W1C、bounded retry 和 no-retry 已验证；command timeout/abort/busy 已接线，Boot ROM/init/auth/secure-boot policy 仍是边界 |
| CPU/MMU shootdown mailbox | `make tlb-shootdown-mailbox-gate`、`make product-mmu-context-cpu-gate`、`make mmu-ipi-shootdown-gate`、`make apb-mmu-ipi-status-gate`、`make dual-core-frontend-compile`、`make dual-core-soc-gate` | PASS（单核 mailbox + standalone dual-core IPI/APB + independent dual-core IPI-master alias firmware gate） | vendor-neutral mailbox、两个独立 IPI controller、target 1/target 0 local invalidate、generation ack、AXI B/R routing 和 mailbox success 已验证；双核 SoC stale/timeout/busy、异常隔离、共享内存一致性、page-table walker 或 scheduler 仍未闭合 |
| CPU/MMU ASID allocator | `make tlb-asid-allocator-gate`、`make product-mmu-context-cpu-gate` | PASS | 四槽分配/耗尽、stale generation 拒绝、释放后 generation 递增并复用，以及真实 CPU APB lease/readback 已验证；完整 page-table walker/OS allocator 仍不在当前 RTL contract |
| CPU/MMU context contract | `make mmu-context-contract-gate`、`make product-mmu-context-cpu-gate`、`make product-mmu-asid-context-gate` | PASS | allocator -> shootdown -> ack -> release/reuse、真实 CPU TLB invalidation/refill 已覆盖；仍未实现 page-table walker、scheduler 或多核 IPI |
| QSPI retry policy | `make qspi-retry-policy-gate` | PASS | timeout/init 一次 retry、retry exhaustion、CRC no-retry 已验证；尚未接入真实 controller/flash status |
| MMU APB context window | `0x4000_9000`；可选 dual-core IPI `0x4000_A000` | `make mmu-context-status-gate`、`make product-mmu-context-cpu-gate`、`make product-mmu-asid-context-gate`、`make mmu-ipi-shootdown-gate`、`make apb-mmu-ipi-status-gate`、`make dual-core-frontend-compile` PASS | 原 context window 保持兼容；`ENABLE_DUAL_CORE_IPI` 在 dual-core opt-in 下提供目标/代次/payload/send/status/W1C，并接入核 1 invalidate/interrupt；默认配置仍关闭。双核 scheduler、反向 shootdown 和共享内存一致性之外的扩展需求待确认，不能由本表单方面标为后置 |

### FPU 增量执行证据（2026-08-14）

| 项目 | 命令 | 结果 | 结论 |
|---|---|---|---|
| 精确 FPE Divide-by-zero slice | `make fpu-fpe-exception-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`build/soc_test/fpu_fpe_exception/sim.log` | `SOC_FPU_ENABLE=1` 下 CU1 与 FCSR Enable[div0] 开启，真实 CPU 执行 `DIV.S 1.0/0.0` 进入 ExcCode 15 handler；handler 读取 FCSR Cause/Flags=`0x00008420`，并确认 FPR4 未提交。该 gate 不覆盖完整 IEEE-754、其余 exception classes、rounding modes 或 OS FPU context。 |
| 精确 FPE Invalid slice | `make fpu-fpe-invalid-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`build/soc_test/fpu_fpe_invalid/sim.log` | `SOC_FPU_ENABLE=1` 下 CU1 与 FCSR Enable[invalid] 开启，真实 CPU 执行 `DIV.S 0.0/0.0` 进入 ExcCode 15 handler；handler 检查 Invalid Cause/Flags 并确认 FPR4 未提交。其余 exception classes、OS context 和完整 IEEE-754 仍未闭合。 |
| 精确 FPE Overflow slice | `make fpu-fpe-overflow-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`build/soc_test/fpu_fpe_overflow/sim.log` | 真实 CPU 执行最大有限 single `MUL.S` 乘 2，FCSR Enable[overflow] 触发 ExcCode 15；handler 检查 `Overflow|Inexact` Cause/Flags 掩码 `0x5` 并确认 FPR4 未提交。完整 range policy、double FPE 和 OS FPU context 仍未闭合。 |
| Opt-in FPU scheduler context slice | `make fpu-context-gate rtl-frontend-compile` | PASS：`REGRESSION_TEST_SUCCESS cpu_scheduler_integration`；`build/unit_tb/fpu_context/sim.log`；frontend `8/8` | scheduler context bank 现保存/恢复完整 32×FPR 与 FCSR；真实 CPU integration 检查 task-0 FPR/FCSR preservation 和 task-1 restore。该切片不等于 Linux lazy-FPU、signal-frame、ABI 或完整 COP1 context 语义。 |
| 精确 FPE Double 三类 slice | `make fpu-fpe-double-gate qemu-system-fpu-fpe-double-differential-gate` | PASS：RTL `REGRESSION_TEST_SUCCESS`；QEMU/RTL `TRACE_COMPARE_PASS`；`build/soc_test/fpu_fpe_double/sim.log`、`build/isa_ref/qemu_system_fpu_fpe_double_differential/completion_report.md` | 真实 CPU 与 `mips32-soc-ref` 分别执行 `DIV.D` 除零、`DIV.D 0/0` invalid、最大有限 double `MUL.D` 乘 2 overflow；三类均进入 ExcCode 15，Cause/Flags 一致，overflow 使用 `Overflow|Inexact=0x5` 掩码，目标 double pair 未提交，并经 ERET 进入下一向量。该 gate 使用 FCSR Cause 识别连续向量并完成 bounded retire differential；异常现场确认 CP0 输入 `except_pc` 已正确指向 faulting instruction，先前观察到的 `cp0_epc=0` 是同一 posedge 读取 NBA 更新前旧值。完整 IEEE-754、inexact/underflow、FPU OS context/ABI 仍未闭合。 |
| 精确 FPE Double Inexact slice | `make fpu-fpe-double-inexact-gate`；独立 system capture + `trace_compare.py --stop-after-mailbox` | PASS：RTL `REGRESSION_TEST_SUCCESS`；`TRACE_COMPARE_PASS records=49`；RTL trace 50 条 | 新增 `CVT.W.D 1.5` enabled-Inexact guest，真实 CPU/SoC 进入 ExcCode 15，Cause/Flags 均为 Inexact (`FCSR=0x00001084`)，double destination pair 不提交；QEMU `mips32-soc-ref` 独立捕获 50 条 retire 与 RTL 严格比较通过。标准 wrapper 在当前 host 偶发 QEMU timeout，但完整 artifacts 与 comparator 结果可复现；完整 double IEEE-754、OS FPU context/ABI 和 full COP1 compliance 仍未闭合。 |
| 精确 FPE Double Underflow boundary slice | `make fpu-fpe-double-underflow-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`build/soc_test/fpu_fpe_double_underflow/sim.log` | 最小正 double subnormal 乘 `0.5`，真实 CPU/SoC 进入 ExcCode 15，启用 Underflow Cause/Flags index 1，double destination pair 不提交；增加 operand-field fallback 处理 host real flush-to-zero。该 gate 不宣称 exact tininess/inexact policy、QEMU differential、完整 IEEE-754 或 OS FPU ABI。 |
| 精确 FPE Underflow boundary slice | `make fpu-fpe-underflow-gate` | PASS：`REGRESSION_TEST_SUCCESS`；`build/soc_test/fpu_fpe_underflow/sim.log` | 真实 CPU 执行涉及最小正 single subnormal 的 `MUL.S`，验证选定 underflow/inexact Flags/Cause 与 enabled trap/no-commit 路径。该单向量不等同于完整 tininess、rounding、inexact 或 IEEE-754 policy。 |
| FCSR rounding mode SoC slice | `make fpu-rounding-gate`、`make mips-fpu-compare-gate` | PASS：`REGRESSION_TEST_SUCCESS`；SoC log 记录 RM `00/01/10/11` 结果 `2/2/-1/2/-2`，primitive gate PASS | `CVT.W.S` 现在使用 FCSR.RM[1:0] 的 nearest-even、RZ、RP、RM；固定 `ROUND.W.S` 不受 RM 改变。范围边界和完整 IEEE-754 exception signaling 仍未闭合。 |
| FPU invalid/underflow primitive boundary | `make mips-fpu-flags-gate` | PASS：`REGRESSION_TEST_SUCCESS mips_fpu_flags invalid=3 underflow=1`；`build/unit_tb/mips_fpu_flags/sim.log` | 补齐 behavioral primitive 对 single `Inf-Inf`、double `Inf/Inf`、double `0*Inf` invalid 和 minimum-normal-times-half double underflow 的分类；不扩展为完整 IEEE-754、double precise FPE 或 OS FPU ABI。 |
| QEMU FPU W-conversion indefinite boundary | `make fpu-single-gate qemu-system-fpu-single-differential-gate` | PASS：RTL `FPU PASS`；QEMU system-mode direct run `FPU PASS`；`TRACE_COMPARE_PASS records=1248` | 项目自有 QEMU 9.2 patch 将 invalid/overflow 的 `CVT/ROUND/TRUNC/CEIL/FLOOR.W.{S,D}` 结果统一为 MIPS indefinite `0x80000000`，并纳入 custom-machine 构建输入 hash；完整 IEEE-754 和 FPU OS/ABI 仍未闭合。 |

| 优先级 | 问题 | 对计划的影响 | 处理条件 |
|---|---|---|---|
| P0 | 当前 RTL/仿真功能闭合：Boot ROM/异常向量、MMU 基础路径、DDR4 controller、QSPI/XIP、UART、WDT 和 CPU/MMU gate | **已完成当前冻结 contract**：本次 Phase 3、CPU/MMU、DDR4 和前端 gate 重跑通过 | 仅在 RTL contract 发生变更时增量重跑对应 gate；不新增物理实现任务 |
| P0 | 双核 CPU/MMU 运行时闭合：核 0/1 firmware execution、core 0/1 IPI 发起、双核 uncached mailbox、复位/异常隔离和 AXI response routing | **已完成已冻结的 TLB/IPI/异常基础子集**：双核 opt-in firmware 已验证两个独立 IPI controller、核 0/核 1 local invalidate、generation ack、SoC target timeout、stale-ack、busy re-entry rejection、core-1 reset isolation 和 core-1 exception isolation | shared-memory coherency、page-table walker、scheduler/OS 等不属于当前 P0 contract；另立需求后再实现 |
| P1 | CPU/MMU 与 ISA/系统软件扩展：共享内存 coherency、更多页尺度 SoC/OS 压力、长期 scheduler/shootdown、权限/多段 runtime、完整 ISA compliance 和 kernel/OS boot | **当前 RTL/仿真 bundle 已由 `make p1-current-complete` 闭合；产品级扩展仍 ACTIVE** | 每项单独冻结 RTL/firmware contract 和验收 gate；不得以当前 bundle gate 代替完整 MESI/directory、完整 ISA/FPU 或 Linux/OS gate |
| P0 | UART RTL pins/IRQ wiring、外部 RX waveform、SoC RX/PIC/RBR behavioral 路径和 CTS flow-control SoC 集成已有证据；WDT APB/reset pulse、boot-status retention 和 Boot ROM failure slice 已通过 | **已完成当前 RTL/仿真 contract** | 仅在 UART/WDT contract 发生变更时增量重跑负例、超时、复位和错误分类 gate |
| P3 | coverage 数值仍低于 99%；exclusion manifest 和 strict URG metadata hygiene 已闭合，但整体 percentage threshold 仍未达标 | 不以 coverage 百分比宣称 signoff；必须继续补齐真实覆盖对象，不降低阈值或用 exclusion 掩盖未覆盖对象 | `python3 tb/coverage/audit_exclusions.py` PASS；`make coverage-strict-clean-gate` PASS；threshold report 位于 `build/signoff/current_contract/current_contract_signoff_report.md` |
| P1 | standalone x1/quad AXI/XIP bridge、shared-pin arbiter、SoC memory quad opt-in 和 development handoff 已通过；APB command、AXI acceptance、request/grant、timeout/abort/recovery 和 endian ABI 均有证据 | **CONTRACT_CLOSED（当前 RTL/仿真范围）** | 仅在当前 contract 变更时增量回归；production boot、device-specific status 和 secure-boot policy 不属于当前范围 |
| P2 | `dcache_nb` 与其 TB 已废弃并从当前集成线移除 | 不属于当前 RTL 功能计划或产品 baseline | 无后续接入任务；阻塞式 `dcache.v` 继续作为 D-cache 基线 |
| P1 | 当前 RTL contract 之外的扩展：shared-memory coherency、ECC/完整 cache-error policy、嵌套/全源 EIC/VEIC、更多 outstanding、MMU/Linux boot | 不阻塞 `RTL_FUNCTIONAL_SIM_READY`；当前基础 contract 不能替代这些扩展的独立验收 | 每项建立独立 spec/RTL/firmware/UVM 变更集，并按本计划的五级状态推进 |
| P3 | coverage scope 配置中的 3 个不存在模块模式已删除 | 当前 `cov.cfg` 不再引入已知 `VCM-HFUFR` scope warning；新 VDB 仍需通过 strict hygiene gate | `tb/uvm_tb/cov.cfg`、`make coverage-strict-clean-gate` |

## 11. 当前剩余任务（仅 RTL 前端）

以下任务是当前阶段的实际清单；完成条件是 RTL 可编译、仿真可重复且行为证据完整。

| 优先级 | 剩余任务 | 当前状态 | 关闭证据 |
|---|---|---|---|
| P1 | 双核 shared-memory coherency v0.4 | `multicore_coherency_spec.md` 已升级；`dcache-coherency-gate`、`llsc-coherency-gate` 和独立双核 firmware stress gate 已通过；完整 MESI/directory 和并发总序仍属于后续扩展 | 当前 evidence 覆盖双向 store visibility、accepted notification order、reset/refill、refill collision、partial-byte/error boundary、L1/L2 stale-line invalidation、LL/SC reservation invalidation 和 8 轮双核 shared-memory stress |
| P1 | MMU/运行时扩展 | 多段 runtime/W^X loader、PIC/GOT-style 单 relocation、walker/refill permission matrix、四种页尺度 walker、bounded page-table root allocator、TLS linker/runtime、连续 UserLocal context-switch slice 和 opt-in SoC hardware-walker AXI refill 已通过；完整 ELF GOT/PLT、TLS relocation/model、CPU 执行级 demand paging、长期 scheduler/shootdown 和 production page-table ownership 仍未闭合 | `build/unit_tb/product_kseg0_runtime_multi_picgot_final/sim.log`、`sim_multi_wx.log`、`build/unit_tb/page_table_walker/sim.log`、`build/unit_tb/page_table_tlb_refill/sim.log`、`build/unit_tb/mmu_page_table_allocator/sim.log`、`build/soc_test/mmu_hardware_walker_soc/sim.log` 与 `build/soc_test/cp0_rdhwr/sim.log`；后续继续补完整 loader、CPU demand paging 和 OS 压力 gate |
| P1 | 中断与缓存错误扩展 | 有限 VEIC source-vector、四级 bounded nested priority 和 cache-error/SECDED primitive 已验证；任意深度/OS EIC/VEIC、完整 cache ECC policy、SoC IRQ escalation 仍未闭合 | `make interrupt-priority-gate`, source/priority/nesting, ECC fault injection, IRQ/status/recovery gates |
| P1 | ISA 与系统软件扩展 | ISA R2 implemented subset 已通过；QEMU 逐 retire differential harness 已接入，但完整 ISA compliance、FPU、kernel/OS boot 和长期 mismatch signoff 仍未闭合 | 扩展同一 guest image 的 RTL/QEMU trace 回归，并建立 privileged/异常覆盖证据 |
| P2 | 阻塞式 D-cache 与默认基线维护 | `rtl/cache/dcache.v` 是默认路径，D-cache NB 已废弃；只维护现有 block/CPU/SoC 证据 | RTL 变更后重跑 `make rtl-frontend-compile soc-smoke phase3-complete` 及受影响 gate |
| P2 | 当前 contract 的证据维护 | registry、Phase 报告和 commit 已建立；后续 RTL 变更需要同步更新命令、日志、基线和残余风险 | `docs/functional_evidence_registry.md` 与 `docs/functional_completeness_plan.md` 可追溯 |
| P3 | coverage/exclusion 治理 | manifest synchronization 已闭合；strict URG metadata hygiene 和整体 coverage 百分比仍 OPEN | 新 coverage VDB 必须使用 `make coverage-strict-clean-gate` 验证；不得降低阈值或用 stale exclusion 掩盖未覆盖对象 |

`p1-current-complete` 是当前唯一集成线上的 P1 RTL/仿真聚合验收入口。它串联
frontend compile、CPU/MMU、双核、coherency v0.1、walker、scheduler、SECDED、
VEIC、ISA R2 implemented subset 和 DDR4 closure gates，并写出固定路径报告。
该入口不吸收没有独立 spec、RTL、firmware 和验收 gate 的产品级扩展。

### 当前阶段退出条件

1. 目标 RTL 和协议验证依赖在固定集成线可重复编译/elaborate；
2. unit、firmware、SoC/UVM 仿真覆盖正常、复位、背压、错误和超时路径；
3. 每个 gate 都有命令、日志、基线 commit 和残余风险；
4. 发布结论使用 `RTL_FUNCTIONAL_SIM_READY`，不得将其扩展为本阶段未定义的产品级结论。

### SVA simulation assertion slice (2026-08-08)

`make sva-gate` provides the first executable assertion gate for the current
RTL contract. It binds VCS SVA properties to the real `axi_sram` and
`apb_vic` interfaces and runs a dedicated `reset_sync` AASD unit scenario.
The slice checks payload stability under backpressure, single-outstanding
burst termination, APB setup/wait/error behavior, and synchronized reset
release. It is simulation assertion evidence only; formal proof, CDC/RDC,
lint, and final assertion-coverage signoff remain deferred.

### 当前文档范围声明

本计划只记录 RTL、前端编译/elaboration、unit/firmware/SoC/UVM 仿真、协议检查、错误路径、
复位、背压、覆盖率和可追溯报告。未列入本阶段的项目不作为当前 P0/P1 任务、依赖或关闭条件。

### L2 CPU/L1/DDR focused closure (2026-08-08)

`make l2-end-to-end-gate` and `make l2-end-to-end-gate L2_WRITEBACK=1` both
pass with `L2_E2E_TEST_SUCCESS`. The focused firmware drives a real cached
line cold read, same-line hit, L1 conflict/eviction, and WT/WB KSEG1 readback;
the testbench counts downstream L2-to-DDR AXI handshakes and logs target-line
read/write activity. L2 8-way capacity eviction and complete WB dirty-victim
`AW/W/B` evidence remain covered by the L2 block gate because the current
behavioral DDR model exposes a 128KB address window; no SoC-level capacity or
performance claim is made here.

The `l2-cpu-gate` uses `SOC_L2_CPU_GATE` to run the complete L2 firmware without
the generic late JTAG/reset stress sequence. That sequence remains covered by
the general reset-recovery gates; keeping it out of this long firmware run
prevents the late reset from restarting the test after the shared watchdog
budget has mostly elapsed. The gate uses a 20 ms watchdog for the deliberately
long 8 KB cache sweep; the default SoC watchdog remains 5 ms.

### L2 nonblocking dirty writeback buffer closure (2026-08-25)

The opt-in `l2_cache_nb` path now snapshots dirty victims into a fixed
four-entry writeback buffer at miss acceptance. A miss requiring a dirty
victim is backpressured when all four slots are occupied; the buffered line
data is used for downstream `AW/W`, and the slot is released only after the
downstream `B` response. `make rtl-frontend-compile`, the L2 concurrency unit
gate, and the explicit `make l2-nonblocking-end-to-end-gate` real SoC smoke pass
after the change.

The directed L2 concurrency test now fixes `WB_DEPTH=4`, establishes four
known dirty resident lines, continuously replaces them in one set, and checks
the backing-memory scoreboard. The fresh run reports
`peak_mshr=8 peak_wb=4 hit_under_miss_beats=32` and
`REGRESSION_TEST_SUCCESS l2nb (reads_checked=63)`. This closes the bounded
four-entry dirty-victim buffering contract. The same test now also drives
clean and dirty snoops: clean lines invalidate directly, while dirty lines are
snapshotted to the WB buffer and drained through downstream `AW/W/B` before a
refill. The standard gate reports
`peak_mshr=8 peak_wb=4 hit_under_miss_beats=32` and
`REGRESSION_TEST_SUCCESS l2nb (reads_checked=65)`. The same-cycle matching
snoop/request case is backpressured before the invalidation edge. This closes
the bounded snoop invalidate/writeback and ordering slice. Coherency/directory
and CPU default-path selection remain open.

### L2 nonblocking AXI error and reset recovery (2026-08-25)

The L2-NB miss engine now distinguishes an observed AXI error from completion
of the complete downstream transaction. A refill with a non-OKAY `RRESP` keeps
`RREADY` asserted through the burst, never installs the line, marks the MSHR
terminal only at `RLAST`, and resolves every merged waiter with `SLVERR`.
A dirty-victim `BRESP` error skips the refill, propagates `SLVERR` to the
associated order entries, and releases the writeback slot and MSHR. Failed
MSHRs cannot accept new secondary waiters while they are being retired.

The updated `make cache-concurrency-gate` passes with
`peak_mshr=8 peak_wb=4 hit_under_miss_beats=33` and
`REGRESSION_TEST_SUCCESS l2nb (reads_checked=68)`. Its directed tail covers
merged refill errors, a clean retry after a failed refill, dirty-writeback
error recovery, and reset during an active refill. The real CPU/L1/SoC
`make l2-nonblocking-end-to-end-gate` and `make rtl-frontend-compile` also
pass. This closes the bounded L2-NB AXI error/drain/resource-recovery slice;
snoop-writeback error reporting, arbitrary error/reset interleavings, full
coherency/directory behavior, and product signoff remain open.

### 2026-08-25 current-head dual-core coherency recheck and parity fix

The current-head `make coherency-stress-gate` recheck initially reproduced a
core-0 `CacheErr` during the shared-memory stress. The failure was caused by
the coherency-mode uncached-store write-through update changing a resident
D-cache line without recomputing its data/tag parity. The fix updates the
resident line through one byte-merge helper and refreshes both parity bits.

Fresh gates now pass: `make coherency-stress-gate`,
`make dcache-coherency-gate`, `make dual-core-soc-gate`,
`make llsc-coherency-gate`, and `make rtl-frontend-compile` (`8/8`). The
bounded dual-core shared-memory coherency gate is closed again for the current
HEAD. This remains a write-invalidate/notification contract; full
MESI/directory ordering and commercial coherency signoff remain outside scope.

### Micro-TLB and L1 transaction closure update (2026-08-10)

`make product-mmu-micro-tlb-gate` now compiles the real SoC with
`SOC_MICRO_TLB_ENABLE=1` and verifies D-side hits in the product MMU boot
workload and I-side hits in the translated-instruction vector workload. The
default MMU boot and `make rtl-frontend-compile` matrix were rerun. The
standalone L1 transaction block was also corrected so one secondary request
per MSHR is retained and receives a response after the shared refill;
`make l1-nonblocking-gate` and `make cache-concurrency-gate` pass. The L1
block remains disconnected from the CPU's blocking D-cache interface, so
full CPU hit-under-miss, maintenance, coherence and error-backpressure
closure remain open.

The L1 transaction unit gate now also holds the downstream line port in
backpressure while four dirty victims occupy the fixed four-entry writeback
queue, rejects the fifth dirty replacement, and verifies all queued writebacks
drain after readiness returns. This closes the standalone WB full/empty
contract; it does not claim CPU default-path switching, nonblocking maintenance,
coherence, or unrestricted error/reset timing.

### L1 CPU error/reset closure update (2026-08-20)

The opt-in CPU/D-cache path now passes the full-ROB same-cycle error/retire/tag
reuse regression, sequential two-line error recovery, three-seed stress and a
dedicated `make l1-nonblocking-cpu-error-reset-gate`. The latter waits for a
real L1 MSHR, resets before the refill response, then verifies post-reset
SLVERR injection and precise CacheErr/ErrorEPC recovery. The two-line gate now
also issues two independent misses back-to-back and verifies simultaneous
responses obey precise exception semantics: the first CacheErr retires, the
younger request is flushed, and replay reaches the success mailbox. The new
`make l1-nonblocking-cpu-two-error-reset-gate` asserts reset after both MSHRs
are active and verifies both faults are re-injected after reset before recovery
reaches the mailbox. Three-or-more errors, arbitrary reset/error timing,
maintenance/coherence, physical DDR failures and default-path switching remain
open.

### L1 maintenance compatibility closure update (2026-08-20)

`make l1-nonblocking-maintenance-compat-gate l1-nonblocking-maintenance-cpu-gate`
passes the CPU CACHE completion
and stall contract plus CP0 TagLo/TagHi/SYNC tests. The opt-in L1 adapter now
routes `Index_Invalidate_D` and `Hit_Invalidate_D` to the line cache only after
L1 bridge traffic, response FIFO, active request and outstanding count are
idle; the operation completes through a one-cycle handshake. Tag, writeback and
unsupported operations still use legacy dcache. This closes the two scoped
invalidates while nonblocking tag/writeback maintenance, concurrent maintenance
before drain, full ordering, and OS cache ABI remain open. The CPU gate uses the
real SoC hierarchy to count both L1 maintenance issues and the subsequent line
requests; the direct unit gate checks the architectural data invalidation.

The opt-in SVA checker is included in `make sva-gate` and the L1 error/reset
gate was rerun with `SVA_ENABLE=1`; no maintenance-idle assertion fired. This
is simulation assertion evidence, not formal signoff.

The same SVA configuration now checks L1 response FIFO depth, two-MSHR and
four-entry writeback bounds, and reset resource flush. These checks remain
simulation assertions rather than formal signoff. The aggregate
`current-contract-signoff` prerequisite list now includes the maintenance
compatibility gate, CPU error/reset gates, and `sva-gate` so the unified entry
point executes this evidence before its existing UVM/coverage stages.

### L1 nonblocking writeback maintenance closure update (2026-08-26)

The opt-in `l1_cache_nb` path now owns the documented D-cache writeback
maintenance operations `Index_Writeback_Invalidate_D` (`00001`),
`Hit_Writeback_Invalidate_D` (`10101`), and `Hit_Writeback_D` (`11001` or
the MIPS32 R2 alias `11101`) in
addition to the existing invalidate operations. A dirty matching line is
placed in the existing ordered writeback FIFO, CPU requests are held while
the maintenance transaction is active, and `cache_maint_done` is delayed
until the AXI line write has drained. The unit gate checks the writeback
address/data and that writeback-only retains a valid clean line; the real CPU
gate covers the instruction encodings through the adapter.

The same opt-in path now also routes `Index_Load_Tag_D` (`00101`) and
`Index_Store_Tag_D` (`01001`) to the L1 tag array. TagLo uses the bounded
architectural tuple valid/dirty/tag in bits `[22:0]`; the unit gate verifies
load/store/load round-trip and the CPU gate verifies the CP0 path on a real
cached line. Full cache ordering, coherency, physical DDR error timing and the
production OS cache ABI remain open.

### 2026-08-26 opt-in L1 nonblocking CPU contract aggregate

The opt-in L1 nonblocking cache is now exercised through the real CPU/D-cache
path by a single aggregate entry, `make l1-nonblocking-cpu-complete-gate`.
The aggregate runs compatibility and multi-request SoC smoke, three seeds of
mid-flight-reset stress, single/two-error recovery, reset-in-flight recovery,
and CACHE maintenance compatibility. All runs pass on the current head, and
the adapter's legacy observation aliases no longer emit a width-truncation
warning during opt-in VCS elaboration. This closes the bounded opt-in CPU
hit-under-miss/ROB response contract. Uncached/peripheral accesses and
unsupported CACHE operations intentionally remain on the legacy dcache,
default blocking mode is unchanged, and full nonblocking coherence and
physical DDR error behavior remain open.

### 2026-08-26 MMU OS-pressure aggregate boundary

Added `make mmu-os-pressure-complete-gate` as the single bounded entry for
software-managed CPU demand refill, ASID-specific process pressure, four
PageMask phases, TLB shootdown protocol pressure, and the corresponding
system-mode RTL/QEMU retire comparisons. The aggregate is intentionally named
for its evidence boundary: it closes single-core OS-style page-table and
shootdown pressure, but does not claim multicore IPI ownership, Linux page-table
allocator/VM ABI, arbitrary demand paging, or full privileged/MMU compliance.
The same aggregate now executes the vendor-neutral QSPI quad/status and DDR4
controller/stress/status/PIC bundle; physical PHY/JEDEC/device signoff remains
outside the aggregate.
The QSPI portion is itself consolidated as `qspi-vendor-neutral-complete-gate`,
covering command, flash model, retry/status, timeout, pad/arbiter and x1/quad
XIP paths without changing the default x1 configuration.

### COP0 shadow-register-set closure update (2026-08-23)

The default compatibility boundary remains unchanged: with
`SOC_SRS_ENABLE=0`, MIPS32 R2 `RDPGPR` (`rs=0x0a`) and `WRPGPR` (`rs=0x0e`)
decode as Reserved Instruction. The opt-in path now provides sixteen 32-entry
GPR banks, software-selected `SRSCtl.PSS/CSS` state, fixed-field decoder
checks, and CPU writeback/readback for `WRPGPR`/`RDPGPR`.

The closure evidence is reproducible with
`make mips-control-srs-gate mips-regfile-srs-gate srs-gate`; the final gate
uses `SOC_SRS_ENABLE=1` and a real firmware sequence that selects PSS, writes
and reads a shadow register, and reaches the SoC mailbox. This is a bounded
software-selected SRS subset. The follow-on `make srs-exception-gate` verifies
exception entry `CSS -> PSS`, `ESS -> CSS`, a PSS-bank read in the handler,
and `ERET` restoration `PSS -> CSS`. The dedicated
`make qemu-system-srs-map-differential-gate` verifies a real VIC Cause.IP2
interrupt maps through SRSMap to CSS=3 on both RTL and QEMU, while
`make srs-nested-gate qemu-system-srs-nested-differential-gate` verifies the
EXL-held nested-fault policy. External VEIC/EICSS mode and Linux SRS ABI are
explicitly still open. The scheduler context
ownership slice is now covered by `make srs-scheduler-context-gate`: the
context image carries all sixteen shadow GPR banks and restores the target
CSS/PSS/ESS together with the ordinary GPR/FPR/CP0 image.

# Current closure boundary

### QEMU system-mode MMU differential update (2026-08-23)

`make qemu-system-mmu-refill-differential-gate` now passes the reproducible
RTL/QEMU system-mode retire comparison for the bounded software-managed 4KB
demand-refill guest (`TRACE_COMPARE_PASS records=3288`). The custom
`mips32-soc-ref` machine exports the opt-in MMU guest state to QEMU's patched
TLB helper, selects the RTL-compatible `0x80000180` exception vector, and
uses a 64-entry reference TLB to match the RTL index contract. The default
identity-TLB machine path remains unchanged. This evidence does not close
full MIPS privileged/MMU compliance, OS page-table ownership, multicore
shootdown, larger-page demand paging, Linux boot, or production signoff.

The active phase is RTL and simulation only. The recent closure work verifies
the dual-core cache notification path, bounded QSPI retry integration, the
page-table walker and scheduler blocks, a vendor-neutral SECDED primitive, and
VEIC CPU routing is now an opt-in SoC path and is covered by the vectored
interrupt gate. This does not constitute a complete OS/Linux port, full
MIPS32 compliance suite, or complete production software policy. Those items
require their own RTL and firmware evidence and must not be marked complete
from block-level gates.

### COP0 SRSMap state closure update (2026-08-23)

The opt-in SRS implementation now exposes CP0 register `(12,3)` as SRSMap.
All eight 4-bit Cause.IP-to-shadow-set mapping entries reset to zero, are
writable through MTC0, and read back architecturally. The selected IP mapping
is now used on interrupt entry to choose CSS, with PSS retaining the previous
set; ERET restores CSS from PSS. The default interrupt vector path and
`SOC_SRS_ENABLE=0` behavior remain unchanged. IP-based SRSMap mapping and the
EXL-held nested-fault policy are closed for this bounded opt-in contract;
external VEIC/EICSS policy and Linux SRS ABI remain open.

Evidence: `make srs-map-gate`, `make srs-exception-gate`,
`make qemu-system-srs-map-differential-gate`, and the default frontend
compile. The CP0/SoC tests check IP2 mapping and mapped interrupt entry /
ERET; the tests run with `SOC_SRS_ENABLE=1` and leave the default path
unchanged.

The nested policy is now independently covered by
`make srs-nested-gate qemu-system-srs-nested-differential-gate`: a nested
`SYSCALL` while EXL is set redirects without replacing CSS/PSS or EPC, and
the RTL/QEMU retire traces compare through mailbox completion. External
VEIC/EICSS policy and Linux SRS ABI remain open.

### 2026-08-23 Hardware walker/TLB refill handshake

`mips_page_table_tlb_refill` now holds every successful hardware-walker
response as a TLB write transaction even when the consumer is already ready
in the response cycle. The permanently-ready case is covered by
`make page-table-tlb-refill-gate`; the walker unit, CPU hardware-walker
integration, and `make rtl-frontend-compile` (8/8) were rerun successfully.
This closes a bounded valid/ready integration hole only. The walker remains
two-level and single-outstanding-read, with the four supported page-size masks
covered separately; Linux VM ownership, general demand paging, and full OS
shootdown remain open.

### 2026-08-24 hardware walker page-size extension

The opt-in hardware walker now supports the four contract page sizes 4KB,
16KB, 64KB and 256KB through `SOC_HARDWARE_WALKER_PAGE_MASK` using masks
`0x0000/0x0003/0x000f/0x003f`. The walker,
CPU refill path and TLB refill mask use the same page-size selection, including
L2 index calculation, PFN alignment checks, physical address offset assembly
and even/odd page selection. `make page-table-walker-page-sizes-gate` passes
all four unit instances, with the default remaining 4KB. This advances the
hardware capability but does not close arbitrary demand paging, OS-owned page
tables, Linux VM or complete privileged/MMU compliance.

### 2026-08-24 MIPS32 R2 PREFX system differential

`make isa-r2-gate` and the system-mode retire differential pass for the COP1X
`PREFX` encoding (`0x4d28000f`) with `SOC_FPU_ENABLE=0`. RTL and the patched
QEMU 9.2 custom machine treat it as an ordered integer no-op, with QEMU using
the `ISA_MIPS_R2` capability check before optional COP1 dispatch. This is
implemented-subset evidence only; full ISA/privileged/MMU, IEEE-754/FPU ABI,
Linux boot, and complete ISA/QEMU differential remain open.

### 2026-08-24 MIPS32 R2 RDHWR differential extension

The ISA R2 sweep now enables the standard HWREna bits and executes the
architectural `RDHWR rt,$1` (`SYNCI_Step`) encoding. The initial mnemonic
attempt correctly exposed RI because the assembler emitted `rs=0`; the test
now uses the exact standard `rs=0` encoding used by the CP0 sweep. Both
`make isa-r2-gate` and `make qemu-system-isa-r2-differential-gate` pass with
`ri=0` and `TRACE_COMPARE_PASS`. Full privileged register access policy,
user/kernel HWREna semantics and complete ISA compliance remain open. The
same selected corpus also checks deterministic `RDHWR CPUNum=0` and
`RDHWR CCRes=2`; dynamic Count remains intentionally outside this differential.

### 2026-08-24 MIPS32 R2 SYNCI differential extension

The ISA R2 firmware sweep now executes real `SYNCI 0(base)` through the RTL
cache-maintenance path. `make isa-r2-gate qemu-system-isa-r2-differential-gate`
passes with `ri=0` and `TRACE_COMPARE_PASS`; the QEMU reference terminates the
translation block for the same R2 synchronization instruction. This adds
selected SYNCI evidence only and does not close full cache ordering, complete
privileged ISA, Linux cache ABI, or full ISA compliance.

### 2026-08-24 P1/QEMU aggregate refresh

Fresh aggregate verification passes `make p1-current-complete`,
`make qemu-system-current-contract-gate`, and
`make qemu-system-selected-differential-gate`. The first covers the current
RTL/simulation architecture bundle; the latter two cover vendor-neutral QEMU
peripherals and the selected RTL/QEMU retire corpus. These results do not
upgrade the scope to full ISA, complete privileged/MMU/Linux VM semantics,
IEEE-754/FPU ABI, MESI/directory coherency, physical DDR/QSPI timing, or
formal/CDC/RDC/lint/product signoff.

### 2026-08-24 precise FPE inexact slice

`make fpu-fpe-inexact-gate` passes on the real opt-in FPU CPU/SoC path. The
guest enables only FCSR Inexact, executes `CVT.W.S 1.5`, reaches ExcCode 15,
checks Cause/Flags and verifies no destination FPR commit. The custom QEMU
reference was patched to retain accrued FCSR Flags on an enabled FPE and its
standalone capture reports `FCSR=0x00001084`. The matching
`qemu-system-fpu-fpe-inexact-differential-gate` now passes with
`TRACE_COMPARE_PASS records=43` through the mailbox retirement boundary. The
gate uses a dedicated run directory because an earlier directory contained a
cached VCS elaboration without `SOC_FPU_ENABLE=1`; the verified run explicitly
recompiles the FPU-enabled design. Full
IEEE-754 inexact/range policy, complete double FPE, OS context/ABI and Linux
boot remain open.

### 2026-08-24 QEMU capture OOM closure

The QEMU system retire gate now bounds event/state counts and capture file
sizes before conversion, so a guest failure loop cannot cause the converter to
materialize an unbounded Python list and exhaust host memory. The double
underflow guest encoding and QEMU reference FCSR boundary were corrected;
`make qemu-system-fpu-fpe-double-underflow-differential-gate` now passes the
RTL/QEMU retire comparison. This closes the selected capture robustness and
FPU boundary evidence only. Full IEEE-754, complete ISA/FPU compliance,
Linux/OS boot and formal signoff remain explicitly outside the current
contract.

### 2026-08-24 QEMU DMA fault classification

The opt-in `mips32-soc-ref` DMA model now supports `dma-fault-mode=1` for a
forced AXI read failure and `dma-fault-mode=2` for a forced AXI write failure.
`make qemu-system-dma-fault-gate` passes both firmware cases, including the
distinct `ERR_AXI_READ=2`/`ERR_AXI_WRITE=3` codes, channel IRQ, PIC source
propagation and DONE/ERR W1C re-arm. Default `dma-fault-mode=0` behavior is
unchanged. This closes the vendor-neutral reference-model fault taxonomy
slice only; physical DDR/AXI response timing, reset-in-flight, arbitrary
multi-channel interleavings and production DMA signoff remain open.

### 2026-08-24 QEMU GPIO input and timer IRQ model

The `mips32-soc-ref` machine now accepts the opt-in `gpio-input` property and
implements RTL-compatible mixed GPIO readback: driven values are returned for
output bits and the configured external value for input bits. Its timer model
now honors the interrupt-enable bit, asserts the RTL VIC source 2, preserves
the sticky INT status across disable, and clears it through the APB W1C
register. `make qemu-system-gpio-input-gate` passes GPIO input, timer IRQ,
timer W1C and the existing peripheral checks. Board-level GPIO synchronization,
physical clock accuracy and RTL pin timing remain outside this reference-model
gate.

### 2026-08-24 QEMU DDR fault/status model

The opt-in `mips32-soc-ref` DDR model now accepts `ddr-fault-mode=1` for a
vendor-neutral AXI error code (`0x00040004`) and `ddr-fault-mode=2` for a
geometry error code (`0x00040005`). `make qemu-system-ddr-fault-gate` passes
both cases, checks the sticky status/error classification, clears it with the
APB W1C control, and verifies cached and uncached DDR window access afterward.
Default mode `0` remains unchanged. This closes the QEMU reference status
slice only; real PHY/JEDEC failure timing, ECC injection, refresh behavior and
board-level DDR signoff remain open.

### 2026-08-24 RDHWR implemented-subset closure

`make cp0-rdhwr-gate` passes on the real CPU/SoC path. The gate verifies
standard MIPS32 R2 `RDHWR` targets `$0` (CPUNum), `$1` (SYNCI_Step), `$2`
(Count), `$3` (CCRes), and `$29` (UserLocal), including kernel setup,
user-mode HWREna-disabled CpU exceptions, re-enabled user reads, and a real
UserLocal/TLS read-write sequence. This closes the bounded RDHWR implementation
slice and updates the ISA/front-end matrices; full privileged ISA compliance,
dynamic Count semantics, OS TLS ABI and Linux boot remain open.

### 2026-08-24 cache FSM SVA integration

`cache_state_props.sv` is now part of the `SVA_ENABLE` SoC compile and binds
to the default blocking `dcache`. The checker asserts a known FSM state and a
bounded refill completion, with a documented 4096-cycle upper bound that
includes the current SoC's legal AXI/APB backpressure. `make sva-gate` passes
and the gate now rejects the checker error text as well as explicit `SVA_FAIL`
markers. This is simulation assertion evidence only; formal proof, CDC/RDC,
lint and product coverage signoff remain open.

The same unified SVA compile now enables the existing 32-source VIC priority
checker (`VIC_PRIORITY_CHECKER_ENABLE`) and includes its bind/source files.
`make sva-gate` remains green with no priority, vector or pending-source
mismatch; this is simulation evidence, not a formal interrupt-priority proof.

### 2026-08-26 QEMU DMA v2 SG data contract

Added the bounded `qemu_system_dma_sg` firmware corpus and
`make qemu-system-dma-sg-data-gate`. It programs two linked 16-byte DMA v2
descriptors, runs the real RTL DMA path and the `mips32-soc-ref` model, compares
all eight destination words in the guest, and only then writes the success
mailbox. The no-coverage UVM RTL run and clean QEMU guest shutdown both pass;
the evidence is under `build/isa_ref/qemu_system_dma_sg_data/`.

An attempt to use the generic per-retire plugin with the full DMA firmware was
bounded out because the long status-poll corpus does not produce a bounded
capture. The new SG data gate therefore closes data movement only and does not
claim full DMA retire differential, physical AXI fault/reset timing, or Linux
DMA ABI.

The same corpus now passes the strict per-retire harness with
`FW_TEST=qemu_system_dma_sg ... tb/isa_ref/run_qemu_system_differential_gate.sh`.
The standard entry is `make qemu-system-dma-sg-differential-gate` and the
fresh comparison reports `QEMU system RTL retire differential: PASS`. The
firmware uses a fixed 512-iteration architectural delay before its single
STATUS read, so the comparison observes the same completed state without
weakening the comparator; this remains a bounded DMA differential rather than
full physical fault/reset or Linux DMA signoff.

### 2026-08-26 QEMU LL/SC system differential closure

Added `make qemu-system-llsc-differential-gate` to the architecture closure
aggregate. The real RTL CPU and `mips32-soc-ref` now compare 293 aligned retire
records covering virtual `LLAddr` visibility, successful `SC`, unreserved
`SC`, ordinary-store invalidation, exception-cleared reservation and mailbox
completion. QEMU's custom-machine LL helper exposes the RTL virtual-address
diagnostic contract while retaining its virtual reservation comparison; the
RTL observation bind has a dedicated SC address capture because `wb_ex_out`
holds the architectural success result. The QEMU converter reconstructs the
attempted SC address/data for fast-failed atomic callbacks. The gate passes with
`TRACE_COMPARE_PASS records=293` and is bounded evidence only: complete MIPS
memory ordering, arbitrary atomic interleavings, MESI/directory ordering and
Linux atomic ABI remain open.

### 2026-08-26 QEMU peripheral retire differential timing closure

`make qemu-system-peripheral-differential-gate` passes in the independent
fresh run `build/isa_ref/qemu_system_peripheral_differential_repro4/` with a
strict `TRACE_COMPARE_PASS`. The peripheral guest now uses an architectural
settling delay after the four-word legacy DMA start, and the custom-machine
reference model completes small transfers at that same observation boundary;
larger transfers retain bounded BUSY polling. The real RTL/QEMU corpus covers
GPIO, timer, DMA status, PIC marker, QSPI status/XIP and DDR status before the
mailbox. This remains a selected peripheral differential slice and does not
close full DMA fault/reset timing, physical device timing, Linux drivers or
full RTL system-mode Linux differential.

### 2026-08-29 QEMU integer overflow differential and trace resource bound

`qemu_system_exception` now executes signed `ADD`, `SUB`, and `ADDI` overflow
cases and the non-trapping `ADDIU` wrap boundary. The real RTL and
`mips32-soc-ref` retire streams both observe three `ExcCode=12` records with
no faulting GPR commit, one syscall exception, and an `ADDIU` result of
`0x80000000`. The corpus-specific gate assertion rejects a reduced
syscall-only image. The RTL UVM and standalone observation bindings suppress
transient GPR writeback on exception records, and the generic differential
runner rejects oversized RTL traces before a stuck guest can exhaust host
storage. Fresh isolated overflow, ISA R2, BREAK, trap, branch-delay exception,
and RTL frontend (`8/8`) gates pass. This closes selected signed integer
overflow differential evidence and verification resource safety only; full
MIPS32/privileged ISA, Linux/OS semantics and product signoff remain open.
