# 时钟 / 复位 / CDC 微架构规格 (v0)

> 状态：v0 草案。作为 Phase E 时钟、复位和 CDC RTL 契约。当前 SoC 单时钟 (`clk`) + 单同步复位 (`rst_n`)；Phase E 关注多时钟域、AASD 复位架构和 CDC 单元库。

---

## 0. 目标

- **多时钟域**：CPU / L2 / AXI fabric / APB / DDR / GMAC / USB / QSPI / 32K RTC 各自独立
- **复位架构**：AASD (async assert / sync deassert) 统一约定；每域独立复位同步器；POR / 软复位 / WDT 复位分层聚合
- **CDC 单元库**：async FIFO、握手同步器、脉冲同步器、灰码计数器、mux-based 同步器
- **CDC / RDC 静态验证 0 违规**

---

## 1. 时钟域清单

| 域 | 频率 (典型) | 用途 | 源 |
|---|---|---|---|
| `cpu_clk`    | implementation-defined | CPU pipeline / L1 caches | clock input |
| `l2_clk`     | implementation-defined | L2 cache | clock input |
| `axi_clk`    | implementation-defined | AXI fabric + AXI 侧 DMA | clock input |
| `apb_clk`    | implementation-defined | APB peripherals (UART/GPIO/SPI/I2C/TMR/VIC) | clock input |
| `ddr_clk`    | implementation-defined | DDR controller | clock input |
| `qspi_clk`   | implementation-defined | QSPI Flash | clock input |
| `jtag_tck`   | implementation-defined | JTAG TAP | external input |

**Phase E 决策**：先落核心域的复位同步和 CDC 契约，外设时钟域按实际集成需要加入。

---

## 2. 复位架构

### 3.1 复位源

| 源 | 触发 | 影响范围 |
|---|---|---|
| POR (Power-On Reset)   | 上电 / 手动 | 全芯片 (所有域) |
| Soft Reset             | 软件写寄存器 | CPU + subsystem (可选) |
| WDT Reset              | Watchdog 到期 | 全芯片 (可配置) |
| JTAG Reset             | TRST_n 或 TAP TEST_LOGIC_RESET | Debug + CPU (可选) |
| PLL Lost Lock          | PLL unlock | 对应域 |
| DDR Init Fail          | DDR ctrl 报错 | DDR + memory subsystem (可选) |

聚合到每域的 `<domain>_rst_pre_n`，然后经该域的**复位同步器**输出 `<domain>_rst_n` 供该域寄存器使用。

### 3.2 AASD 复位同步器

`rtl/clock/reset_sync.v`：

```verilog
module reset_sync #(
    parameter STAGES = 3        // 至少 2, 建议 3
)(
    input  wire clk,
    input  wire rst_pre_n,      // 异步输入 (聚合后)
    output wire rst_n           // 同步输出
);
    reg [STAGES-1:0] sync_r;
    always @(posedge clk or negedge rst_pre_n) begin
        if (!rst_pre_n) sync_r <= '0;
        else            sync_r <= {sync_r[STAGES-2:0], 1'b1};
    end
    assign rst_n = sync_r[STAGES-1];
endmodule
```

- 异步 assert (`negedge rst_pre_n` 即刻拉低 rst_n)
- 同步 deassert (STAGES 拍延迟)
- 每域独立实例化

### 3.3 复位聚合器

```verilog
module reset_agg (
    input  wire por_n,
    input  wire soft_rst_n,
    input  wire wdt_rst_n,
    input  wire jtag_rst_n,
    input  wire pll_lock,       // 用于 gated release
    output wire agg_rst_n
);
    assign agg_rst_n = por_n & soft_rst_n & wdt_rst_n & jtag_rst_n & pll_lock;
endmodule
```

聚合后送 `reset_sync` 各域。

### 3.4 复位顺序

```
1. POR: 全域异步拉低
2. cpu_clk 域 reset_sync 释放 → CPU 出复位 (PC = 0xBFC0_0000)
3. DDR init → dfi_init_complete → ddr_clk 域释放
4. AXI/APB 域跟随 cpu_clk 释放
5. Peripheral 域按依赖顺序释放
```

由外部 PMU/CMU 顺序控制器 (`rtl/clock/reset_seq.v`) 生成。

---

## 4. CDC 单元库

`rtl/clock/`:

### 4.1 sync_2ff.v — 单 bit 电平同步器

```verilog
module sync_2ff #(parameter STAGES = 2) (
    input  wire dst_clk,
    input  wire dst_rst_n,
    input  wire src_data,
    output wire dst_data
);
    (* async_reg = "true" *) reg [STAGES-1:0] sync_r;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) sync_r <= '0;
        else            sync_r <= {sync_r[STAGES-2:0], src_data};
    end
    assign dst_data = sync_r[STAGES-1];
endmodule
```

