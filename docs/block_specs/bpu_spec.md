# 分支预测单元 (BPU) 微架构规格 (v0)

> 状态：v0 草案。作为 Phase B **新增 `rtl/cpu/mips_bpu.v` + 修改 `rtl/cpu/mips_if_stage.v` / `mips_id_stage.v` / `mips_cpu.v`** 的实施基线。

---

## 0. 目标与范围

**目标**：把当前 5 段流水线的静态"不跳"预测升级为**动态预测**，降低 CPI，与 MIPS 24Kc 竞品对齐。

- **命中率目标**：SPECint / CoreMark 常见分支模式 ≥ 90% (2-bit 饱和计数器)。
- **误预测代价**：1-cycle bubble（沿用现有 ID 阶段解析条件分支的架构）。
- **预测端**：IF 阶段并行给出下一 PC，与 I-cache 索引同拍。
- **解析端**：条件分支 (BEQ/BNE/BLEZ/BGTZ/BLTZ/BGEZ/BLTZAL/BGEZAL) 在 ID 阶段解析（沿用现有 forwarding）；无条件跳转 (J/JAL/JR/JALR) 在 ID 阶段目标可算，与条件分支同延迟。
- **延迟槽**：MIPS 硬性 1-slot 延迟槽由 ISA 保证，BPU 不需额外处理，但预测必须与延迟槽指令联动（预测方向 = 预测下一 PC；不预测延迟槽本身）。

**不做**（本 phase）：
- 竞态感知全局历史 (GShare / GAg / gselect)
- Perceptron / TAGE
- Loop predictor
- Indirect branch target prediction (超出 RAS 覆盖的 JR)
- Precise branch outcome recovery（当前 in-order 单一 in-flight branch，简化）

---

## 1. 结构

BPU 由三个子组件构成：

### 1.1 分支目标缓冲器 (BTB)

- **组织**：直接映射，256 entries（可参数化 128/256/512）。
- **索引**：`BTB_INDEX = PC[BTB_IDX_LSB + BTB_IDX_BITS - 1 : BTB_IDX_LSB]`；`BTB_IDX_LSB = 2` (跳过字对齐)。
- **每 entry**：
  - `valid` (1 bit)
  - `tag` (`ADDR_WIDTH - BTB_IDX_BITS - 2` bits)
  - `target` (30 bit, 字对齐)
  - `type` (2 bit)：`00=cond`, `01=jump_direct`, `10=jr_return`, `11=jalr_call`
- **命中条件**：`valid && tag == PC[高位]`。
- **复位**：所有 `valid = 0`；不需清 tag/target/type。

### 1.2 分支历史表 (BHT) — 2-bit 饱和计数器

- **组织**：256 或 512 entries（`parameter BHT_ENTRIES`），2-bit saturation counter，状态编码 `00=SN, 01=WN, 10=WT, 11=ST`。
- **索引**：与 BTB 共享 `PC[BTB_IDX_LSB +: log2(BHT_ENTRIES)]`（避免额外 XOR，简化）。
- **仅用于条件分支**；无条件分支忽略 BHT，直接用 BTB 目标 + 静态"必跳"。
- **预测方向**：`counter[1] == 1 → taken`。
- **复位**：全部初始化为 `WN (2'b01)`，偏保守。

### 1.3 返回地址栈 (RAS) — 可选

- **深度**：8 entries（`parameter RAS_DEPTH`），环形。
- **入栈**：JAL / JALR 类型（`BTB.type == call`）预测时 `push (PC+8)`（延迟槽后 PC）。
- **出栈**：JR 类型（`BTB.type == jr_return`，或 JR $ra 简单启发式）预测时 `pop → 预测 target`。
- **溢出/下溢**：环形覆盖，无异常；仅影响命中率。

---

## 2. 预测路径 (IF 阶段)

```
IF (predict):
  1. bpu_hit    = BTB.valid && BTB.tag == PC_hi
  2. bpu_taken  = case (BTB.type)
                    cond       : BHT[idx][1]
                    jump_direct: 1'b1
                    jr_return  : ras.valid
                    jalr_call  : 1'b1
                  endcase
  3. bpu_target = case (BTB.type)
                    jr_return : ras.top
                    default   : BTB.target
                  endcase
  4. next_PC = bpu_hit && bpu_taken ? bpu_target : (PC + 4)
```

**关键约束**：BTB/BHT 读为**单周期组合**（同拍出结果，与 I-cache index 并行）。若 SRAM 需注册端口，则 BTB/BHT 用 **flop-based 或双端口 register-file** 实现避免额外 pipe stage。

**延迟槽**：预测 taken 时，IF 依然继续取 `PC+4`（延迟槽），并把 `bpu_target` 放入 IF+1 slot；一拍后 fetch `bpu_target`。

---

## 3. 解析与更新 (ID / EX)

### 3.1 条件分支解析 (ID)

- 沿用现有 forwarding：ID 阶段计算 `branch_take_actual`。
- 与 IF 阶段的 `bpu_taken_pred` 对比：
  - **误预测方向**：冲刷 IF+1（1 bubble）+ 修正 PC。
  - **误预测目标**（BTB 命中但地址错，比如 tag alias）：冲刷 IF+1 + 修正 PC。
  - **BTB miss + 实跳**：冲刷 IF+1 + 分配 BTB entry。
  - **正确预测**：无 bubble。

### 3.2 无条件跳转解析 (ID)

