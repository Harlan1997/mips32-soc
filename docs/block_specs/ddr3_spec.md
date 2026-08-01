# DDR3 控制器/PHY 功能契约 (v1.0)

> 状态：**契约冻结候选，RTL 未实现**（2026-08-01）。这是替换
> `rtl/perips/axi_ddr_behavioral.v` 的接口和验收基线，不是 controller
> 已完成的声明。当前 S3 仍是 behavioral capacity placeholder；它不能作为
> DDR3 controller、PHY、商用初始化或 `PRODUCT_FUNCTION_READY` 证据。

---

## 0. 目标与范围

- **产品基线**：单 rank、单 chip-select、x32 DDR3，JEDEC JESD79-3F，最高
  DDR3-1600 (800 MT/s per pin)。x16 只允许作为参数化 block 测试配置，不能
  改变 SoC 的 x32 AXI 契约。
- **地址宽度**：Bank[2:0] × Row[14:0] × Col[9:0]；实际颗粒容量由 part
  timing file 决定，SoC 暴露的窗口固定为 `SOC_DDR_BASE..BASE+SIZE-1`。
- **AXI4 前端**：32-bit 数据、4-bit ID（fabric 侧），异步 FIFO 跨到 DDR
  clock 域；地址和 burst 语义见第 2 节。
- **命令调度**：Bank-aware，ACT/RD/WR/PRE/REF/自刷新
- **Refresh**：自动周期性刷新 (tREFI = 7.8 µs @ 85°C)
- **PHY 接口**：**采购**（Cadence/Synopsys/Northwest Logic）；本控制器输出 DFI 3.1 兼容命令/写数据/读数据
- **ECC (可选)**：SECDED per 64-bit（Phase D+ 决策）
- **Bring-up / 校准**：PHY 负责物理层校准；控制器提供 mode register 写入序列

**不做**（本契约）：
- LPDDR3/4 (需 PHY 支持)
- 多 rank / 多 CS
- Bank 分组 (BG) — DDR4 特性
- 加密 (仅 M8Nx 等一些 IP 支持)

### 0.1 当前阻塞和输入

输入登记见 [`docs/ddr_integration_inputs.md`](../ddr_integration_inputs.md)；
当前 `DDR_ENTRY_READY=0`，因此本节只冻结实施前置条件，不授权 controller RTL。

controller RTL 只有在以下输入全部冻结后才允许实现：

1. PHY vendor/IP、版本、许可证和 DFI 3.1 port list；
2. DDR3 part number、rank/width、板级频率/电气约束和 timing file；
3. 可分发的真实 DDR3 memory model（Micron 或商用模型）及其初始化参数；
4. `axi_clk`/`ddr_clk`/PHY clock 的时钟树、复位释放和 power-good ownership；
5. APB 软件 owner、错误码 ABI、WDT 超时预算和 boot handoff 依赖。

在这些输入缺失时，只能完成本文档和独立 protocol checker；不得新增一个
behavioral module 并把它命名为 controller。

---

## 1. 拓扑

```
[AXI Fabric] ─(AXI4 32-bit @ axi_clk)─→ [AXI/DDR CDC + Reorder Buffer]
                                              │
                                              ↓ (per-command DFI @ ddr_clk)
                                        [Command Scheduler]
                                              │
                                              ↓ DFI Cmd/Wr/Rd
                                        [DDR3 PHY (采购 IP)]
                                              │
                                              ↓ CK/CKE/CS/ADDR/BA/DQ/DQS/DM
                                        [DDR3 Chip / DIMM]
```

`axi_clk`：与 fabric 同域（如 200 MHz）
`ddr_clk`：controller/DFI 时钟（如 400 MHz）；在 DFI ratio=2 时，PHY CK
可为 800 MHz，对应 DDR3-1600 的 1600 MT/s 数据速率。

### 1.1 时钟/复位域契约

| 信号 | 域 | 要求 |
|---|---|---|
| `axi_clk` / `axi_rst_n` | AXI/APB/fabric | 与 SoC fabric 同步；`axi_rst_n=0` 时 AXI 不得产生有效握手 |
| `ddr_clk` / `ddr_rst_n` | controller scheduler/DFI | 由选定 PHY/PLL 提供；复位时 DFI 命令必须为 NOP、`cke=0`、`dfi_reset_n=0` |
| `ddr_phy_clk` / `ddr_phy_rst_n` | PHY vendor wrapper | 由 PHY 负责生成/锁定；controller 不假设其相位，必须由 DFI wrapper 明确 ratio |
| `dfi_init_complete` | PHY → controller | 先同步到 `ddr_clk`，再同步到 `axi_clk` 状态路径；不可直接跨域采样 |

