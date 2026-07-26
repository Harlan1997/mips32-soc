# DDR3 控制器 微架构规格 (v0)

> 状态：v0 草案。作为 Phase D **替换 `rtl/perips/axi_ddr_model.v`**（当前仅仿真 behavioral model）的实施基线。目标：可综合的 DDR3 SDRAM 控制器，AXI4 前端 + 命令调度 + 刷新 + 校准接口。PHY 采购。

---

## 0. 目标与范围

- **DDR3 支持**：JEDEC JESD79-3F 兼容，最高 DDR3-1600 (800 MT/s per pin)
- **数据宽度**：16 或 32 bit (DIMM 或分立颗粒)
- **地址宽度**：Bank[2:0] × Row[15:0] × Col[9:0]，容量 512 MB - 4 GB
- **AXI4 前端**：32-bit 数据（fabric 侧），CDC 到 DDR clock 域
- **命令调度**：Bank-aware，ACT/RD/WR/PRE/REF/自刷新
- **Refresh**：自动周期性刷新 (tREFI = 7.8 µs @ 85°C)
- **PHY 接口**：**采购**（Cadence/Synopsys/Northwest Logic）；本控制器输出 DFI 3.1 兼容命令/写数据/读数据
- **ECC (可选)**：SECDED per 64-bit（Phase D+ 决策）
- **Bring-up / 校准**：PHY 负责物理层校准；控制器提供 mode register 写入序列

**不做**（本 phase）：
- LPDDR3/4 (需 PHY 支持)
- 多 rank / 多 CS
- Bank 分组 (BG) — DDR4 特性
- 加密 (仅 M8Nx 等一些 IP 支持)

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
`ddr_clk`：DDR3 时钟（如 400 MHz，DDR-800，PHY 支持更高时同步升）

---

## 2. AXI4 前端

- AXI4 slave，32-bit data，256-bit line 支持 (INCR burst up to 16 beats × 32b = 64 B)
- 支持乱序 (per fabric spec: multi-outstanding, ID 追踪)
- 每 read/write 事务转成 DDR 命令队列 (可能拆多个 burst)
- 写数据先入 write buffer；读数据从 read buffer 出到 R 通道

**内部队列**：
- Read Command Queue: 16-32 深
- Write Command Queue: 16-32 深
- Read Data Buffer: 64 words (缓冲 in-flight read)
- Write Data Buffer: 64 words (合并写入 + 与 command 对齐)

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
- `dfi_cs_n[1:0]`, `dfi_ras_n`, `dfi_cas_n`, `dfi_we_n`, `dfi_address[15:0]`, `dfi_bank[2:0]`, `dfi_cke`
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

## 5. 寄存器映射 (APB, base = `SOC_APB_DDRCTRL_BASE`)

| Offset | 名称 | RW | 说明 |
|:-:|---|:-:|---|
| 0x000 | CTRL          | RW | enable / self_refresh / init_start |
| 0x004 | STATUS        | RO | init_done / busy / calib_done |
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

    // AXI4 slave (from fabric)
    // ... 完整 AXI4 slave 端口 ...

    // APB slave (control)
    // ... APB 端口 ...

    // DFI 3.1 interface to PHY (vendor-specific pins)
    output wire [BANK_BITS-1:0]  dfi_bank,
    output wire [ROW_BITS-1:0]   dfi_address,
    output wire                  dfi_cs_n,
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

    // Interrupt to VIC
    output wire        irq
);
```

---

## 8. 时序 (关键)

DDR3-1600 CL=11 CWL=8：

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

**SoC 级**：
- U-Boot memtest：全 DDR 空间 walk (0x00/FF, 55/AA, 随机)
- STREAM benchmark：带宽 ≥ 60% 峰值 (DDR3-1600 单 32-bit → 6.4 GB/s 峰值，实际 3.8+)
- Linux 引导：kernel + rootfs 加载到 DDR

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

---

## 版本记录

- v0 (2026-07-26)：初版规格，DDR3-1600 32-bit + FR-FCFS 调度 + 自动 refresh + DFI 3.1 接口 + APB 配置 + ECC 预留。等待 Phase D 启动评审。
