# QSPI Flash 控制器 微架构规格 (v0)

> 状态：v0 草案。作为 Phase D **替换 `rtl/perips/axi_spi_flash.v`** 的实施基线。当前 SPI 控制器只支持 XIP 单线 read (0x03)，写返回 SLVERR，无擦除/编程/QUAD/DMA。新控制器目标是**通用 QSPI Flash controller (SPI/DSPI/QSPI)** + XIP + 擦除/编程 + DMA。

---

## 0. 目标

- **模式**：Single (Standard SPI), Dual (DSPI), Quad (QSPI); read/write phases 独立配置
- **XIP (Execute-In-Place)**：AXI4 slave 端口透明响应 read → 后端 SPI 完成
- **命令 API**：APB 寄存器接口下发任意 SPI 命令 (erase/program/status/config)
- **命令查找表 (LUT)**：8+ 条预定义 LUT，软件按 opcode 索引
- **DMA 支持**：写入/读出大块数据经 AXI DMA 或本控制器内 DMA engine
- **时钟**：QSPI clk 由 APB clk 分频 (M+1)，独立 divisor 寄存器
- **CS 控制**：手动 (软件写) 或自动 (随事务)
- **对接**：常见 SPI Flash (Micron/Winbond/Macronix)：读 0x03/0x0B/0x3B/0x6B/0xEB；写 0x02/0x32；擦 0x20/0xD8/0xC7；状态 0x05/0x35；配置 0x01/0x11/0x31

---

## 1. 顶层端口

- **AXI4 slave**（XIP 读）：只接受 R；W 返回 SLVERR。
- **APB slave**（命令/状态/DMA 触发）：寄存器接口。
- **AXI4 master**（可选，命令 DMA）：把 flash 数据流向内存 / 反之。**Phase D 决策**：不做内部 DMA，靠外部通用 DMA 触发 (APB → DMA → AXI)；仅保留 slave 侧。
- **SPI 引脚**：`sclk, ss_n[3:0], sd[3:0]`。sd 双向 (inout)，方向切换由 controller 依阶段控制。

---

## 2. LUT (Lookup Table) 命令描述

每 LUT 条目 = 一个 SPI 事务序列，按阶段编码：

| 字段 | 位宽 | 值 |
|---|---|---|
| CMD  (opcode 8 bit) | 8 | 例 0x03, 0x0B, 0xEB |
| ADDR 阶段 | 2 | 0=无, 1=24-bit, 2=32-bit, 3=保留 |
| MODE 阶段 | 2 | 0=无, 1=8-bit continuous read mode |
| DUMMY cycles | 5 | 0-31 dummy |
| DATA 方向 | 1 | 0=read, 1=write |
| CMD lane   | 2 | 0=x1, 1=x2, 2=x4 |
| ADDR lane  | 2 | 同上 |
| DATA lane  | 2 | 同上 |

**8 slots**（`LUT[0..7]`），APB 可写。软件初始化时配置 flash-specific 命令。

XIP 内部固定用 `LUT[0]` (默认 QSPI Fast Read Quad I/O 0xEB) 或软件配置的 `XIP_LUT_INDEX` 寄存器。

---

## 3. 寄存器映射 (APB, base = `SOC_APB_QSPI_BASE`)

| Offset | 名称 | RW | 说明 |
|:-:|---|:-:|---|
| 0x000 | CTRL       | RW | 使能、模式、CS 自动/手动、reset |
| 0x004 | STATUS     | RO | busy/tx_full/rx_empty/error |
| 0x008 | CLK_DIV    | RW | SPI clk = APB clk / (2 × (CLK_DIV+1)) |
| 0x00C | CS_CTRL    | RW | CS 手动 assert; ss select |
| 0x010 | IRQ_EN     | RW | 完成中断使能 |
| 0x014 | IRQ_STATUS | W1C | 完成 pending |
| 0x020–0x040 | LUT[0..7] | RW | 8 × 32-bit LUT 描述 |
| 0x044 | XIP_LUT_INDEX | RW | XIP 用哪条 LUT (默认 0) |
| 0x100 | CMD_TRIGGER | W | 写触发命令：{lut_idx[2:0], addr[24-bit or 32-bit low], data_len[16-bit]} |
| 0x104 | CMD_ADDR    | RW | 32-bit 命令地址（若 addr 阶段有效） |
| 0x108 | CMD_DATA_LEN | RW | 命令 data 阶段字节数 |
| 0x110 | TX_DATA    | W | 写数据 FIFO 入口 (32-bit chunks) |
| 0x114 | RX_DATA    | R | 读数据 FIFO 出口 |
| 0x118 | FIFO_STATUS | RO | TX/RX FIFO 计数、水位 |

**FIFO 深度**：TX/RX 各 32 words (128 B)。

---

## 4. XIP 路径

```
AXI R (addr, len):
  1. Fabric 送 addr 到 QSPI slave (base 0x1000_0000 - 0x1FFF_FFFF)
  2. Controller 映射 addr[27:0] → flash offset
  3. 用 XIP_LUT_INDEX 指定的 LUT 发起 SPI:
     CS assert → CMD → ADDR (28-bit → 24 或 32-bit) → MODE (若有) → DUMMY → DATA read
  4. 一次读满 line (32 B) 或至 RLAST
  5. 每 32 bit 组装成 R beat 返回
  6. CS deassert (若命令要求) 或保留 continuous mode
  7. RRESP = OKAY (读成功) 或 SLVERR (SPI error, 罕见)
```