AXI 与 DDR 域之间使用有界 async FIFO/握手队列。任一 reset 域单独复位时，
未完成事务必须被 flush 并返回 `SLVERR`；不得重放写数据或永久保持
`ARREADY/AWREADY=0` 而没有 APB/WDT 可观察的错误状态。

---

## 2. AXI4 前端契约

- AXI4 slave：`DATA_WIDTH=32`、`ID_WIDTH=4`、`AWSIZE/ARSIZE=3'b010`。
- 只接受 `INCR` burst，`AWLEN/ARLEN <= 8'h0f`（1--16 beats）；不接受
  `FIXED`、`WRAP`、未对齐地址或跨 4-KB 边界的 burst，违规事务返回
  `SOC_AXI_RESP_SLVERR`，不得修改 DRAM。
- AXI 地址是物理地址；只接受 `SOC_DDR_BASE <= addr <
  SOC_DDR_BASE+SOC_DDR_SIZE`。窗口外返回 `DECERR`，**不能像 behavioral
  placeholder 一样折返地址**。
- 保留 AW/AR 的 ID，B/R response 必须带回原 ID；不在不同 ID 之间交叉
  R beat，单个 burst 的 `RLAST` 必须严格对应最后一个 beat。
- AW 与 W 通道可独立到达；controller 必须按 `AWLEN+1` 消耗 W beat，检查
  `WLAST`，在最后一个 W beat 后只产生一个 B response。
- 初始队列深度冻结为 read command 16、write command 16、read data 64
  words、write data 64 words；满时通过 `READY` 施加背压。
- 在 `STATUS.init_done=0` 的正常初始化阶段允许保持 AXI ready 为 0，但
  Boot ROM 必须通过 APB 轮询并使用 WDT 超时；在 fatal `STATUS.error=1`
  或 `CTRL.enable=0` 时，controller 必须接受有限的地址/数据并以
  `SLVERR` 完成事务（读返回全 0、写丢弃），避免静默死锁。

**内部队列**：
- Read Command Queue: 16-32 深
- Write Command Queue: 16-32 深
- Read Data Buffer: 64 words (缓冲 in-flight read)
- Write Data Buffer: 64 words (合并写入 + 与 command 对齐)

AXI 协议错误、地址错误、初始化未完成和 PHY/refresh 错误分别记录到
`ERROR_STATUS`；错误 response 不得被改写为 `OKAY`。错误清除后只有在
重新执行完整 init/calibration 序列并观察到 `init_done=1` 时才允许恢复正常
AXI 服务。

---

## 3. 命令调度

### 3.1 Bank State Machine

per bank (8 banks)：`IDLE → ACTIVE (row 打开) → READ/WRITE (数据传输) → PRECHARGE (关行)`

调度器同时追踪 8 个 bank 状态，优化 row 命中率。

### 3.2 调度策略

- **FR-FCFS** (First-Ready First-Come-First-Serve): 优先能立即发命令的（row hit），其次按到达顺序
- **Read/Write 分组**：批量 R 或 W 减少 RD→WR / WR→RD 切换 (tWTR/tRTW 开销)
- **Bank interleaving**：并发用多 bank 隐藏 tRCD/tRP
- **QoS-aware** (可选)：AXI QoS 高的事务优先 dispatch

### 3.3 命令生成

Per cycle 输出 DFI 命令：
- `dfi_cs_n[0:0]`（单 rank）、`dfi_ras_n`、`dfi_cas_n`、`dfi_we_n`、
  `dfi_address[14:0]`、`dfi_bank[2:0]`、`dfi_cke`
- 遵守 timing：tRCD (ACT→RD 12ns), tRP (PRE→ACT 12ns), tRAS (ACT→PRE 35ns), tRC, tFAW, tRRD, tWTR, tCL/tCWL 等
- 用 per-bank timer 追踪空闲时间；不 ready 的 bank 阻塞对应命令

### 3.4 Refresh

- Auto-refresh: 每 tREFI (~7.8µs @85°C) 发 REF 命令
- 若所有 bank 都在 IDLE → 直接 REF；否则等一个短时机窗口 (最多推迟 8 × tREFI)
- Self-refresh: 低功耗模式，PHY 支持

---

## 4. Mode Register / 初始化

复位后启动序列（约 500 µs 后 CKE 拉高，MRS 写入）：

