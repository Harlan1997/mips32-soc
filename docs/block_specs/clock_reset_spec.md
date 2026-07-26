# 时钟 / 复位 / CDC / 电源意图 微架构规格 (v0)

> 状态：v0 草案。作为 Phase E **新增 `rtl/clock/`** 与 `upf/soc.upf` 的实施基线。当前 SoC 单时钟 (`clk`) + 单同步复位 (`rst_n`)；Phase E 升级为多时钟域 + AASD 复位架构 + CDC 单元库 + PLL 接口 + ICG + UPF 声明层。

---

## 0. 目标

- **多时钟域**：CPU / L2 / AXI fabric / APB / DDR / GMAC / USB / QSPI / 32K RTC 各自独立
- **复位架构**：AASD (async assert / sync deassert) 统一约定；每域独立复位同步器；POR / 软复位 / WDT 复位分层聚合
- **CDC 单元库**：async FIFO、握手同步器、脉冲同步器、灰码计数器、mux-based 同步器
- **PLL 接口**：外部 PLL macro (采购)；控制器 wrapper 提供 lock 检测 / 分频 / 旁路 / 参考切换
- **ICG (集成时钟门控)**：latch-based ICG cell wrapper，供 clock gating 使用
- **UPF 电源意图**：声明层 (Phase E 只做 RTL 兼容性 + 声明；物理实现在后端)
- **CDC / RDC 静态验证 0 违规**

---

## 1. 时钟域清单

| 域 | 频率 (典型) | 用途 | 源 |
|---|---|---|---|
| `cpu_clk`    | 500 MHz – 1 GHz | CPU pipeline / L1 caches | PLL0 |
| `l2_clk`     | 500 MHz | L2 cache | PLL0 / 2 |
| `axi_clk`    | 250 MHz | AXI fabric + AXI 侧 DMA | PLL0 / 4 |
| `apb_clk`    | 50 MHz  | APB peripherals (UART/GPIO/SPI/I2C/TMR/VIC) | axi_clk / 5 |
| `ddr_clk`    | 400 MHz (DDR3-1600 内部) | DDR3 controller + PHY | PLL1 |
| `ddr_phy_clk` | 800 MHz | DDR3 PHY (2× ddr_clk) | PLL1 |
| `gmac_tx_clk` | 125 MHz (Gigabit) | GMAC TX | PLL2 或外部 |
| `gmac_rx_clk` | 125 MHz | GMAC RX | 外部 (PHY 提供) |
| `usb_utmi_clk` | 60 MHz | USB 2.0 UTMI | 外部 PHY 提供 |
| `qspi_clk`   | 100 MHz | QSPI Flash | axi_clk / 2 |
| `rtc_clk`    | 32.768 kHz | RTC / 深度睡眠计时 | 外部晶振 |
| `jtag_tck`   | ≤ 20 MHz | JTAG TAP | 外部 |

**Phase E 决策**：先落 8 个核心域（cpu / l2 / axi / apb / ddr / ddr_phy / qspi / jtag），其他（gmac/usb/rtc）随 Phase D 外设并行加入。

---

## 2. PLL 接口

`rtl/clock/pll_wrapper.v`：包裹外部 PLL macro，提供统一接口。

```verilog
module pll_wrapper #(
    parameter OUT_DIVIDERS = 4      // 输出分频数
)(
    input  wire        ref_clk,     // 参考晶振 (e.g. 25 MHz)
    input  wire        rst_n,       // 异步 reset (PLL 断电)
    input  wire        bypass,      // 1 → 直通 ref_clk
    input  wire [7:0]  fb_div,      // 反馈分频
    input  wire [3:0]  out0_div,    // 输出 0 分频
    input  wire [3:0]  out1_div,
    input  wire [3:0]  out2_div,
    input  wire [3:0]  out3_div,

    output wire [OUT_DIVIDERS-1:0] out_clk,
    output wire        lock         // PLL 锁定
);
    // Phase E: 内部 tie-off 或 behavioral model；实际实现由后端插入 PLL macro
    // 提供 lock=1 (bypass 或 macro lock)
endmodule
```

**上电序列**：Reset 释放 → ref_clk 稳定 → 配置分频 → 等 lock (通常 100 µs) → 释放该 PLL 下游复位。

---

## 3. 复位架构

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
2. Ref clk 稳定 → PLL enable
3. PLL lock (~100µs) → 释放 cpu_clk 域 pll_lock
4. cpu_clk 域 reset_sync 释放 → CPU 出复位 (PC = 0xBFC0_0000)
5. DDR PHY init → dfi_init_complete → ddr_clk 域释放
6. AXI/APB 域跟随 cpu_clk 释放
7. Peripheral 域按依赖顺序释放
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

## 5. ICG (Integrated Clock Gating)

`rtl/clock/clkgate_icg.v`：