**Continuous mode**：LUT 的 MODE 阶段发 0xA5 保持 flash 在 "no cmd" 状态，下次 XIP 只发 addr 省 cmd。可提速 10-20%。

**性能**：QSPI 100 MHz × 4 lanes ≈ 400 Mbit/s = 50 MB/s；AXI 40 MHz × 32-bit = 160 MB/s → SPI 是瓶颈，AXI 侧自然 backpressure。

---

## 5. 命令 API 路径 (擦除/编程/状态)

```
APB:
  1. 软件设 CMD_ADDR, CMD_DATA_LEN, TX_DATA (若 write)
  2. 写 CMD_TRIGGER {lut_idx, addr_high, data_len}
  3. Controller FSM 启动:
     CS assert → CMD → (ADDR) → (MODE) → (DUMMY) → DATA (TX or RX)
     TX: 从 TX_DATA FIFO pop 到 SPI
     RX: 从 SPI 收到 RX_DATA FIFO push
  4. 完成 → CS deassert → STATUS.busy=0, IRQ_STATUS.done=1, IRQ (若使能)
  5. 软件读 RX_DATA (若 read) 或轮询 STATUS
```

典型命令示例：
- **Read Status Register (0x05)**：LUT{cmd=0x05, addr=none, data=read 1B}；返回 flash busy 位
- **Write Enable (0x06)**：LUT{cmd=0x06}；无 addr/data
- **Sector Erase 4KB (0x20)**：LUT{cmd=0x20, addr=24-bit}；软件 WEL → cmd → 轮询状态直至完成
- **Page Program 256B (0x02)**：LUT{cmd=0x02, addr=24-bit, data=write}；FIFO 装 256B

---

## 6. 与 DMA 协作

- 外部 DMA (`apb_axi_dma`) 触发 QSPI 命令 → RX_DATA FIFO → DMA 读 APB → AXI 写内存
- 或反：DMA 从 AXI 内存读 → 写 TX_DATA FIFO → QSPI 命令 write
- FIFO 半空 / 半满 flag 触发 DMA req (可选，Phase D+)

---

## 7. Reset / Flush

- Reset：CTRL.enable=0, FIFOs 空, FSM=IDLE, CS deasserted, IRQ_STATUS 清
- CTRL.reset (软) 位：软件写 1 → 清 FIFO + FSM
- XIP AXI 请求 in-flight 时 reset：AXI 侧返回 SLVERR + RLAST；不能挂

---

## 8. 参数化

```verilog
`define SOC_QSPI_TX_FIFO_DEPTH  32
`define SOC_QSPI_RX_FIFO_DEPTH  32
`define SOC_QSPI_LUT_SLOTS      8
`define SOC_QSPI_CS_COUNT       4      // 支持 4 片 flash
`define SOC_QSPI_ADDR_WIDTH_MAX 32     // 支持大容量 flash (>128MB)
```

---

## 9. 接口

```verilog
module qspi_ctrl #(
    parameter TX_FIFO_DEPTH = 32,
    parameter RX_FIFO_DEPTH = 32,
    parameter LUT_SLOTS     = 8,
    parameter CS_COUNT      = 4
)(
    input  wire        clk,           // apb clk = spi ref clk
    input  wire        rst_n,

    // AXI4 slave (XIP read only)
    // ...

    // APB slave (command interface)
    // ...

    // SPI pins
    output wire                 sclk,
    output wire [CS_COUNT-1:0]  ss_n,
    inout  wire [3:0]           sd,

    // Interrupt
    output wire        irq
);
```

**inout 端口**：唯一破例（顶层 pad），需在 pad ring 处理方向控制。

---

## 10. 验证要求

**块级** (`tb/uvm_tb/qspi/`)：

- 每 LUT 阶段组合：CMD/ADDR/MODE/DUMMY/DATA × 1/2/4 lane × read/write
- XIP 读：单 beat / 8-beat burst；命中 continuous mode
- 命令 API：Read Status / Write Enable / Erase / Page Program
- FIFO 满/空/水位 flag
- CS 手动/自动
- CS 多片 (ss_n[3:0]) 切换
- Divisor 边界 (最小 clk, 最大 clk)
- Reset 中断进行中的事务 → 恢复
- SPI 错误注入 (模型强制返回 dummy) → SLVERR

**SoC 级**：
- 从 QSPI Flash boot：CPU 复位 → BFC0_0000 → XIP 加载 U-Boot → jump to DDR
- U-Boot 擦写 flash test
- Linux MTD driver 挂载 QSPI 分区

**SVA**：
- SS 拉高时 SCLK 无活动
- LUT 各阶段 lane 切换 (x1 → x2 → x4) 无 glitch
- FIFO 计数不出边界

**Formal**：
- FSM 无死锁
- XIP AXI backpressure 正确处理

---

## 11. Flash Model 依赖

- 现有 `rtl/perips/axi_flash_image_model.v` 是仿真专用，可保留供 tb 用（连到本控制器 SPI 端口 → 需要新增 SPI 层 model）。
- 建议引入开源 SPI Flash behavioral model (Micron N25Q / Winbond W25Q 系列 Verilog model)。
- 真实 tape-out：直接接商用 flash 芯片。

---

## 版本记录

- v0 (2026-07-26)：初版规格，8-LUT + XIP + 命令 API + 4 CS + 32-word TX/RX FIFO + 100MHz QSPI x4。等待 Phase D 启动评审。
