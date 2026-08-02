# QSPI Flash 控制器 微架构规格 (v0.1)

> 状态：v0.1，RTL 前端行为契约。它仍是 Phase D **替换 `rtl/perips/axi_spi_flash.v`** 的实施基线；当前可验证 slice 不是商用 QSPI controller。默认兼容路径仍为单线 XIP，`soc_top` 可选启用 vendor-neutral 四线 pad mux，但真实 PHY、器件时序、板级模型和 production boot 均未签收。
> 当前 RTL 前端交付已增加 `qspi_axi_xip` standalone bridge：它通过 APB sequencer 驱动 `qspi_cmd_behavioral`，完成 x1 `0x03` 读和 AXI read-only 返回。该 bridge 已达到 `BLOCK_VERIFIED (vendor-neutral)`，但尚未接入 `soc_memory_subsystem`，不能替代产品 QSPI controller 或商用 flash/PHY。

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
| 0x004 | STATUS     | RO | bit0 busy, bit1 tx_full, bit2 rx_empty, bit3 done/IRQ pending, bit4 error, bit5 timeout, bit6 aborted |
| 0x008 | CLK_DIV    | RW | SPI clk = APB clk / (2 × (CLK_DIV+1)) |
| 0x00C | CS_CTRL    | RW | CS 手动 assert; ss select |
| 0x010 | IRQ_EN     | RW | 完成中断使能 |
| 0x014 | IRQ_STATUS | RW/W1C | bit0 done, bit1 timeout, bit2 aborted；对应位 W1C |
| 0x018 | TIMEOUT    | RW | command reference-clock budget; 0 disables command timeout |
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

### 4.1 当前 standalone AXI/XIP bridge contract

`rtl/perips/qspi_axi_xip.v` 是当前 RTL 前端阶段的独立验证实现，边界如下：

- 只接受一个 AXI read burst；每个 beat 串行执行一次 APB command transaction，burst 不跨 beat 合并。
- 固定使用 LUT0=`0x03 + 24-bit address + 4-byte x1 read`，每个 beat 地址递增 4 字节。
- 轮询 command status，读取四个 RX FIFO byte 后组成 `RDATA`；command error 返回 `SLVERR`。
- AXI write address/data handshake 完成后返回 `BVALID/SLVERR`，不对 flash 发起写命令。
- 该实现没有 continuous-read、quad XIP、DMA 或多片 CS 支持；command timeout 已由 reference-clock budget 提供，计划集成 SoC 时仍必须继续放在 `axi_read_timeout_guard` 后面。
- standalone bridge 的 command timeout/error 会转换为 AXI `SLVERR`；AXI bridge 仍保持单 outstanding，并由 `COMMAND_TIMEOUT_CYCLES` 参数提供 bounded command budget。
- APB command path 与既有单线 AXI/XIP path 已有共享 pin 的 owner/priority/abort/timeout/reset-in-flight contract；standalone bridge 仍不切换默认 `soc_memory_subsystem` 的 `axi_spi_flash` 路径。
- 注意：上句指 standalone `qspi_axi_xip` bridge 本身仍未替换默认路径；SoC 当前已对既有 `axi_spi_flash` 单线 XIP 与 APB command path 接入 `qspi_shared_pin_arbiter`，并由 `qspi_soc_pad_mux` 提供可选 `qspi_io[3:0]` 四线三态边界。该接入是有限 `SOC_INTEGRATED`/vendor-neutral slice，不是 quad PHY 或商用 QSPI 完成。

### 4.2 共享 pin 仲裁 contract（SoC 单线接入）

`rtl/perips/qspi_shared_pin_arbiter.v` 固定当前接入前的总线语义：

