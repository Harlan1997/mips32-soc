# UART 16550 兼容控制器 微架构规格 (v0)

> 状态：v0 草案。作为 Phase D **替换 `rtl/perips/apb_uart.v`** 的实施基线。当前 UART TX 用 `$write` 打印字符（仿真专用），无 RX、无 FIFO、无波特率生成器。新 UART 兼容业界标准 16550，可对接 Linux 8250 驱动。

---

## 0. 目标

- **PC16550D 兼容**：寄存器映射、字段语义与 8250/16550 一致，Linux 8250 driver 直接可用。
- **TX / RX FIFO**：各 64 entries (16550A 是 16，本设计放大以提升吞吐)，可参数化。
- **波特率**：16-bit 除数寄存器 (DLL/DLM)，最高 3 Mbaud @ 48 MHz APB clock (16× 过采样)。
- **帧格式**：5/6/7/8 数据位、1/1.5/2 停止位、奇偶校验 (奇/偶/mark/space/无)。
- **流控**：RTS/CTS 硬件流控 (16550 MSR/MCR)。
- **中断源** (合并成 1 → VIC)：
  - RX 数据可读 (阈值可编程)
  - TX FIFO 空
  - RX 线路状态错误 (parity/framing/break/overrun)
  - Modem status 变化
- **Break detect / send**
- **Loopback 模式**（自测）
- **APB 接口**

---

## 1. 寄存器映射 (APB, 8-bit reg on 32-bit APB word)

标准 16550 布局。字节访问用 APB `pstrb`（若无 pstrb，则 word 只用低 8 bit）。

| Offset | 名称 (DLAB=0) | 名称 (DLAB=1) | RW | 说明 |
|:-:|---|---|:-:|---|
| 0x00 | RBR (读) / THR (写) | DLL | RW | 接收缓冲 / 发送保持；DLAB=1 时低 8 除数 |
| 0x04 | IER | DLM | RW | 中断使能 / 高 8 除数 |
| 0x08 | IIR (读) / FCR (写) | -   | RW | 中断标识 / FIFO 控制 |
| 0x0C | LCR | -   | RW | Line control (DLAB, 帧格式) |
| 0x10 | MCR | -   | RW | Modem control (DTR, RTS, LOOP) |
| 0x14 | LSR | -   | RO | Line status |
| 0x18 | MSR | -   | RO | Modem status |
| 0x1C | SCR | -   | RW | Scratch (软件用) |

### 1.1 LCR (Line Control)

| bit | 名 | 说明 |
|:-:|---|---|
| 7   | DLAB | Divisor Latch Access Bit (1 → 0x00/0x04 访问 DLL/DLM) |
| 6   | BC   | Break Control (强制 TX 拉低送 break) |
| 5   | SP   | Stick Parity |
| 4   | EPS  | Even Parity Select |
| 3   | PEN  | Parity Enable |
| 2   | STB  | Stop Bits (0=1, 1=1.5/2 by WLS) |
| 1:0 | WLS  | Word Length Select (00=5, 01=6, 10=7, 11=8 bits) |

### 1.2 FCR (FIFO Control, W-only)

| bit | 名 | 说明 |
|:-:|---|---|
| 7:6 | RCVR_TRIG | RX 触发阈值 (00=1, 01=16, 10=32, 11=56 chars) — 16550 阈值放大到 64-FIFO 比例 |
| 3   | DMA_MODE | DMA 模式 (Phase D+ 可加，先 tie 0) |
| 2   | XFR_RESET | 写 1 → 清 TX FIFO |
| 1   | RCVR_RESET | 写 1 → 清 RX FIFO |
| 0   | FIFO_EN | 使能 FIFO (0 → 单字节兼容模式) |

### 1.3 IER (Interrupt Enable)

| bit | 名 |
|:-:|---|
| 3 | EDSSI (Modem Status) |
| 2 | ELSI (RX Line Status) |
| 1 | ETBEI (TX Holding Empty) |
| 0 | ERBFI (RX Data Available) |

### 1.4 IIR (Interrupt Identification, RO)

| bit | 名 |
|:-:|---|
| 7:6 | FIFO enabled (11) |
| 3   | Fifos timeout indicator |
| 2:1 | Interrupt ID code (00=Modem, 01=TX empty, 10=RX data, 11=RX line status) |
| 0   | Interrupt pending (0=pending, 1=none) |

### 1.5 LSR (Line Status)

| bit | 名 | 说明 |
|:-:|---|---|
| 7 | RFE  | Receiver FIFO Error (任一 char 有 error) |
| 6 | TEMT | TX empty (FIFO+shift 均空) |
| 5 | THRE | TX Holding Register Empty |
| 4 | BI   | Break Interrupt |
| 3 | FE   | Framing Error |
| 2 | PE   | Parity Error |
| 1 | OE   | Overrun Error |
| 0 | DR   | Data Ready (RX FIFO 非空) |

### 1.6 MCR (Modem Control)

| bit | 名 |
|:-:|---|
| 4 | LOOP (loopback) |
| 3 | OUT2 (通用输出，通常关联 IRQ 门) |
| 2 | OUT1 (通用) |
| 1 | RTS |
| 0 | DTR |