```verilog
module clkgate_icg (
    input  wire clk_in,
    input  wire enable,
    input  wire test_en,        // scan / test bypass
    output wire clk_out
);
    reg latch;
    always @(clk_in or enable or test_en)
        if (~clk_in) latch <= enable | test_en;
    assign clk_out = clk_in & latch;
endmodule
```

- Latch-based (低毛刺)
- test_en 供 DFT scan 模式旁路
- 综合工具会替换为工艺库 ICG cell (如 CLKGATETST_X1)

**使用规则**：
- 每层 clock gating 只用 ICG，不用 AND 门（会 glitch）
- Enable 必须由**寄存器输出**，或经 pipeline stage 打拍
- 层次门控：粗粒度 (block level) + 细粒度 (register bank) 结合

---

## 6. UPF (Unified Power Format) 声明层

`upf/soc.upf`（Phase E 只落声明，物理实现在后端）：

```tcl
# 电源域声明
create_power_domain PD_AON  -include_scope
create_power_domain PD_CPU  -elements {u_soc_top/u_core_subsystem}
create_power_domain PD_L2   -elements {u_soc_top/u_core_subsystem/u_l2}
create_power_domain PD_DDR  -elements {u_soc_top/u_memory_subsystem/u_ddr_ctrl}
create_power_domain PD_PERI -elements {u_soc_top/u_peripheral_subsystem}

# 电源开关
create_power_switch PSW_CPU -domain PD_CPU \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_CPU} \
    -control_port {pcm cpu_pwr_ctrl}

# 隔离
set_isolation ISO_CPU -domain PD_CPU -isolation_supply_set primary \
    -clamp_value 0 -applies_to outputs
set_isolation_control ISO_CPU -domain PD_CPU \
    -isolation_signal cpu_iso_en -isolation_sense high

# Retention
set_retention RET_CPU -domain PD_CPU -retention_supply primary \
    -save_signal {cpu_ret_save posedge} -restore_signal {cpu_ret_restore posedge}
```

**Phase E 范围**：只落 UPF 声明 + RTL 侧兼容性检查（跨域信号命名规范 + 不引入 UPF-违规的直连）。物理实现（隔离单元插入、retention flop 映射）在后端。

**RTL 编码约束**（配合 UPF）：
- 跨电源域信号命名：`<dst_pd>_from_<src_pd>_<name>`
- 电源域边界处必须有可插入 iso cell 的 register 输出
- 关键 always-on 逻辑 (VIC / RTC / PMU / WDT) 放 PD_AON

---

## 7. 参数化 (`rtl/include/soc_config.vh`)

```verilog
// Clock domain enable (仿真 / bring-up 用)
`define SOC_CLK_DOMAINS       8
`define SOC_RESET_SYNC_STAGES 3

// PLL config default
`define SOC_PLL0_REF_HZ       25_000_000
`define SOC_PLL0_OUT0_HZ      1_000_000_000   // cpu_clk 目标
`define SOC_PLL0_OUT1_HZ      500_000_000     // l2_clk
`define SOC_PLL0_OUT2_HZ      250_000_000     // axi_clk
`define SOC_PLL0_OUT3_HZ      50_000_000      // apb_clk

`define SOC_PLL1_REF_HZ       25_000_000
`define SOC_PLL1_OUT0_HZ      400_000_000     // ddr_clk

// CDC FIFO defaults
`define SOC_CDC_FIFO_DEPTH    16
`define SOC_CDC_SYNC_STAGES   2

// Power domain enable
`define SOC_PD_CPU_SWITCHABLE  1     // 支持关 CPU 保 L2 (deep sleep)
`define SOC_PD_L2_SWITCHABLE   0
`define SOC_PD_DDR_SWITCHABLE  1     // 支持关 DDR (self-refresh 除外)
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
    // PLL 层
    pll_wrapper u_pll0 (.ref_clk(ref_clk_25m), ...);
    pll_wrapper u_pll1 (.ref_clk(ref_clk_25m), ...);

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

- **PLL wrapper**：bypass / lock 时序、分频正确性
- **reset_sync**：async assert 立即传播；deassert 3 拍延迟
- **reset_agg**：任一源拉低即聚合拉低
- **sync_2ff / pulse_sync / handshake_sync / async_fifo**：单元级功能 + 边界（连续 pulse / 空满 / 握手循环）
- **ICG**：enable=0 时 clk_out 无翻转；test_en 强制旁路

**SoC 级**：
- 复位序列：POR → PLL lock → 各域按依赖释放 → CPU 从 0xBFC0_0000 取指
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

- **DFS/DVFS (动态调压调频)**：PLL 分频动态切换 + 电压变化联动
- **Multi-PLL sync**：多 PLL 之间保序切换
- **Power sequencer (PMU FSM)**：多域顺序上下电，与外部 PMIC 通信
- **AON (always-on) 深度睡眠唤醒**：RTC/GPIO/UART 唤醒源

---

## 版本记录

- v0 (2026-07-26)：初版规格，8 时钟域 + AASD 复位 + CDC 单元库 (5 类) + ICG + UPF 声明层。等待 Phase E 启动评审。