- command 与 memory source 都必须在整个事务期间保持 `*_req`；`*_active` 只能由获 grant 的 source 驱动。
- owner 一旦 active 不可抢占；owner 释放后才允许切换，切换到空闲时 `SCLK=0`、`CS_N=1`、`MOSI=0`。
- 总线空闲且两个 source 同时 claim 时，command 获得确定性优先级；不会在一个事务中间切换 source。
- 两个 source 同时 claim 或未获 grant 的 source assert `*_active` 时，`conflict=1`；冲突不会覆写当前 owner 的 pins。
- `qspi_shared_pin_arbiter` 的独立 contract gate 已通过，并已由 `mips_soc_impl` 接入既有单线 `axi_spi_flash` 与 APB command path。SoC 接入同时把 command trigger/AXI `AR` acceptance、downstream `ARVALID` 与 `*_req` 正确绑定；SoC smoke 已证明 crossbar response accounting 不因 grant 等待而失步。command timeout 在 command reference clock 上计数，超时回到 IDLE、置 `STATUS.timeout/error`、产生 done IRQ 并释放 pins；CTRL[2] 或清 enable 终止当前事务并置 `STATUS.aborted/error`；IRQ_STATUS bit0/1/2 分别清 done/timeout/aborted。任一外部/WDT reset 优先清 FSM/FIFO/事件并将 pins 回到 `SCLK=0/CS_N=1/MOSI=0`，不保留半个 command。

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

- Reset：CTRL.enable=0, FIFOs 空, FSM=IDLE, CS deasserted, IRQ_STATUS 清；reset/WDT 期间正在进行的 command 被丢弃，不能产生迟到 IRQ。
- CTRL.reset (软) 位：软件写 1 → 清 FIFO + FSM + timeout/abort/error/done 状态。
- CTRL[2] abort 或清 CTRL.enable：同步终止当前 command，保留 FIFO 内容，置 aborted/error/done，软件可通过 IRQ_STATUS W1C 清事件。
- `TIMEOUT=0` 仅用于受控仿真/调试来禁用 command budget；产品配置必须使用非零值。
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
- Reset/WDT 中断进行中的事务 → pins 安全 idle、状态清零、下一事务可恢复
- Command timeout、CTRL abort、清 enable → bounded completion、IRQ/error 事件和 W1C
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

- 现有 `rtl/perips/axi_flash_image_model.v` 是 AXI image-window 仿真专用模型，可保留供 UVM/legacy tb 使用。
- `rtl/perips/spi_flash_behavioral.v` 提供当前 command slice 的 vendor-neutral SPI 端点：`0x03` 读、`0x05` 状态、`0x06` WREN、`0x02` page-program 基本 NOR `1->0` 语义和 `0x20` 4-KB sector erase；它只用于 RTL 仿真，不代表 Micron/Winbond 宏模型、时序、电压、擦写寿命或 PHY。
- 真实产品验证仍需选定 flash 厂商/型号并引入其受许可的行为模型或板级模型。
- 真实 tape-out：直接接商用 flash 芯片。

---

## 验证状态

