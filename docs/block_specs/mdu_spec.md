# 乘除单元 (MDU) 微架构规格 (v1.1)

> 状态：v1.1 Phase 4B 已闭合。`rtl/cpu/mips_mdu.v` 作为多周期 MDU
> 已完全闭合 CPU-visible MDU ISA Gap，支持 `MULT/MULTU/DIV/DIVU/MFHI/MFLO/MTHI/MTLO`
> 及 `MADD/MADDU/MSUB/MSUBU` 和 `MUL rd, rs, rt` 的 CPU 解码与写回。

---

## 0. 目标

- CPU 已支持指令：`MULT / MULTU / DIV / DIVU / MFHI / MFLO / MTHI / MTLO`，`MADD / MADDU / MSUB / MSUBU`，`MUL rd, rs, rt`。
- `CLO / CLZ` 不属于 MDU block 合同（属于 EX / ALU 路径）。
- **乘法**：behavioral 32x32 乘法器，3-cycle 模型；小操作数早退出。
- **除法**：32-cycle restoring radix-2，含确定性除零行为。
- **流水线合同**：MDU FSM 与主流水线并行；EX 通过 HI/LO hazard 与 busy 状态 stall。

**不做**：
- 硬件浮点（在 FPU/CP1 单元中）
- SIMD / MIPS DSP ASE

---

## 1. 指令行为

### 1.1 有符号乘法 `MULT rs, rt`

`{HI, LO} = signed(rs) * signed(rt)`（64 位）。3-5 cycle FSM。

### 1.2 无符号乘法 `MULTU rs, rt`

`{HI, LO} = unsigned(rs) * unsigned(rt)`。

### 1.3 32-bit 乘 `MUL rd, rs, rt`（MIPS32 R2，CPU-visible）

`rd = (rs * rt)[31:0]`；**HI/LO 不定**（spec 允许乱刷，但保守做法保持 HI/LO 不变或写入低 32 位）。3-5 cycle。

### 1.4 有符号除法 `DIV rs, rt`

`LO = rs / rt`（有符号商）；`HI = rs % rt`（有符号余数，符号跟 rs）。
- 除数为 0：`{HI, LO}` 未定义（MIPS spec 说明不产生异常，交由软件检查）。实现建议：`LO = -1, HI = rs` 用于确定性。
- 18-cycle radix-2 或 9-cycle radix-4。

### 1.5 无符号除法 `DIVU rs, rt`

类似 DIV。除 0：`LO = 32'hFFFF_FFFF, HI = rs`。

### 1.6 乘加乘减 `MADD / MADDU / MSUB / MSUBU`（MIPS32 R2，CPU-visible）

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

- 不在当前 MDU block 中实现。
- 后续 CPU ISA 完备性阶段应作为 EX/ALU 组合路径或独立单元处理，并添加 firmware/UVM 场景。

---

## 2. 微架构 FSM

### 2.1 状态

```
ST_IDLE  → 空闲
ST_MUL   → behavioral 乘法 3-cycle 模型或小数早退出
ST_DIV   → 32-cycle radix-2 除法迭代
ST_ACC   → 乘加/乘减累加
ST_DONE  → 1 cycle 写 HI/LO 回寄存器
```

### 2.2 乘法器实现选项

| 选项 | 延迟 | 备注 |
|---|---|---|---|
| A. 单周期 32×32 组合 | 1 cycle | 组合路径较长 |
| **B. Booth radix-4, 5-cycle** | 中 | 5 cycle | 24Kc 常见选择 |
| C. Wallace tree pipelined 3-stage | 3 cycle (throughput 1/cycle) | 用流水化换取吞吐 |

**当前 RTL**：使用 Verilog `*` 的 behavioral 乘法，配 3-cycle latency
模型。Booth/radix-4、Wallace tree 或定制乘法器可作为后续 RTL 演进方向。

### 2.3 除法器实现

**Radix-2 恢复余数除法**：最多 32 次 1-bit 迭代，加 setup/fixup/done 状态。

**早退出**：
- 检查 |rs| < |rt| → 商 = 0, 余数 = rs → 3 cycle 完成。
- 计数除数前导 0，跳过对应 iter。

**Radix-4**：不在当前 RTL 合同内，作为后续性能增强项。

### 2.4 早退出乘法 (符号 extension)

`MULT` / `MULTU` 检查：
- `rs[31:16] == {16{rs[15]}}` 且 `rt[31:16] == {16{rt[15]}}` → 短 mul（3 cycle）。
- 全 0：结果直接 0，1 cycle。
- 覆盖 CoreMark 常见小整数乘法。

---

## 3. 与流水线交互

### 3.1 发射 (Issue)

- ID 阶段解码 MDU 指令 → 若 MDU busy → **stall ID 与 IF**（保守，避免多 outstanding hazard）。
- MDU idle → EX 发出单周期 issue pulse；流水线在 launch/busy 期间保持该 EX 指令，直到结果/HI/LO 更新完成。

### 3.2 依赖 stall

- **MFHI/MFLO 遇 MDU busy** → stall ID（HI/LO 未 ready）。
- **MTHI/MTLO 遇 MDU busy** → stall ID（避免竞争写 HI/LO）。可选优化：kill in-flight MDU 但 spec 不要求。
- **MADD/MADDU/MSUB/MSUBU 遇 MDU busy** → stall ID。

### 3.3 写回

- MDU 完成后单 cycle 写 HI 与 LO（并行）。
- 若同 cycle 有 MTHI/MTLO 写请求（不应发生 — 已 stall），SVA 报错。

### 3.4 异常与冲刷

- 无异常（MIPS spec 定义除 0 不异常）。
- `flush` 对在途 MDU 操作具有最高优先级：采样到 `flush` 时回到
  `ST_IDLE`，清除乘法/除法中间状态，不更新 HI/LO，也不产生 `done_pulse`。
- 当前 CPU 将 `exception_flush | ctx_restore_req` 连接到 `flush`，覆盖异常、ERET、
  中断和上下文恢复冲刷。取消后下一周期可重新发射；BPU 误预测没有独立 flush
  输入，仍遵循当前延迟槽/resolve 恢复路径。

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
- Radix-2 除法：除 0、`MIN_INT`、符号修正、余数符号、早退出路径。
- 早退出乘法：小操作数命中/未命中。
- MADD/MSUB 覆盖 HI/LO 初值 0 与非 0。
- MFHI/MFLO 遇 busy stall 循环。
- Flush during MDU busy：`make mdu-flush-gate` 覆盖乘法/除法取消、HI/LO 保持、
  完成脉冲抑制和取消后重新发射。

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
- CoreMark 中 MULT/DIV 平均延迟测量与当前 RTL latency 合同一致。
- MDU stall 占总执行时间 < 5%（正常 workload）。

---

## 版本记录

- v1.1 (2026-07-27)：Phase 4B CPU-visible MDU ISA 闭合，解禁 MADD/MADDU/MSUB/MSUBU/MUL 的 CPU 译码与写回，增加 mdu_cpu 固件门禁。
- v1 (2026-07-27)：更新为当时 DUT 基线；CPU 仅暴露 legacy HI/LO
  MDU op，MADD/MADDU/MSUB/MSUBU/MUL 当时标为块级已实现、CPU 集成待闭合，CLO/CLZ
  移出 MDU 当前合同，乘除 latency 与 flush 语义按当前 RTL 重述。
- v0 (2026-07-26)：初版规格，Booth radix-4 乘法 5-cycle + radix-2 除法 18-cycle + 早退出 + Flush-to-IDLE。等待 Phase B 启动评审。