- MR0: burst length (8), burst type (sequential), CAS latency, WR recovery
- MR1: DLL enable, output impedance, ODT
- MR2: dynamic ODT, self-refresh temperature
- MR3: MPR (multi-purpose register)

由控制器 FSM 顺序发送；软件通过 APB 寄存器 override 部分参数。

---

## 5. APB 控制器契约

APB slave base 固定为 `SOC_APB_DDRCTRL_BASE = 32'h4000_6000`（offset
`SOC_APB_DDRCTRL_OFFSET = 16'h6000`），窗口大小 4 KB。所有寄存器访问在
`axi_clk` 域完成，`PREADY` 必须在一个有限周期内返回；非法 offset 返回
`PSLVERR=1`。下表中的 W1C/W1S 语义是软件 ABI，不能由 vendor PHY wrapper
自行改变。

| Offset | 名称 | RW | 说明 |
|:-:|---|:-:|---|
| 0x000 | CTRL          | RW/W1S | bit0 enable；bit1 init_start (W1S)；bit2 self_refresh_req；bit3 force_refresh |
| 0x004 | STATUS        | RO | bit0 init_done；bit1 calib_done；bit2 busy；bit3 refresh_pending；bit4 self_refresh；bit5 error；bit6 axi_rejecting；bit7 dfi_init_complete；bit8 phy_ready |
| 0x008 | TIMING_0      | RW | tRCD/tRP/tRAS |
| 0x00C | TIMING_1      | RW | tRC/tFAW/tRRD |
| 0x010 | TIMING_2      | RW | tCL/tCWL/tWR/tWTR/tRTP |
| 0x014 | REFRESH_CTRL  | RW | tREFI / temperature mode |
| 0x018 | MR0_INIT      | RW | Mode Register 0 值 |
| 0x01C | MR1_INIT      | RW | Mode Register 1 |
| 0x020 | MR2_INIT      | RW | Mode Register 2 |
| 0x024 | MR3_INIT      | RW | Mode Register 3 |
| 0x028 | ADDR_MAP      | RW | Row/Col/Bank bit 映射 (软件配置) |
| 0x02C | ODT_CTRL      | RW | On-die termination 配置 |
| 0x030 | ERROR_STATUS  | RO | sticky error code；读不清除 |
| 0x034 | ERROR_CLEAR   | WO/W1C | bit0 清除 error；只有 controller idle 才接受 |
| 0x038 | VERSION       | RO | `0x4444_0301`（DDR3 controller contract v1） |
| 0x040 | PHY_CTRL      | RW | 传递给 PHY 的 vendor-specific 控制 |
| 0x044 | PHY_STATUS    | RO | PHY 校准/训练状态 |
| 0x080 | IRQ_EN        | RW | 完成 / 错误中断使能 |
| 0x084 | IRQ_STATUS    | W1C | 中断 pending |
| 0x100 | ECC_CTRL      | RW | ECC 使能 (若实现) |
| 0x104 | ECC_STATUS    | RO | 单/双 bit error 计数 |
| 0x108 | ECC_ADDR      | RO | 最近错误地址 |
| 0x200 | PERF_R_CNT    | RO | Read 事务计数 |
| 0x204 | PERF_W_CNT    | RO | Write 事务计数 |
| 0x208 | PERF_REF_CNT  | RO | Refresh 计数 |

`IRQ_STATUS` 位定义：bit0 init_done、bit1 calibration_done、bit2 refresh_due、
bit3 fatal_error、bit4 self_refresh_enter/exit。写 1 清除对应 pending 位。
`ERROR_STATUS[15:0]` 的首版错误码固定为：`0x0001` PHY init timeout、`0x0002`
calibration failure、`0x0003` refresh deadline、`0x0004` AXI protocol/address、
`0x0005` unsupported geometry/timing、`0x0006` reset/CDC flush。高 16 位保留
为 vendor detail，不得让软件依赖。

---

## 6. 参数化

```verilog
`define SOC_DDR_DATA_WIDTH    32
`define SOC_DDR_ROW_BITS      15
`define SOC_DDR_COL_BITS      10
`define SOC_DDR_BANK_BITS     3
`define SOC_DDR_BURST_LEN     8    // BL8 for DDR3
`define SOC_DDR_CL            11   // CAS Latency @ DDR3-1600
`define SOC_DDR_CWL           8
`define SOC_DDR_CMD_QUEUE     16
`define SOC_DDR_ECC_ENABLE    0
`define SOC_DDR_DFI_WIDTH     64   // DFI data width (2× DDR bus × 2 for double edge)
`define SOC_DDR_DFI_FREQ_RATIO 2
`define SOC_DDRCTRL_VERSION   32'h4444_0301
```