### 1.7 MSR (Modem Status)

| bit | 名 | 说明 |
|:-:|---|---|
| 7:4 | DCD, RI, DSR, CTS (电平) | |
| 3:0 | 4 delta bits (变化标志) | 读 MSR 清 delta bits |

---

## 2. 波特率生成

- 输入时钟 `apb_clk`（例 48 MHz）
- 16× 过采样：`baud = apb_clk / (16 × divisor)`
- `divisor = {DLM, DLL}`，16-bit → 1 ≤ divisor ≤ 65535
- 例：48 MHz / (16 × 26) = 115_384 ≈ 115200 baud
- divisor=0 视为 divisor=1（防除零）

---

## 3. TX 路径

```
APB 写 THR:
  1. 若 FIFO_EN=0: 写 THR 缓冲，1 char at a time
  2. 若 FIFO_EN=1: 入 TX FIFO 尾
  3. 若 TX shift 空 → 从 THR/FIFO 拿一 char → 装 shift
  4. shift 按波特率发：start bit (0) + data + parity + stop
  5. 完成 → shift 空 → 若 FIFO 非空 → 装下一 char
  6. FIFO 空 + shift 空 → LSR.TEMT=1, LSR.THRE=1, 触发 IRQ (若 IER.ETBEI=1)

CTS 流控：
  MCR.RTS 与外部 CTS 联动：若 auto-CTS 使能且 CTS=0 → 暂停 TX
  (Phase D 默认不支持 auto-CTS，软件轮询 MSR.CTS)
```

---

## 4. RX 路径

```
UART_RX 引脚采样：
  1. 检测 start bit (下降沿)
  2. 半 bit 后校正 → 按 baud tick 采样中点
  3. 每 char: shift → 检 parity/framing/break
  4. 若无 error → 入 RX FIFO
  5. FIFO 到阈值 → IRQ (若 IER.ERBFI=1)
  6. FIFO 满 → 新 char → LSR.OE=1 (overrun)
  7. Break 检测: RX 保持 0 超过 1 char time → LSR.BI=1

RTS 流控:
  auto-RTS: FIFO 到高水位 → RTS 拉高（信号发送方停发）
  低水位后拉低 → 允许接收
  (Phase D 默认软件控制 MCR.RTS)
```

---

## 5. Loopback (MCR.LOOP=1)

- TX serial → 反接 RX serial（内部）
- Modem 引脚：DTR→DSR, RTS→CTS, OUT1→RI, OUT2→DCD (内部环)
- 用于自测。

---

## 6. 参数化

```verilog
`define SOC_UART_TX_FIFO_DEPTH  64
`define SOC_UART_RX_FIFO_DEPTH  64
`define SOC_UART_OVERSAMPLE     16
`define SOC_UART_APB_CLK_HZ     48_000_000    // 参考频率
`define SOC_UART_INSTANCES      2             // uart0, uart1
```

---

## 7. 接口

```verilog
module apb_uart_16550 #(
    parameter TX_FIFO_DEPTH = 64,
    parameter RX_FIFO_DEPTH = 64
)(
    input  wire        clk,          // apb clock
    input  wire        rst_n,

    // APB slave
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [4:0]  paddr,        // 5 bit for 8 regs × 4B
    input  wire [3:0]  pstrb,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Serial pins
    output wire        uart_tx,
    input  wire        uart_rx,

    // Modem
    output wire        uart_rts_n,
    input  wire        uart_cts_n,
    output wire        uart_dtr_n,
    input  wire        uart_dsr_n,
    input  wire        uart_dcd_n,
    input  wire        uart_ri_n,

    // Combined interrupt to VIC
    output wire        irq
);
```

---

## 8. 验证要求

**块级** (`tb/uvm_tb/uart/`)：

- 波特率精度：divisor=26 (115200 @ 48MHz) TX/RX 时序对齐 ≤ 3% 误差
- 帧格式全组合：5-8 位 × 1/1.5/2 stop × 奇/偶/mark/space/无
- FIFO 满/空/阈值中断
- Overrun / Framing / Parity / Break 错误注入 → LSR 位
- Loopback 模式全帧格式回环
- Auto-baud (可选 Phase F)
- Modem 4 delta bit 变化检测
- APB 字节访问（pstrb）
- FCR reset 位清 FIFO
- Divisor latch access (DLAB) 语义
- IIR 中断优先级：RX line status > RX data > TX empty > Modem
- 16550 一致性向量测试（用第三方 UART tester model）

**SoC 级 firmware**：
- Bare-metal echo test: RX → TX
- U-Boot 打印 (Phase F Linux boot 前提)
- Linux 8250 driver 挂载 → `printk` 输出

**SVA**：
- LSR.THRE=1 iff TX FIFO 空 && THR 空
- LSR.TEMT=1 iff LSR.THRE=1 && shift 空
- IRQ pulse 仅在 IER 对应位使能时可拉高

**Formal**：
- FIFO 计数不出边界
- Baud counter 无死锁

---

## 版本记录

- v0 (2026-07-26)：初版规格，PC16550D 兼容 + 64-entry FIFO + 硬件 RTS/CTS + Loopback。等待 Phase D 启动评审。
