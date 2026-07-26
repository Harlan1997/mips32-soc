# 向量化中断控制器 (VIC) 微架构规格 (v0)

> 状态：v0 草案。作为 Phase D **替换 `rtl/perips/apb_pic.v`** 的实施基线。当前 PIC 是纯 OR-reduce（32 源 → 1 `cpu_int`），软件必须遍历 STATUS 找源；新 VIC 引入**硬件优先级编码 + 向量派发 + 嵌套 + 软触发**。

---

## 0. 目标

- **源数**：32 个（可参数化 16 / 32 / 64）
- **每源属性**：4-bit 优先级、边沿/电平触发选择、掩码、软触发
- **优先级编码**：硬件选出当前最高优先级 pending 源
- **向量输出**：向 CPU 提供 `vec_id[7:0]` + 6-bit IP 编码（挂到 MIPS Cause.IP[7:2]）
- **配合 MIPS CP0**：与 `Cause.IV=1, IntCtl.VS>0` 联动，实现向量化异常入口
- **嵌套**：支持 CP0 EIC (External Interrupt Controller) 模式；软件在高优先级 ISR 中重开 `Status.IE`，硬件保证只有更高优先级源可再触发
- **APB 接口**：寄存器可读写，走 `soc_peripheral_subsystem` APB bridge

**不做**：
- MSI (message-signalled interrupts) — 需要 AXI master 端口写通知，Phase D+ 评估
- CP2 (第二 coprocessor) 中断路由 — 无 CP2 硬件

---

## 1. 中断源映射

| 源号 | 来源 | 类型 | 备注 |
|:-:|---|---|---|
| 0-1 | 保留（软触发 SW0/SW1）| 电平 | 软件写 SOFTINT 触发 |
| 2   | Timer (CP0 Count/Compare) | 电平 | 内部；镜像到 Cause.IP7，与 VIC 并列 |
| 3   | UART 0    | 电平 | 4 内部源 OR，见 UART spec |
| 4   | UART 1    | 电平 | 可选 |
| 5   | GPIO 组 A | 边沿 | 32-bit GPIO 边沿聚合 |
| 6   | GPIO 组 B | 边沿 | 可选 |
| 7   | DMA ch0 完成 | 边沿 | |
| 8   | DMA ch1 完成 | 边沿 | |
| 9-12 | DMA ch2-5 | 边沿 | |
| 13  | I2C 0    | 电平 | |
| 14  | SPI 0    | 电平 | |
| 15  | QSPI Flash 完成 | 边沿 | |
| 16  | SD/eMMC   | 电平 | |
| 17  | GMAC TX   | 边沿 | |
| 18  | GMAC RX   | 边沿 | |
| 19  | USB       | 电平 | |
| 20  | WDT 预警 | 边沿 | 溢出前警告；实际 WDT 到期直接复位 |
| 21-23 | Timer 1-3 | 电平 | 高级定时器 |
| 24-31 | 保留 | | |

**决策**：源 2 (Timer via CP0 Count/Compare) 走 `IntCtl.IPTI` 直接挂 IP7，不经 VIC；VIC 内部源 2 tie 0 或用于其他。

---

## 2. 寄存器映射 (APB, base = `SOC_APB_VIC_BASE`)

| Offset | 名称 | 宽 | RW | 说明 |
|:-:|---|:-:|:-:|---|
| 0x000 | INTR_RAW      | 32 | RO | 原始中断电平（未掩码） |
| 0x004 | INTR_MASKED   | 32 | RO | 掩码后 pending |
| 0x008 | INTR_ENABLE   | 32 | RW | 掩码使能（1=允许通过） |
| 0x00C | INTR_ENABLE_SET | 32 | W1S | 写 1 位对应 INTR_ENABLE 置 1 |
| 0x010 | INTR_ENABLE_CLR | 32 | W1C | 写 1 位对应 INTR_ENABLE 清 0 |
| 0x014 | INTR_TYPE     | 32 | RW | 0=电平，1=边沿 (per source) |
| 0x018 | INTR_POLARITY | 32 | RW | 0=高有效/上升沿，1=低有效/下降沿 |
| 0x01C | INTR_SOFT     | 32 | RW | 写 1 触发对应源软中断（源 0/1 首选） |
| 0x020 | INTR_SOFT_CLR | 32 | W1C | 清除 INTR_SOFT bit |
| 0x100–0x17C | INTR_PRIO[0..31] | 4 (占 32b 字) | RW | 每源 4-bit 优先级 (0=lowest, 15=highest) |
| 0x200 | VEC_ID     | 8 | RO | 当前最高优先级 pending 源号 (0-31)；无 pending 时 = `8'hFF` |
| 0x204 | VEC_IPRIO  | 4 | RO | 当前最高优先级值 |
| 0x208 | ACK        | 32 | W1C | 软件 ACK：写 1 到对应源 bit → 边沿源清 pending；电平源保持直到源撤 |
| 0x20C | ACTIVE     | 32 | RO | 当前正在处理（软件已进入 ISR 但未 ACK）的源位图 |
| 0x210 | RUNNING_PRIO | 4 | RO | 当前最高 ACTIVE 优先级 (用于嵌套判定) |

---

## 3. 硬件行为

### 3.1 Pending 生成

