# 乘除单元 (MDU) 微架构规格 (v0)

> 状态：v0 草案。作为 Phase B **重构 `rtl/cpu/mips_mdu.v`** 的实施基线。现状 MDU 阻塞 EX 阶段直到完成，本规格把它改为独立多周期 FSM，与 pipeline 解耦，含早退出优化。

---

## 0. 目标

- 覆盖 MIPS32 R2 整数 M-单元指令：`MULT / MULTU / MUL / DIV / DIVU / MADD / MADDU / MSUB / MSUBU / MFHI / MFLO / MTHI / MTLO / CLO / CLZ`。
- **乘法**：3-5 cycle（可参数化，24Kc 目标 ≤ 5）。
- **除法**：radix-2 或 radix-4，18 或 9 cycle for 32-bit。
- **早退出**：MULT 若高 16 位相同（sign extension）→ 短路 2-cycle；DIV 若除数覆盖高位为 0/1 → 提前退出。
- **独立于 EX**：MDU FSM 与主流水线并行，写回 HI/LO；EX 只在 MFHI/MFLO/MADD 等需要 HI/LO 结果时才 stall（写后读依赖）。

**不做**：
- 硬件浮点（在 FPU/CP1 单元中）
- SIMD / MIPS DSP ASE

---

## 1. 指令行为

### 1.1 有符号乘法 `MULT rs, rt`

`{HI, LO} = signed(rs) * signed(rt)`（64 位）。3-5 cycle FSM。

### 1.2 无符号乘法 `MULTU rs, rt`

`{HI, LO} = unsigned(rs) * unsigned(rt)`。

### 1.3 32-bit 乘 `MUL rd, rs, rt`（R2 新增）

`rd = (rs * rt)[31:0]`；**HI/LO 不定**（spec 允许乱刷，但保守做法保持 HI/LO 不变或写入低 32 位）。3-5 cycle。

### 1.4 有符号除法 `DIV rs, rt`

`LO = rs / rt`（有符号商）；`HI = rs % rt`（有符号余数，符号跟 rs）。
- 除数为 0：`{HI, LO}` 未定义（MIPS spec 说明不产生异常，交由软件检查）。实现建议：`LO = -1, HI = rs` 用于确定性。
- 18-cycle radix-2 或 9-cycle radix-4。

### 1.5 无符号除法 `DIVU rs, rt`

类似 DIV。除 0：`LO = 32'hFFFF_FFFF, HI = rs`。

### 1.6 乘加乘减 `MADD / MADDU / MSUB / MSUBU`（R2）

- `MADD rs, rt`：`{HI, LO} += signed(rs) * signed(rt)`（有符号）
- `MADDU`：无符号
- `MSUB / MSUBU`：`{HI, LO} -= ...`
- 时序：等价于 MULT + 加/减，可复用乘法器 3-5 cycle + 1 cycle 加法。

### 1.7 HI/LO 移动 `MFHI / MFLO / MTHI / MTLO`

- `MFHI rd`：`rd = HI`
- `MFLO rd`：`rd = LO`
- `MTHI rs`：`HI = rs`
- `MTLO rs`：`LO = rs`
- **hazard**：在 MDU busy 时读 HI/LO → stall。写 HI/LO 与 in-flight MULT/DIV 竞争 → 后写者赢（软件责任避免；建议 SVA 断言检测）。

### 1.8 前导 0/1 计数 `CLZ rd, rs` / `CLO rd, rs`（R2）

- `CLZ`：rs 前导 0 的个数 (0-32)
- `CLO`：rs 前导 1 的个数
- **1-cycle 组合**（可放 EX 阶段完成，不占 MDU FSM）。

---

## 2. 微架构 FSM

### 2.1 状态

```
ST_IDLE  → 空闲
ST_MUL   → 乘法 3-5 cycle iterations (Booth radix-4 或 shift-add)
ST_DIV   → 除法迭代
ST_MADD  → 乘 + 加/减
ST_DONE  → 1 cycle 写 HI/LO 回寄存器
```

### 2.2 乘法器实现选项

| 选项 | 面积 | 延迟 | 备注 |
|---|---|---|---|
| A. 单周期 32×32 组合 | 大 | 1 cycle | 综合会跑不上高频 |
| **B. Booth radix-4, 5-cycle** | 中 | 5 cycle | 24Kc 常见选择 |
| C. Wallace tree pipelined 3-stage | 大 | 3 cycle (throughput 1/cycle) | 面积换性能 |

**Phase B 默认**：B (Booth radix-4)，`parameter MUL_LATENCY = 5`；提供 A/C 参数化开关备将来切换。

### 2.3 除法器实现

**Radix-2 恢复余数除法**：18 cycles = 1 (setup) + 32 (iterate 1 bit/cycle) - early exit + 1 (writeback)。

**早退出**：
- 检查 |rs| < |rt| → 商 = 0, 余数 = rs → 3 cycle 完成。
- 检查 rt 高 16 位 = 0 且 rs 高 16 位 = 0 → 16 iter 而非 32。
- 计数除数前导 0，跳过对应 iter。

