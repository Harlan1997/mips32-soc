# RTL 编码规范 (v0)

> 状态：v0 草案。适用于 `rtl/` 下所有新增与大改代码；存量模块允许暂不追溯，但触及即修。
>
> 目的：为商用级 AP 芯片前端签核提供**可 Lint、可 CDC 校验、可综合、可 formal**的一致代码基线。所有规则均可被 SpyGlass/Ascent Lint 或人工评审机械化检查。

---

## 0. 通用原则

1. **可综合优先**：`rtl/` 只写可综合子集。仿真专用构造 (`$display`, `initial`, `#delay`, `assert`) 必须放在 `tb/` 或用 `` `ifdef SIMULATION `` / `` synopsys translate_off `` 严格围栏。
2. **一份约定，一次决策**：命名、复位、时钟、参数化、错误响应任一维度只允许一种实现方式；变体在 `docs/rtl_coding_style.md` 显式登记后方可使用。
3. **Lint 零违规**：每次 push 前 lint 必须过。新增违规必须在同一 PR 里 waive 或修复。
4. **禁止 push 未解决的 X 传播**：所有寄存器复位有确定初值；组合逻辑分支穷举 default。

---

## 1. 文件与目录

- 文件名 = 顶层 module 名 + `.v` / `.sv`；一个文件一个 module，禁止匿名模块。
- 后缀选择：
  - 纯 Verilog-2001 可综合模块 → `.v`
  - 需要 SystemVerilog 结构 (interface/struct/enum) 的可综合模块 → `.sv`
  - 断言 bind、UVM、覆盖率、参考模型 → `.sv` 且置于 `tb/`
- **`rtl/` 内禁止出现**：仿真产物 (`simv`, `csrc/`, `*.log`)、编辑器备份、`patch_*.py` 脚本。这些属于 `build/` 或 `scripts/`。
- 目录组织沿用现状：`cpu/`、`cache/`、`axi/`、`perips/`、`clock/`(新增)、`include/`；新增大子系统再拆一层子目录。

### 文件头（强制）

```verilog
// =============================================================================
// File Name : <basename>.v
// Module    : <top module name>
// Design    : <一句话职责>
// Standard  : Verilog-2001 | SystemVerilog-2012 subset (synthesizable)
// Reset     : async assert / sync deassert (see §3)
// Clock     : <primary clock name, e.g. cpu_clk>
// =============================================================================
```

---

## 2. 命名

| 对象 | 规则 | 示例 |
|---|---|---|
| module / instance | snake_case | `mips_cp0`, `u_axi_arbiter` |
| 端口 / 内部信号 | snake_case | `axi_arvalid`, `epc_next` |
| 参数 (`parameter`) | UPPER_SNAKE | `parameter TLB_ENTRIES = 64` |
| 宏 (`` `define ``) | UPPER_SNAKE，模块级加前缀 | `` `SOC_AXI_ID_WIDTH `` |
| 本地参数 (`localparam`) | UPPER_SNAKE | `localparam ST_IDLE = 3'd0` |
| 复位低有效 | 后缀 `_n` | `rst_n`, `flush_n` |
| 低有效使能 | 后缀 `_n` | `cs_n` |
| 差分对 | 后缀 `_p` / `_n` | `ddr_ck_p`, `ddr_ck_n` |
| 时钟 | 前缀 `clk` 或 `_clk` 后缀标域 | `clk`, `ddr_clk`, `axi_clk` |
| 复位（每域独立） | `<domain>_rst_n` | `cpu_rst_n`, `ddr_rst_n` |
| FSM 状态编码 | `ST_<NAME>` `localparam` | `ST_REFILL` |
| 输出 reg | 后缀 `_r` 表示为寄存器输出 | `arvalid_r` |
| 组合中间信号 | 后缀 `_c` 或 `_w`（可选） | `next_state_c` |
| 参数化例化 | 例化名前缀 `u_` | `u_dcache`, `u_l1_arb` |

**禁用**：驼峰、大小写混合、缩略语拼错（Addr/Adr 二选一，全项目统一 `addr`）。

---

## 3. 复位策略

- **单一约定**：**异步置位、同步释放（async assert / sync deassert, "AASD"）**。
  - 触发：`always @(posedge clk or negedge rst_n)`
  - 每个时钟域独立配一个复位同步器 (`rtl/clock/reset_sync.v`)，输出 `<domain>_rst_n` 供该域内所有寄存器使用。
  - 输入端 (`rst_n`) 由 POR / 软复位 / WDT 复位聚合后进入同步器。
