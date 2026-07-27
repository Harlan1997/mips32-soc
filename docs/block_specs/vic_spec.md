# 向量化中断控制器 (VIC) 微架构规格 (Phase 4D 商业化闭环)

> 状态：Phase 4D 商业化闭环。`rtl/perips/apb_vic.v` 已通过单顺序写控制（Single Sequential Writer）重构，完全消除多过程赋值警告。
> 当前 SoC 合同：单线 `irq` 输出至 CPU/CP0 Cause.IP[x] + APB 读取 `VEC_ID` 派发模型。

---

## 0. 目标与当前合同

- **源数**：32 个（参数化 NUM_SOURCES = 32）
- **每源属性**：4-bit 优先级、边沿/电平触发选择、触发极性、掩码使能、软触发
- **优先级编码**：组合逻辑选出最高优先级 pending 源；相同优先级按 lower source ID 仲裁
- **向量输出**：提供 `vec_id[7:0]` 与 `vec_prio[3:0]`；软件读 `VEC_ID`（0x200）触发 Accept 事件，更新 `ACTIVE` 状态
- **嵌套控制**：维护 `ACTIVE` 位图与 `RUNNING_PRIO`；仅严格更高优先级的 pending 源可抢占并重拉高 `irq`
- **APB 接口**：零等待响应（`pready = 1`, `pslverr = 0`）；未定义地址读零

**明确非目标（Future Work）**：
- CPU EIC/VEIC 硬件向量派发（需硬件 vector index 接口与 `Config3.VEIC=1`）
- MSI (Message-Signalled Interrupts)
- 多核中断路由与 CPU affinity 掩码
- 形式化验证 (Formal proof) 与 综合/时序闭环 (Synthesis/Timing closure)
- 更丰富的外部中断源映射表
- Coverage exclusion 文件的变更与维护

---

## 1. 当前 SoC 实际中断源映射 (Current DUT Wiring)

对齐 `rtl/soc_peripheral_subsystem.v` 的实际硬件连接：

| 源号 (Source ID) | 中断源名称 | 默认触发类型 / 极性 | 备注 |
|:-:|---|---|---|
| 0 | `uart_rx_int` | 电平 / 高有效 | 内部 UART RX 中断 |
| 1 | `uart_tx_int` | 电平 / 高有效 | 内部 UART TX 中断 |
| 2 | `timer_int`   | 电平 / 高有效 | 内部 Timer 中断 |
| 3 | `dma_int`     | 电平 / 高有效 | 内部 DMA 频道 OR 聚合中断 |
| 4..31 | 保留 / Tied Low | 电平 / 高有效 | 当前 SoC 硬件固定 tie 0 |

未来更丰富的中断源映射仅作为 Future Work 规划，不得混淆为当前集成 DUT 的行为。

---

## 2. 寄存器映射 (APB, Byte Offsets)

| Offset | 名称 | 宽 | RW | 说明 |
|:-:|---|:-:|:-:|---|
| 0x000 | INTR_RAW       | 32 | RO | 原始/软中断状态（未掩码前） |
| 0x004 | INTR_ENABLE    | 32 | RW | 掩码使能（1=允许）；兼容旧 PIC MASK |
| 0x008 | INTR_MASKED    | 32 | RO | 掩码后 pending 状态；兼容旧 PIC ACTIVE 读 |
| 0x00C | ENABLE_SET     | 32 | W1S | 写 1 置位 INTR_ENABLE |
| 0x010 | ENABLE_CLR     | 32 | W1C | 写 1 清零 INTR_ENABLE |
| 0x014 | TYPE           | 32 | RW | 0 = 电平触发，1 = 边沿触发 |
| 0x018 | POLARITY       | 32 | RW | 电平: 0=高有效, 1=低有效; 边沿: 0=上升沿, 1=下降沿 |
| 0x01C | SOFT           | 32 | RW | 写 1 设置对应源软中断 pending |
| 0x020 | SOFT_CLR       | 32 | W1C | 写 1 清除软中断 pending |
| 0x100–0x17C | PRIO[0..31] | 4 | RW | 32 个源的 4-bit 优先级配置 (0x100 + i*4) |
| 0x200 | VEC_ID        | 8 | RO | 最高优先级 pending 源号 (无 pending 时为 `8'hFF`)；`irq` 为 1 时读触发 Accept |
| 0x204 | VEC_IPRIO     | 4 | RO | 当前最高 pending 优先级 (无 pending 时为 0) |
| 0x208 | ACK           | 32 | W1C | 写 1 清除对应源的 ACTIVE、边沿 pending 及软中断 pending |
| 0x20C | ACTIVE        | 32 | RO | 当前正在服务（已 Accept 未 ACK）的源位图 |
| 0x210 | RUNNING_PRIO  | 4 | RO | 当前 ACTIVE 源中的最高优先级 |

---

## 3. 硬件与状态机制

### 3.1 单顺序写控制 (Single Sequential Writer)
`apb_vic.v` 中的每一个状态寄存器（`enable_r`, `type_r`, `polarity_r`, `soft_r`, `edge_pending_r`, `active_r`, `prio_r`）必须且仅由一个 `always @(posedge clk or negedge rst_n)` 块驱动，严禁跨多过程赋值。

### 3.2 仲裁与抢占 (Arbitration & Preemption)
- **Pending 计算**：`raw = level_pend | edge_pending_r | soft_r`; `pending = raw & enable_r`
- **Encoder**：在 `pending` 中选出 `prio_r` 最大者 `best_id_r`。平票时 `lower source ID` 优先。
- **IRQ 产生**：当无 `ACTIVE` 源时，任意 pending 源拉高 `irq`；有 `ACTIVE` 源时，仅当 `best_pri_r > RUNNING_PRIO` 时拉高 `irq`。
- **Accept 机制**：仅当 `irq` 为 1 时，读 `VEC_ID` 会将 `best_id_r` 置位到 `active_r`。在 `irq` 为 0 时重复读 `VEC_ID` 不会破坏或重复修改 `active_r`。

---

## 4. 验证与门控

- 单元门控：`make dut-block-unit-gate` (包含 `tb/unit/vic/tb_vic.v` 覆盖 16 项商业化合约测试)
- 产品固件门控：`make vic-cpu-gate` (运行 `tb/soc_test/fw/tests/vic_cpu/` 固件验证 APB-visible VIC 行为)

---

## 版本记录

- Phase 4D (2026-07-27)：完成 VIC 商业化闭环。重构 `apb_vic.v` 单顺序写控制，扩充 `tb_vic.v` 单元测试与 `vic_cpu` 产品固件门控。
- v1 (2026-07-27)：更新为当前 DUT 基线。