---

## 7. 接口

```verilog
module ddr3_ctrl #(
    parameter DATA_WIDTH = 32,
    parameter ROW_BITS   = 15,
    parameter COL_BITS   = 10,
    parameter BANK_BITS  = 3,
    parameter CMD_QUEUE  = 16
)(
    input  wire        axi_clk,     // fabric domain
    input  wire        axi_rst_n,
    input  wire        ddr_clk,     // DDR3 domain
    input  wire        ddr_rst_n,

    // AXI4 slave (from fabric), ID=4, DATA=32; all Ax/W/R/B channels include
    // the fields declared by the project AXI contract.
    // ... 完整 AXI4 slave 端口 ...

    // APB slave (control)
    // ... APB 端口 ...

    // DFI 3.1 command phase, driven in ddr_clk domain. CS is one rank only.
    output wire [BANK_BITS-1:0]  dfi_bank,
    output wire [ROW_BITS-1:0]   dfi_address,
    output wire [0:0]            dfi_cs_n,
    output wire                  dfi_ras_n,
    output wire                  dfi_cas_n,
    output wire                  dfi_we_n,
    output wire                  dfi_cke,
    output wire                  dfi_odt,
    output wire                  dfi_reset_n,

    output wire [(2*DATA_WIDTH)-1:0] dfi_wrdata,
    output wire [(2*DATA_WIDTH/8)-1:0] dfi_wrdata_mask,
    output wire                  dfi_wrdata_en,

    input  wire [(2*DATA_WIDTH)-1:0] dfi_rddata,
    input  wire                  dfi_rddata_valid,
    output wire                  dfi_rddata_en,

    input  wire                  dfi_init_complete,
    input  wire                  dfi_phyupd_ack,
    output wire                  dfi_phyupd_req,
    input  wire                  dfi_ctrlupd_ack,
    output wire                  dfi_ctrlupd_req,

    // Interrupt to VIC
    output wire        irq
);
```

`dfi_phyupd_*`/`dfi_ctrlupd_*` are mandatory handshake signals when required by
the selected DFI 3.1 PHY; a PHY wrapper may tie them inactive only when its
datasheet explicitly states that update handshakes are not used. The wrapper,
not the controller, owns vendor-specific pad names, delay lines, byte-lane
training and DQS timing.

---

## 8. 时序 (关键)

DDR3-1600 CL=11/CWL=8；下表按 800 MHz PHY CK 周期列出。controller 必须
按 `SOC_DDR_DFI_FREQ_RATIO` 将 PHY 周期换算为 `ddr_clk` 调度计数，不能把
下表的 PHY cycle 直接当成 400 MHz controller cycle：

| 参数 | 值 (@ 800MT/s) | 说明 |
|---|---|---|
| tRCD | 12 ns / 10 cyc | ACT → RD/WR |
| tRP  | 12 ns / 10 cyc | PRE → ACT |
| tRAS | 35 ns / 28 cyc | ACT → PRE |
| tRC  | 47 ns / 38 cyc | ACT → ACT (same bank) |
| tFAW | 45 ns / 36 cyc | 4 ACT window |
| tRRD | 6 ns / 5 cyc   | ACT → ACT (diff bank) |
| tWTR | 7.5 ns / 6 cyc | WR → RD (same bank) |
| tRTP | 7.5 ns / 6 cyc | RD → PRE |
| tREFI | 7.8 µs @85°C | Refresh 间隔 |
| tRFC | 260 ns / 208 cyc | Refresh cmd 长度 (4Gb) |

调度器内部 timer 追踪；软件通过 TIMING_* 寄存器可 override（用于不同颗粒）。

---

## 9. ECC (可选)

- SECDED (Single Error Correct, Double Error Detect) per 64-bit word
- 8 check bits per 64 data bits (Hamming code + parity)
- 读 → 检测 → 单 bit 纠正 (透明) → 双 bit 报中断 (ECC_STATUS.uncorrectable)
- 需要额外 DRAM 位宽 (32-bit + 8-bit) 或将 8-bit check 存在专用区域 (影响带宽)

**Phase D 决策**：**ECC_ENABLE=0** 默认关闭；预留 hooks。若产品定位需 ECC，Phase D+ 打开。

---

## 10. Reset / Init 序列