**Radix-4** (可选)：每 cycle 2 bit → 9 cycle。综合面积代价约 +30%。Phase B 默认 radix-2；`parameter DIV_RADIX = 2` 可切 4。

### 2.4 早退出乘法 (符号 extension)

`MULT` / `MULTU` 检查：
- `rs[31:16] == {16{rs[15]}}` 且 `rt[31:16] == {16{rt[15]}}` → 短 mul（3 cycle）。
- 全 0：结果直接 0，1 cycle。
- 覆盖 CoreMark 常见小整数乘法。

---

## 3. 与流水线交互

### 3.1 发射 (Issue)

- ID 阶段解码 MDU 指令 → 若 MDU busy → **stall ID 与 IF**（保守，避免多 outstanding hazard）。
- MDU idle → 接收操作数，FSM 转 ST_MUL/DIV/MADD；ID 与 IF 可继续（后续指令不等 MDU 完成，除非再遇 MDU 或 MFHI/MFLO）。

### 3.2 依赖 stall

- **MFHI/MFLO 遇 MDU busy** → stall ID（HI/LO 未 ready）。
- **MTHI/MTLO 遇 MDU busy** → stall ID（避免竞争写 HI/LO）。可选优化：kill in-flight MDU 但 spec 不要求。
- **MADD/MADDU/MSUB/MSUBU 遇 MDU busy** → stall ID。

### 3.3 写回

- MDU 完成后单 cycle 写 HI 与 LO（并行）。
- 若同 cycle 有 MTHI/MTLO 写请求（不应发生 — 已 stall），SVA 报错。

### 3.4 异常与冲刷

- 无异常（MIPS spec 定义除 0 不异常）。
- 流水线冲刷（异常/mispredict）时：
  - 未完成的 MDU 操作**继续运行**（结果虽然可能被 kill 的指令产生，但架构 spec 允许 HI/LO 结果无关软件顺序）。可选保守：flush MDU → ST_IDLE。
  - **Phase B 决策**：Flush MDU 到 IDLE，简化 hazard。代价 <5% 性能（异常/mispredict 罕见）。

---

## 4. 参数化

`rtl/include/soc_config.vh`：

```verilog
`define SOC_MDU_MUL_LATENCY   5
`define SOC_MDU_DIV_RADIX     2      // 2 or 4
`define SOC_MDU_EARLY_EXIT    1
```

---

## 5. 接口

```verilog
module mips_mdu #(
    parameter MUL_LATENCY = `SOC_MDU_MUL_LATENCY,
    parameter DIV_RADIX   = `SOC_MDU_DIV_RADIX
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // Issue interface (ID)
    input  wire        issue_valid,
    input  wire [3:0]  issue_op,       // MULT/MULTU/DIV/DIVU/MADD/.../MTHI/MTLO
    input  wire [31:0] rs_data,
    input  wire [31:0] rt_data,
    output wire        issue_ready,    // MDU idle → accept

    // HI/LO read (MFHI/MFLO from EX)
    output wire [31:0] hi_data,
    output wire [31:0] lo_data,
    output wire        hilo_ready,     // 0 → MDU busy, stall

    // Status
    output wire        busy
);
```

---

## 6. 验证要求

**块级** (`tb/uvm_tb/mdu/`)：

- 每指令类型 × 边界值 (0, 1, -1, MAX_INT, MIN_INT, 除 0) 全组合。
- Radix-2 除法：8 种前导 0/1 组合覆盖早退出路径。
- 早退出乘法：sign-extension short mult 命中/未命中。
- MADD/MSUB 覆盖 HI/LO 初值 0 与非 0。
- MFHI/MFLO 遇 busy stall 循环。
- Flush during MDU busy：FSM 回 IDLE，无残留输出。

**SoC 级 firmware**：

- Dhrystone / CoreMark 覆盖典型 mult/div 密度。
- 递归函数（MADD 场景）。
- 大量 short mult (256 × 256) 触发早退出。

**SVA**（bind）：

- `busy` 期间 `issue_ready=0`。
- HI/LO 写口不与外部 MTHI/MTLO 同 cycle 触发。
- FSM 状态编码合法。
- 除法迭代计数 ≤ 32 (radix-2) 或 ≤ 16 (radix-4)。

**Formal**：
- 每种 op 结果与参考模型（黄金 Verilog 或 Python）等价（bounded 除法迭代 32 depth）。
- 除 0 行为确定性（LO=-1, HI=rs 恒立）。

**性能门槛**：
- CoreMark 中 MULT/DIV 平均延迟测量与目标 (5 / 18 cycle) 一致。
- MDU stall 占总执行时间 < 5%（正常 workload）。

---

## 版本记录

- v0 (2026-07-26)：初版规格，Booth radix-4 乘法 5-cycle + radix-2 除法 18-cycle + 早退出 + Flush-to-IDLE。等待 Phase B 启动评审。