- 2026-08-02：`rtl/perips/qspi_cmd_behavioral.v` + `tb/unit/flash/tb_qspi_cmd_behavioral.sv` 通过 `make qspi-cmd-behavioral-gate`。证据覆盖 APB LUT/command API、24/32-bit address serialization、RX/TX FIFO、status read、x4 data lane、CS/SCLK、busy error、IRQ W1C 和 soft reset。
- 该实现是 `BLOCK_VERIFIED (vendor-neutral)` 行为契约，尚未成为 `soc_top` 的 AXI XIP controller，也未连接商用 flash model、quad pad/PHY 或 erase/program boot path；不能标记为商用 ASIC QSPI 完成。
- 2026-08-02：`qspi_apb_integration` 接入 `soc_peripheral_subsystem`；保留 `0x4000_5000` status map，在 `0x4000_5020..0x4000_519f` 暴露 command window，并由 SoC mux 在 command CS active 时接管单线 SPI pins。`qspi-status-integration`、SoC smoke 和 RTL frontend `3/3` 通过。
- 该集成证据已包含有限 `SOC_INTEGRATED` APB/x1 command slice 和 SoC 四线 APB command read/write gate；`qspi_soc_pad_mux` 已接入 `mips_soc_impl`，并由 `soc_top` 的 `ENABLE_QSPI_QUAD=1` 暴露 `qspi_io[3:0]`。四线 mux 的 lane mapping/高阻和 AXI→APB command read/write 已通过，但四线 AXI XIP、PHY、电气时序、商用 flash model、erase/program production path 和 boot handoff 仍未完成。
- 2026-08-02：`spi_flash_behavioral` 通过 `make qspi-flash-behavioral-gate` 接入 `qspi_apb_integration`，验证 `0x03` 读 `DE AD BE EF`、`0x06` WREN、`0x02` 编程空白页、再次读回 `CA FE BA BE`，以及重新 WREN 后 `0x20` sector erase 读回全 `FF`。状态仍为 `BLOCK_VERIFIED (vendor-neutral)`，不升级为真实 flash/PHY 或 AXI XIP 产品完成。
- 2026-08-02：`qspi_pad_wrapper` 通过 `make qspi-pad-wrapper-gate` 验证 x4 read `A5`、x4 write `A1B2C3D4` 的三态方向/nibble 映射和 CS 结束后的高阻。该 wrapper 仅是 vendor-neutral RTL pad boundary，未接 SoC top、pad ring、IO timing 或真实 PHY。
- 2026-08-02：`qspi_axi_xip` 通过 `make qspi-axi-xip-gate` 验证 AXI 单拍读、两拍 burst、ID/RLAST/RRESP、内部 APB command sequencing、vendor-neutral flash 读回和 AXI write `SLVERR`；SPI pins 在每次事务后回到 idle。该 bridge 仍为 `BLOCK_VERIFIED (vendor-neutral)` standalone 实现，未替换 SoC 默认 `axi_spi_flash`。
- 2026-08-02：`qspi_shared_pin_arbiter` 通过 `make qspi-shared-pin-arbiter-gate` 验证 memory owner 保持、command 非抢占、release 后切换、idle 时 command priority、冲突指示和 idle pin 安全值；随后由 `mips_soc_impl` 接入既有单线 AXI XIP/APB command，`make soc-smoke`、QSPI integration gates 和 RTL frontend `3/3` 通过。状态升级为有限 `SOC_INTEGRATED` shared-pin slice；abort/reset-in-flight、quad PHY、商用 flash/boot 仍未完成。
- 2026-08-02：SoC integration fix：grant 同时门控 fabric `ARREADY` 与 guard/model downstream `ARVALID`，并在 guard/model 已接受事务后保持 memory request；修复此前 SoC smoke 中 crossbar response FIFO 与 guard 状态失步的 5 ms timeout。该行为已由 `/tmp/soc_smoke_qspi_arbiter_final/sim.log` 的 `REGRESSION_TEST_SUCCESS` 复验。
- 2026-08-03：`qspi_cmd_behavioral` 增加 `TIMEOUT`、CTRL[2] abort、清 enable abort、timeout/abort W1C 和 reset-in-flight 安全语义；`tb_qspi_cmd_behavioral` 覆盖 timeout、abort、外部 reset，`qspi-status-integration` 覆盖 AXI/APB 集成 timeout 及 WDT 中断 command。`qspi-cmd-behavioral-gate`、`qspi-status-integration-gate`、相关 QSPI gates、`rtl-frontend-compile` 和 `soc-smoke` 均通过；证据仍为 RTL 前端功能，不代表真实 flash 静默检测、quad PHY 或 production boot。
- 2026-08-03：`qspi_soc_pad_mux` 接入 `mips_soc_impl`，`mips_soc/soc_top` 新增可选 `ENABLE_QSPI_QUAD` 与 `qspi_io[3:0]`，默认配置仍保持 legacy x1。`make qspi-soc-pad-mux-gate` 覆盖 command 四 lane 输出、memory lane-0 兼容、command 优先级、读阶段高阻和 idle 安全值；`rtl-frontend-compile`、QSPI 既有 gates 与 `soc-smoke` 通过。状态仅提升 SoC pad boundary 的 RTL 证据，不提升为真实 PHY、商用 flash 或 production boot。
- 2026-08-03：`qspi-status-integration` 打开 `ENABLE_QSPI_SHARED_ARB=1`/`ENABLE_QSPI_QUAD=1`，经真实 AXI→APB command window 和共享 owner 完成 x4 read `0xC3`、x4 write `A1B2C3D4`；`make qspi-soc-quad-gate` 通过。该证据只关闭 SoC 四线 APB command wiring，不覆盖四线 AXI XIP、真实 PHY 或 production boot。

## 版本记录

- v0 (2026-07-26)：初版规格，8-LUT + XIP + 命令 API + 4 CS + 32-word TX/RX FIFO + 100MHz QSPI x4。等待 Phase D 启动评审。
- v0.1 (2026-08-03)：冻结 RTL 前端 timeout/abort/reset-in-flight 行为、W1C 位和可选 SoC 四线 pad boundary；商用 PHY、flash/板级模型、四线命令 SoC gate、擦写量产路径仍开放。