```
1. axi_rst_n / ddr_rst_n 复位 →  CTRL.init_start=0, STATUS.init_done=0
2. PHY 上电 + DLL 锁定 → dfi_init_complete
3. 软件写 CTRL.init_start=1
4. FSM: dfi_reset_n=0 → 100 µs
5. dfi_reset_n=1 → cke=0 → 500 µs
6. cke=1 → MRS 序列 (MR2/MR3/MR1/MR0) → ZQ calibration
7. STATUS.init_done=1, IRQ (若使能)
8. 正常运行
```

Any timeout in steps 2--6 sets `ERROR_STATUS`, clears `init_done`, asserts
`STATUS.error`, raises `IRQ_STATUS.fatal_error` when enabled, and enters the
bounded AXI reject path. A second `init_start` is ignored while `busy=1`.
`self_refresh_req` is acknowledged only after all AXI queues drain; wake-up
returns to `init_done=1` or a calibration error. APB status remains readable
throughout reset/error handling.

---

## 11. 验证要求

**块级** (`tb/uvm_tb/ddr3/`)：

- 使用 Micron DDR3 Verilog model (公开) 或商用 memory model
- Init 序列符合 JEDEC
- Timing 遵守：tRCD/tRP/tRAS 等边界 (SVA)
- Bank interleaving 命中率
- Refresh 周期正确性
- ECC 单/双 bit error 注入 (若启用)
- AXI backpressure 传播
- CDC (axi_clk ↔ ddr_clk) 无 loss
- Mode register 写序列
- Self-refresh 进入 / 退出
- `init_done=0`、fatal error 和 reset/CDC flush 的 bounded `SLVERR` response；
  地址越界必须是 `DECERR`，且任何错误 response 都不能静默变为 `OKAY`

**SoC 级**：
- U-Boot memtest：全 DDR 空间 walk (0x00/FF, 55/AA, 随机)
- STREAM benchmark：带宽 ≥ 60% 峰值 (DDR3-1600 单 32-bit → 6.4 GB/s 峰值，实际 3.8+)
- Linux 引导：kernel + rootfs 加载到 DDR

在真实 PHY/model 和 S3 替换完成前，上述 `ddr_init_test`、memory march、
refresh 和 Linux/U-Boot 项目均为 **未执行/阻塞**，不能用
`axi_ddr_behavioral` 或 `axi_ddr_model` 的通过结果代替。

**SVA**：
- 所有 DDR3 timing 参数遵守（bind checker，模型自带 SVA library）
- Refresh 间隔 ≤ tREFI × 9 (最多推迟 8 tREFI)
- Command scheduler 无 hang

**Formal**：
- Command 队列无死锁
- FR-FCFS 调度器公平性 (bounded age)

---

## 12. 演进

- **LPDDR3/4**：切 PHY IP，加低功耗模式
- **多 rank / 多 CS**：多颗粒 DIMM
- **加密**：memory encryption engine (Phase 后期，安全要求)
- **QoS 分区**：per-master bandwidth allocation

## 13. Contract entry/exit criteria

### Entry (before `ddr3_ctrl` RTL)

- PHY/IP vendor, release, license and complete DFI 3.1 port list are recorded;
- DRAM part/rank/width, board timing file, operating frequency and reset/power
  sequencing are reviewed by the board owner;
- a real memory model is runnable in the selected simulator;
- `SOC_APB_DDRCTRL_BASE`, register offsets, error codes and boot/WDT timeout
  budget are accepted by firmware and verification owners;
- the AXI reject, address-range, burst and CDC reset behavior in Sections 1--2
  has a checker/test plan.

### Exit (before replacing S3)

- synthesizable controller and selected PHY wrapper implement this exact AXI,
  APB, reset and DFI contract;
- block tests pass init success, init timeout, calibration failure, refresh
  deadline, self-refresh, malformed AXI, backpressure, reset flush and bounded
  error response against the real memory model;
- product SoC tests pass no-preload DDR init, march patterns, boot handoff,
  WDT failure classification and at least one long-running read/write stress;
- the report records PHY/IP version, DRAM part/timing-file hash, memory-model
  version and firmware image hash. Only then may the DDR row advance beyond
  `BLOCK_VERIFIED`.

---

## 版本记录

- v1.0 (2026-08-01)：冻结 AXI/APB/clock-reset/DFI/error contract、S3 地址边界、
  PHY/DRAM external inputs 和 entry/exit criteria；明确 behavioral model 不能
  作为商用 DDR 证据。RTL 仍未实现，等待 PHY/IP 选型。
- v0 (2026-07-26)：初版 DDR3-1600 32-bit + FR-FCFS 调度 + 自动 refresh + DFI
  3.1 接口 + APB 配置 + ECC 预留。