- 所有寄存器**必须有复位分支**给出确定值。允许例外：数据 payload FIFO/RAM 存储阵列，可只复位控制指针（需在文件头 Reset 注明）。
- **禁止**：混用同步和异步复位；跨域直接使用未同步的 `rst_n`；只置位无释放。

```verilog
// 标准模板
always @(posedge cpu_clk or negedge cpu_rst_n) begin
    if (!cpu_rst_n) begin
        state_r  <= ST_IDLE;
        count_r  <= '0;
    end else begin
        state_r  <= state_next_c;
        count_r  <= count_next_c;
    end
end
```

---

## 4. 时钟与 CDC

- 每个时钟只由**一个** PLL/分频器产生；模块内部禁止再分频（除非用 ICG cell 门控）。
- **禁止组合逻辑门控时钟**；需要门控用 `rtl/clock/clkgate_icg.v` (基于 latch-based ICG cell)。
- 跨时钟域信号 (`clk_a` → `clk_b`) 必须走以下之一：
  1. **握手同步器** `rtl/clock/handshake_sync.v`
  2. **脉冲同步器** `rtl/clock/pulse_sync.v`
  3. **async FIFO** `rtl/clock/async_fifo.v`
  4. **灰码计数器** + 2-flop 同步器（多 bit 计数）
- 单 bit 电平信号可用 2-flop 同步器（`rtl/clock/sync_2ff.v`），源端必须为寄存器输出。
- 所有 CDC 路径必须能被 CDC 静态验证 (VC-CDC / SpyGlass CDC / Meridian) 识别；打不上标签必须 waive 并在 `docs/cdc_waivers.md` 登记。

---

## 5. 组合逻辑

- **禁止 latch**：所有 `always @*` 分支必须写完整或用赋默认值语句。
- **敏感列表**：Verilog-2001 用 `always @*`；SV 用 `always_comb`。禁止手写敏感列表。
- **case 语句**必须有 `default`；FSM 用 `case` 而非 `if-else` 级联。
- **禁止**在同一 `always` 块混用阻塞 (`=`) 与非阻塞 (`<=`) 赋值。
  - 组合：阻塞 `=`
  - 时序：非阻塞 `<=`
- **三元优先级**：一层三元表达式允许，超过两层拆 `case` 或组合函数。

---

## 6. FSM 编码

- 状态用 `localparam` + `[N-1:0]` 编码，长度显式：`localparam [2:0] ST_IDLE = 3'd0;`
- **一段式 FSM 禁止**；采用**两段式**（时序 + 组合次态）或**三段式**（+ 组合输出）。
- 状态迁移必须能被 FSM 覆盖率工具识别；避免在 `case` 里做函数副作用。
- 允许的编码：二进制、格雷（跨 CDC 时强制）、独热（大状态数）。
- 每个 FSM 提供不可达状态的 `default: state_next_c = ST_IDLE;` 兜底并在注释注明"unreachable — safety recovery"。

---

## 7. 参数化与配置

- 芯片级参数进 `rtl/include/soc_config.vh`（已存在）；模块级参数用 `parameter` 端口暴露。
- **禁止 hard-coded magic number** 出现在 RTL 表达式中；用 `parameter` / `localparam` / `` `define ``。
- 例外：宽度为 0/1、复位向量索引等自解释常量。
- 例化时**按名传递** (`.PARAM_NAME(VALUE)`) 与**按名连线** (`.port(sig)`)。禁止顺序传参。

---

## 8. 接口与端口

- 顶层模块端口按类别分组注释（时钟复位 / 配置 / 数据 / 状态 / 调试）。
- 优先用 SystemVerilog `interface` 封装同类总线束（AXI/APB）—— Phase C 起启用；纯 Verilog 模块用 `` `include `` 接口宏。
- **禁止 `inout`**（顶层 pad 除外）。
- 未使用的输入端口用 `assign unused = &{...};` 收拢，避免 lint 报 unused。

---

## 9. 复位值与 X 传播