```
per source i:
  raw_i     = level 或 edge_detected input (per INTR_TYPE, INTR_POLARITY)
  edge det: 2-flop sync + rising/falling detector
  pending_i = raw_i && INTR_ENABLE[i]
```

### 3.2 优先级编码

- 组合并行找 `pending_i && (INTR_PRIO[i] > RUNNING_PRIO)` 中 `INTR_PRIO` 最大者
- 平票 → 源号小者优先
- 输出：`VEC_ID`, `VEC_IPRIO`, `int_req_to_cpu`

### 3.3 送 CPU

- `int_req_to_cpu` → 挂到 MIPS `Cause.IP` 中的某一 bit（`IntCtl.IPPCI` 或专用位）
- 若 CP0 `Status.IE && !EXL && !ERL && ((Cause.IP & Status.IM) != 0)` → CPU 接受中断
- CP0 EIC 模式（`Config3.VEIC=1`）：CPU 从 VIC 读 `VEC_ID` 决定向量偏移；`vector_addr = EBase + 0x200 + VEC_ID * (IntCtl.VS * 32)`
- **本 Phase D 选项**：不用 EIC，用简单方式 → VIC 只提供 `int_req` 单线到 CP0.IP[2]，ISR 软件读 `VEC_ID` 派发。将来切 EIC 需修 CP0 spec (`Config3.VEIC=1`) 并加 CPU-to-VIC 读端口。

### 3.4 嵌套支持

- ISR 进入后软件读 `VEC_ID` → 派发到 handler → 写 `ACTIVE |= (1 << src)` (硬件自动，读 VEC_ID 时置)
- 硬件 `RUNNING_PRIO = max(ACTIVE 中的 PRIO)`
- 后续中断只有当新源 `PRIO > RUNNING_PRIO` 才能 `int_req_to_cpu`
- ISR 结束前写 ACK 清 pending 与 ACTIVE bit → RUNNING_PRIO 回退

### 3.5 软件触发

- 写 `INTR_SOFT[i] = 1` → pending_i = 1 (与掩码 AND)
- 写 `INTR_SOFT_CLR[i] = 1` → 清 pending

---

## 4. 时序

- APB 访问单周期（除 read-modify 类可能 1 wait）
- Pending → int_req 组合传播；同拍可见
- ACK / SET / CLR 后 1 cycle 更新 pending/enable

---

## 5. 复位

- Reset: INTR_ENABLE=0, INTR_TYPE=0 (电平), INTR_POLARITY=0 (高有效), INTR_SOFT=0, ACTIVE=0, RUNNING_PRIO=0, INTR_PRIO=0
- 无 pending, int_req=0

---

## 6. 接口

```verilog
module apb_vic #(
    parameter NR_SOURCES = 32,
    parameter PRIO_BITS  = 4
)(
    input  wire         clk,
    input  wire         rst_n,

    // APB slave
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [11:0]  paddr,
    input  wire [31:0]  pwdata,
    output wire [31:0]  prdata,
    output wire         pready,
    output wire         pslverr,

    // Interrupt inputs
    input  wire [NR_SOURCES-1:0] intr_src,

    // CPU-side output
    output wire         int_req,       // to CP0 Cause.IP[x]
    output wire [7:0]   vec_id,        // to EIC (future); readable via APB
    output wire [PRIO_BITS-1:0] vec_prio
);
```

---

## 7. 验证要求

**块级** (`tb/uvm_tb/vic/`)：

- 每源单独触发：raw → masked → int_req → ACK 清。
- 边沿/电平 × 高/低有效 4 组合。
- 优先级仲裁：低源号高优先级 vs 高源号低优先级。
- 平票：多源相同优先级 → 源号小者先。
- 嵌套：进入低优先级 ISR，高优先级源触发 → 硬件重开 int_req；低优先级源在 ACTIVE 期间不重触发。
- 软触发 SW0/SW1 → int_req → ACK。
- 掩码 SET / CLR 原子性。
- Reset 状态：全 0、int_req=0。
- 与 CP0 联动：Cause.IE/IM/EXL/ERL 边界。
- 32 源全 pending 时 API 读取一致性。

**SVA**：
- `int_req == (∃ i, pending_i && enable_i && (PRIO_i > RUNNING_PRIO))`
- ACTIVE bit 只在 ACK 后清
- RUNNING_PRIO 单调更新（严格 max ACTIVE PRIO）

**Formal**：
- 优先级编码器 max 正确性（proven）
- 嵌套无死锁：任何 pending 序列最终收到 ACK（bounded liveness）

**性能**：
- Pending → int_req latency = 1 cycle (sync)
- ACK → int_req 撤 latency = 1 cycle

---

## 8. 演进

- **EIC 模式**：加 CP0 反向读端口 (`VEC_ID` 直接给 CPU 硬件用于向量派发)，`Config3.VEIC=1`
- **MSI**：加 AXI master 端口，中断源写内存地址通知
- **多核**：per-core enable / target mask
- **QoS-aware**：中断优先级动态调整（rarely needed）

---

## 版本记录

- v0 (2026-07-26)：初版规格，32 源 × 4-bit 优先级 + 嵌套 + 软触发 + APB 寄存器。等待 Phase D 启动评审。