**约束**：`src_data` 必须为**寄存器输出**（组合信号跨域禁）。

### 4.2 pulse_sync.v — 脉冲同步器

- src 域一拍 pulse → dst 域一拍 pulse
- 通过 toggle → 2FF → edge detector 实现
- 要求 src pulse 间隔 ≥ 3 dst clk

### 4.3 handshake_sync.v — 握手同步器

- Full 4-phase handshake (req/ack)
- src 拉 req → 2FF 到 dst → dst 拉 ack → 2FF 回 src → src 撤 req → dst 撤 ack
- 用于多 bit 数据打包传输 (data 与 req 一同稳定)

### 4.4 gray_counter.v + async_fifo.v — 异步 FIFO

- Gray-coded read/write pointer 跨域比较
- 深度 2^N (推荐 8 / 16 / 32)
- 数据宽度参数化
- 用于连续数据流 (音视频、DMA 数据流)

**约束**：Gray counter 保证跨域时仅 1 bit 变化 → 采样无 metastability 传播。

### 4.5 mux_sync.v — Mux 同步器

- 数据+valid 一起：valid 用 sync_2ff，data 由 valid 门控采样
- 适合低频、非连续多 bit 传输
- 简化替代 handshake

### 4.6 使用规则

- 所有跨域 signal 必须通过上述之一
- CDC 静态验证工具 (VC-CDC / SpyGlass CDC / Meridian) 必须识别 100%
- 未识别的路径必须在 `docs/cdc_waivers.md` 登记原因

---

## 5. 参数化 (`rtl/include/soc_config.vh`)

```verilog
// Clock domain enable (仿真 / bring-up 用)
`define SOC_CLK_DOMAINS       8
`define SOC_RESET_SYNC_STAGES 3

// CDC FIFO defaults
`define SOC_CDC_FIFO_DEPTH    16
`define SOC_CDC_SYNC_STAGES   2

```

---

## 8. 顶层接线

`rtl/soc_top.v` 新增：

```verilog
module soc_top (
    // Off-chip clock/reset
    input  wire ref_clk_25m,    // 参考晶振
    input  wire rtc_clk_32k,    // RTC 晶振
    input  wire por_n,          // 上电复位
    input  wire jtag_trst_n,

    // ... 其他 I/O ...
);
    // 复位聚合与同步
    reset_agg u_rst_agg_cpu (...);
    reset_sync u_rst_sync_cpu (.clk(cpu_clk), .rst_pre_n(cpu_rst_pre_n), .rst_n(cpu_rst_n));
    // ... 每域一份 ...

    // CDC bridge 例化在 subsystem 边界

    // 各 subsystem 接自己的 clk/rst_n

endmodule
```

---

## 9. 验证要求

**块级** (`tb/uvm_tb/clock_reset/`)：

- **reset_sync**：async assert 立即传播；deassert 3 拍延迟
- **reset_agg**：任一源拉低即聚合拉低
- **sync_2ff / pulse_sync / handshake_sync / async_fifo**：单元级功能 + 边界（连续 pulse / 空满 / 握手循环）

**SoC 级**：
- 复位序列：POR → 各域按依赖释放 → CPU 从 0xBFC0_0000 取指
- WDT reset：使能 WDT → 不喂狗 → 触发全芯片 reset → 重新引导
- 跨域数据流：AXI (axi_clk) ↔ DDR (ddr_clk) 大数据传输无 loss
- APB 慢域访问快域寄存器无 hazard

**静态验证**：
- **CDC** (VC-CDC / SpyGlass CDC / Meridian)：0 违规；100% CDC 路径识别为已同步
- **RDC** (Reset Domain Crossing)：0 违规；跨复位域路径全部同步或 waive 有据
- **Lint**：通过

**SVA**：
- reset_sync 输出 rst_n 拉高后 STAGES 拍无 X
- async_fifo 空/满不同时；wr/rd pointer gray-encoded
- handshake req 拉高必收 ack (bounded)

**Formal**：
- reset_sync 无死锁
- async_fifo 无数据 loss / duplicate（bounded liveness）
- pulse_sync src 每 pulse 对应 dst 一 pulse (bounded)

---

## 10. 演进

- **AON (always-on) 深度睡眠唤醒**：RTC/GPIO/UART 唤醒源

---

## 版本记录

- v0 (2026-07-26)：初版规格，时钟域 + AASD 复位 + CDC 单元库 (5 类)。等待 Phase E 启动评审。