- 所有 `reg` 必须有复位分支。
- **禁止**在 RTL 使用 `x` 或 `?` 作为赋值目标（RTL 而非 assertion 语境）。case 语句用 `casez` 需谨慎，且必须有 `default`。
- 未初始化的存储阵列（RAM）在仿真里可加 `` `ifdef SIMULATION `` 的 `initial` 填 `x` 检 X 传播。

---

## 10. 断言与调试

- **仿真消息**：`$display` / `$write` / `$monitor` 必须置于 `` `ifdef SIMULATION `` 或 `// synopsys translate_off` 围栏。
- **RTL 内建 SVA**：允许 `` `ifndef SYNTHESIS `` 内写 `assert property` 用作单元自检，但**主断言库必须以 bind 方式挂在 `tb/uvm_tb/checkers/`**，不侵入 RTL 源。
- **调试信号**（VIO 或观测）通过命名良好的 monitor 输出，或用 `soc_observation_if` 现有机制。

---

## 11. 错误响应与协议合规

- AXI slave 必须对所有非法地址返回 `DECERR`；权限错误返回 `SLVERR`。禁止吞没或悬空。
- 所有握手 (valid/ready) 严格遵循 AMBA：`valid` 一旦拉高不得撤，直到 `ready` 采样。
- FIFO 空满、单调计数器溢出等边界必须有 SVA 覆盖或断言。

---

## 12. 电源意图 (Power Intent) 兼容

即使当前不做物理实现，RTL 需按 UPF 假设写：

- 跨电源域信号必须走 isolation 单元位（RTL 建模：多路选 `1'b0`/`1'b1` 兜底）。
- retention flop 通过 `(* retention *)` 属性或 `rtl/clock/ret_flop.v` 包装。
- 电源域边界信号命名 `<dstdom>_<srcdom>_<sig>`。

---

## 13. 综合与工具指令 pragma

- 允许：`// synopsys translate_off/on`（仿真专属代码围栏）、`(* keep = "true" *)`（防止综合优化）、`(* preserve *)`。
- **禁止**：`// synopsys full_case`、`// synopsys parallel_case`（用完整 `case` + `default` 代替）；`// synopsys dc_shell` 等工具专用后门。

---

## 14. 例化与层次

- 顶层子系统层次不超过 4 级（`soc_top` → `subsystem` → `block` → `submodule`）。
- 每个 subsystem 只跨其自身时钟域，跨域连接在 subsystem 边界的 CDC 单元中完成。
- 模块间不允许通过 `defparam` 覆盖参数。

---

## 15. 注释

- 文件头（§1）、端口分组、FSM 状态含义、非平凡算法必写注释。
- 注释语言：**英文优先**，中文允许出现在文件头 Design 一句话与内部临时说明。
- 禁止写"what"注释（代码可读即可）；只写"why"和 spec 引用（`// per MIPS32 R2 vol II §2.4.1`）。

---

## 16. Git 与提交

- 一个提交一个逻辑单元；跨模块大改分多次提交。
- Commit message 前缀分类：`rtl(cpu):`、`rtl(cache):`、`tb(uvm):`、`docs:`、`build:`、`ci:`、`chore:`。
- **禁止**提交 `simv`、`*.log`、`csrc/`、`urgReport/`、`fullexclude.*`；`.gitignore` 已覆盖。

---

## 17. Lint 与 CDC 门槛（Phase A 后强制）

- Lint (SpyGlass Lint 或 Ascent Lint)：0 error, 0 critical warning，warning waive 需在 `syn/lint/waivers/` 登记原因。
- CDC (VC-CDC / SpyGlass CDC / Meridian)：0 violation，同步器识别率 100%。
- RDC：0 violation。
- Formal Sanity (`formal_lint` / `hal-formal`)：无 dead code / unreachable FSM state（除 §6 安全兜底）。

---

## 附录 A：现存模块偏差登记（v0 快照）

以下已知偏离本规范，需在 Phase A/B 逐步收敛。触及即修，不强求追溯：

| 位置 | 偏差 | 修复计划 |
|---|---|---|
| `rtl/cpu/mips_cp0.v:79` | RTL 内 `$display` 未围栏 | Phase B CP0 重写时清理 |
| `rtl/perips/apb_uart.v` | 用 `$write` 实现 TX | Phase D 替换为 16550 |
| `rtl/soc_fabric.v` | 地址 nibble 硬编码 (0x0/0x1/0x4/0xA) | Phase A：改为 `soc_config.vh` 宏引用 |
| `rtl/mips_soc_impl.v` 参数 `ENABLE_*` | 产品/验证边界耦合 | Phase 3D 已启动，Phase E 完结 |
| `rtl/patch_*.py`, `rtl/simv` | 非 RTL 产物混入 | Phase A：移出或 gitignore |
| 所有模块 | 单时钟单同步复位 | Phase E：改 AASD + 每域复位同步器 |

---

## 版本记录

- v0（2026-07-26）：初版，覆盖命名 / 复位 / CDC / FSM / 参数化 / 断言 / 电源意图 / 综合 pragma / Lint 门槛。
- 计划 v1：Phase A 结束时结合 Lint 实践反馈迭代；补充 SVA 编写规范细则、SV interface 具体模板。