- J/JAL：目标 = `PC[31:28], instr[25:0], 2'b00`；BTB miss 时 1-bubble 冲刷 + 分配 entry (`type=jump_direct`)。
- JAL/JALR：BPU 预测时 push RAS；ID 解析时若目标匹配则无 bubble；否则冲刷。
- JR：BPU 预测走 RAS；若 RAS 命中且目标匹配 → 无 bubble；否则冲刷 + 更新 RAS。

### 3.3 BTB 更新时机

- 在 ID 阶段解析完成后，写回 BTB 与 RAS（保守：EX 阶段写以避开与 IF 读冲突）。
- 更新策略：
  - **taken 但 BTB miss** → allocate: 写 valid=1, tag, target, type。
  - **taken 且 BTB 命中但 target 变** → update target（间接跳转常见）。
  - **not-taken 条件分支** → 只更新 BHT（-1 计数），BTB entry 保留。
  - **BHT 更新**：命中 taken → counter++（sat）；命中 not-taken → counter--（sat）。

### 3.4 冲突处理

- IF 读端口与 ID/EX 写端口冲突：写优先 + 转发到读，或 IF 阶段读旧值（1 拍延迟无害，最多一次多余 misprediction）。

---

## 4. Reset / Flush 语义

- Reset：BTB.valid 全清 0；BHT 全 `WN`；RAS.top=0, RAS.count=0。
- 异常/中断冲刷：BPU 内部状态**不清**（保留学习）；仅清 IF 阶段 in-flight predict slot。
- ERET：同上。
- TLB 更新（TLBWI/WR）后 I-cache flush：BPU **不需清**（tag 匹配 VA，与 PA 无关）。若担心 alias，Phase C 可加软件 `SYNCI` 后清 BPU 的钩子。

---

## 5. 参数化

`rtl/include/soc_config.vh` 新增：

```verilog
`define SOC_BPU_ENABLE       1
`define SOC_BTB_ENTRIES      256
`define SOC_BHT_ENTRIES      256
`define SOC_RAS_DEPTH        8
`define SOC_BPU_IDX_LSB      2
```

`SOC_BPU_ENABLE=0` → BPU 组合固定输出 `bpu_hit=0, next_PC=PC+4`（静态不跳），供早期 bring-up。

---

## 6. 接口 (module port)

```verilog
module mips_bpu #(
    parameter BTB_ENTRIES = `SOC_BTB_ENTRIES,
    parameter BHT_ENTRIES = `SOC_BHT_ENTRIES,
    parameter RAS_DEPTH   = `SOC_RAS_DEPTH,
    parameter ADDR_WIDTH  = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // IF stage: predict
    input  wire                    if_valid,
    input  wire [ADDR_WIDTH-1:0]   if_pc,
    output wire                    predict_hit,
    output wire                    predict_taken,
    output wire [ADDR_WIDTH-1:0]   predict_target,
    output wire [1:0]              predict_type,

    // ID/EX stage: resolve & update
    input  wire                    resolve_valid,     // branch/jump resolved
    input  wire [ADDR_WIDTH-1:0]   resolve_pc,
    input  wire                    resolve_taken,
    input  wire [ADDR_WIDTH-1:0]   resolve_target,
    input  wire [1:0]              resolve_type,
    input  wire                    resolve_mispredict,

    // Optional: pipeline flush signal (does not clear BPU state)
    input  wire                    flush_if
);
```

---

## 7. 验证要求

**块级** (`tb/uvm_tb/bpu/`)：

- 每种 type × taken/not-taken × BTB hit/miss × BHT 状态 (SN/WN/WT/ST) 组合覆盖。
- BHT 学习曲线：连续 8 次 taken 后 SN→ST；连续 4 次 not-taken 后回 SN。
- BTB alias：不同 PC 映射同 index 导致误预测 → 覆盖点。
- RAS 溢出/下溢：连续 push 超 8 → 覆盖 wrap 后正确性（可放弃精度，但不能 hang）。
- Reset 后首次预测：BHT=WN → 应 not-taken。

**SoC 级 firmware** (`tb/soc_test/bpu/`)：

- 简单循环 (for i in 1..N)：稳态命中率 ≥ 90%。
- 嵌套函数调用 (JAL / JR $ra)：RAS 命中 ≥ 95%。
- 间接跳转 (计算式 JR): BTB 命中率视 workload；至少不 hang。

**SVA**（bind 至 `mips_bpu`）：

- IF 阶段 `predict_hit=1` 时 `predict_target` 必对齐 4 字节。
- resolve 时 mispredict 与 taken/target 一致性检查。
- RAS 计数器不出 [0, RAS_DEPTH]。
- BHT counter 保持 sat 边界。

**Formal**：

- BPU 内部 FSM 无死锁：任何序列后能回到"稳态"（bounded proof 10 cycles）。
- 复位后一段时间内 (BTB 全 miss) BPU 行为等价静态不跳。

**性能门槛**：

- CoreMark 分支命中率 ≥ 88%（Phase B 结束时测）。
- Dhrystone 分支命中率 ≥ 90%。

---

## 8. 后续演进（不属于 Phase B）

- GShare / gselect：加入 GHR (global history register) 与 BHT index XOR，用于关联式分支。
- 分离 T/NT BTB：减少冲突。
- 提早解析：把简单条件分支 (BEQ zero, BNE zero) 挪到 IF 阶段解析，去掉 1 bubble。
- 精确 speculation：多个 in-flight 分支时的 mispredict 恢复（多 outstanding 需要 checkpoint）。

---

## 版本记录

- v0 (2026-07-26)：初版规格，BTB 256 + BHT 256 (2-bit) + RAS 8 + 1-bubble misprediction。等待 Phase B 启动评审。
