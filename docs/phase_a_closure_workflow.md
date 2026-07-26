# Phase A — 99% 覆盖率闭合工作流

> 状态：v0 草案，基于 2026-07-26 session 实测经验总结。
>
> 目的：把 `make current-contract-signoff` 从"跑一次失败一次"变成可迭代收敛的工程。前 5 次 AGY 尝试全部失败（quota、timeout、cardinality mismatch 等），本文档记录已建立的基础设施 + 下一轮该按什么节奏推进。

---

## 1. 一次完整 signoff 的解剖（实测）

`make current-contract-signoff` 是 5-stage 串行 gate（`tb/uvm_tb/run_current_contract_signoff.sh`）：

| Stage | 内容 | 单次耗时 | Cardinality 硬约束 |
|---|---|---|---|
| 1/5 Phase 2 gate  | 16 directed test × 2 (functional + coverage) | ~3-5 min | `-ne 16` |
| 2/5 Phase 3A gate | 5 deferred-feature test × 2  (post-c9d095a/fa417a0)     | ~2-3 min | `-ne 5`  |
| 3/5 Phase 3B gate | 1 CPU/CP0 exception smoke                          | <1 min   | `-ne 1`  |
| 4/5 Phase 3C gate | 1 PIC mask arbitration                             | <1 min   | `-ne 1`  |
| 5/5 stress merge  | `NUM_TESTS` 多种子 stress + merged URG             | ~5-10 min| —        |

**总耗时**：约 15-30 分钟（依 build 缓存热度）。**任何 gate 失败 → 整个 signoff 立即退出**。因此 iteration turnaround 是"改 → 15+ min → 报告"。

---

## 2. 常见失败模式（已见）

### 2a. Test cardinality mismatch
新增 test 忘 bump signoff 脚本里的 `-ne N` 硬编码 → `REGRESSION_CARDINALITY` fail。修法：新增 test 时同步修改 phase*_directed_tests.txt + `run_current_contract_signoff.sh` 里的 3 处 (`-ne N` 判定 + 2 处 error msg)。

### 2b. UVM_ERROR in new test
新增 test 内的断言失败 → gate fail。**避免方式**：新增 sequence 必须先 `make uvm UVM_TEST=xxx` 独立跑通 REGRESSION_TEST_SUCCESS + 0 UVM_ERROR 才纳入 phase testlist。

**已知教训**（本 session 抓到）：
- APB peripheral 有 side-effect (GPIO DATA readback 依赖 DIR，Timer LOAD 会启动计数等)，seq 写模式前需先设置模式位。见 `axi_apb_bit_pattern_sweep_seq` GPIO DIR pre-config。

### 2d. Firmware sweep 的 CP0 / 中断 / TLB side-effect (信号 #5/#6 教训 2026-07-26)
新增 `cp0_sweep` firmware 例程扫 CP0 寄存器 → signoff #5 Phase 2 gate FAIL；`soc_bus_stress_test` + `soc_base_test` 在 sim time ~362 ms 触发大量 `[AXI_MON] SRAM monitor observed extra W beat` UVM_ERROR + `axim3/axim4 protocol_checker BVALID asserted with no completed write data`。**错误诊断**：初以为是 Compare 未 restore → Timer IRQ storm；signoff #6 加了 Compare=0xFFFF_FFFF restore 后**依旧同一位置同一错**。实际 root cause 更深，可能之一：
- 写 EntryHi / Wired / PageMask 后 TLB 状态污染（虽然 SOC_MMU_ENABLE=0 但内部信号可能被观察）
- 写 HWREna=0x2000000F 影响 RDHWR 路径
- 写 IntCtl.IPTI / VS 改变中断 vector 位置

**Firmware sweep 编写清单**（每加一条 sweep 必查）：
1. 该 sweep 修改的所有寄存器**必须在 return 前 restore 到 reset 值**
2. 该 sweep 触发的所有异常路径**必须能自然 resolve**（handler advance EPC 或不重触发）
3. 该 sweep 对 SRAM / 外设 / cache 状态的持久修改**不能影响后续 UVM tests**（UVM tests 与 firmware 并行跑）
4. **每次加 sweep 后先 `make uvm UVM_TEST=soc_bus_stress_test`** 独立验证，再 `make uvm UVM_TEST=soc_base_test`，再全 signoff。这两个 test 对 firmware 副作用最敏感
5. `cp0_sweep` 里 MMU register 写（Index/EntryHi/EntryLo0/1/PageMask/Wired/Context）**必须彻底 restore**；HWREna 也 restore；IntCtl 也 restore；Compare 也 restore

### 2c. Coverage threshold < 99%
所有 gate 都过后，`COVERAGE_THRESHOLDS` 检查失败。**2026-07-26 session 后**（Phase B + 2 新 stimulus 后）实测：

### 2c. Coverage threshold < 99%
所有 gate 都过后，`COVERAGE_THRESHOLDS` 检查失败。**2026-07-26 session 后**（Phase B + 2 新 stimulus 后）实测：

| 指标 | UVM actual | UVM Δ vs review | Product actual | Product Δ vs review |
|---|---|---|---|---|
| SCORE  | 92.71 | ↓1.19 | 87.46 | ↓0.91 |
| LINE   | **100.00 ✓** | 达标 | 79.70 | ↑1.54 |
| COND   | 97.93 | ↑0.53 | **100.00 ✓** | 达标 |
| TOGGLE | 78.70 | ↓0.44 | 75.45 | ↓0.46 |
| FSM    | 98.85 | 0      | 94.29 | 0     |
| BRANCH | 88.07 | **↓6.05** | 87.88 | **↓5.60** |

**主要 gap**：
- **BRANCH 双域 ~88%**（Phase B 加大量 decode/MMU/BPU 分支，firmware/UVM stimulus 覆盖不到新增指令，特别是 ROTR/WSBH/MOVN 等 firmware 未发射的 R2 指令）
- **TOGGLE 双域 ~76-79%**（register 位模式 sweep 不足 —— 本 session 的 APB bit pattern sweep 是首个针对性解决，覆盖 GPIO/Timer/DMA/PIC；CPU/cache/fabric 内部信号 toggle 未系统覆盖）
- **Product LINE 79.70%**（firmware 未穷举 ISA + 未系统触发 cache 状态）
- **Product FSM 94.29%**（部分 FSM 状态过渡未触发，特别是 AXI arbiter 争抢场景、cache miss/refill 序列）

**规律**：Phase B 系列引入的新 RTL（新指令 decoder / MMU / BPU）扩大了 coverage denominator 比 stimulus 增量快，短期 BRANCH/SCORE 下滑是正常的。真正闭合需要 stimulus 与 RTL 增长同步。

---

## 3. 已建立的闭合基础设施

### 3.1 目录约定
- `tb/uvm_tb/seqs/` — sequence class
- `tb/uvm_tb/tests/` — test class wrapper（`tb_top.sv` 需 `include`）
- `tb/uvm_tb/phase{2,3,3b,3c}_directed_tests.txt` — 每 phase testlist
- `tb/coverage/{uvm,product}_exclusions.el` — 精化 exclusion
- `tb/coverage/exclusion_manifest.json` — exclusion 分类审计

### 3.2 加新 stimulus test 的标准步骤
1. 写 `seqs/axi_XXX_seq.sv` — 该 seq 是主 stimulus 生成器
2. 写 `tests/soc_XXX_test.sv` — 简单 wrapper，`` `include `` seq + `start()`
3. `tb_top.sv` line 25-30 附近 `` `include "../tests/soc_XXX_test.sv" ``
4. `phase3_directed_tests.txt` 加 `soc_XXX_test 1`（Phase 3A 是 deferred-feature closure 的最合适位置）
5. `run_current_contract_signoff.sh` 里 `-ne N` 从旧值 bump +1（4 处：两个 `-ne`，两个 error msg 的"expected N"）
6. **独立跑** `make uvm UVM_TEST=soc_XXX_test`：必须 `REGRESSION_TEST_SUCCESS + 0 UVM_ERROR`，否则修 seq
7. `make firmware && make current-contract-signoff` 跑全流程（15+ min）
8. 若 gate 全过，看 coverage_summary.json 数值变化

### 3.3 已在 phase3 testlist 的 Phase A 闭合 stimulus（本 session 加）
- `soc_axi_attribute_cross_sweep_test` — 16 ID × 4 burst len × 5 window × 2 direction sweep（`axi_attribute_cross_sweep_seq`）
- `soc_apb_bit_pattern_sweep_test` — walking-1/walking-0/交替位 pattern 覆盖 GPIO/Timer/DMA/PIC 寄存器（`axi_apb_bit_pattern_sweep_seq`）

---

## 4. 下一轮 iteration 优先级

按预期收益排序（每加一批 stimulus → 跑一次 signoff → 看 numeric 变化）：

### 4.1 短期（下一 session）—— 按数据决定的优先级
1. **CPU firmware ISA sweep（最高优先）** — 是当前 BRANCH ↓6% 的直接原因。在 `tb/soc_test/fw/` 加 asm 或 C-with-inline-asm 序列，显式发射：
   - R2 新增：CLZ / CLO / SEB / SEH / WSBH / ROTR / ROTRV / MOVN / MOVZ
   - R1 尚未完全覆盖的：所有 branch 变体 (BEQ/BNE/BLEZ/BGTZ/BLTZ/BGEZ + AL 变体) taken 和 not-taken
   - Load/Store 全组合：LB/LBU/LH/LHU/LW + SB/SH/SW，跨越对齐边界
   - MDU: MULT / MULTU / DIV / DIVU + 各种 corner (0/负/最大)
   会显著提升 Product Line/Branch 覆盖率 + UVM decoder BRANCH 覆盖率。**必须先 rebuild firmware.hex 才生效**。
2. **Cache miss/hit variation** — 现有 firmware 触发 dcache 状态较少；加一段刻意跨越 cache line 的 memcpy 强制多次 refill/eviction。提升 dcache FSM 覆盖率。
3. **Fabric backpressure sweep** — 慢 slave 响应场景压 axi_arbiter FSM 少见状态。提升 axi_arbiter_2x1_full FSM。
4. **APB register additional patterns** — 若 signoff 报告显示 UART_TX / PIC STATUS 等仍未 100% toggle，加针对该寄存器的 seq。（当前 apb_bit_pattern_sweep 覆盖 GPIO/Timer/DMA/PIC.MASK，不含 UART）

### 4.2 中期
5. **Object-level exclusion refactor** — 拆除 `product_exclusions.el` / `uvm_exclusions.el` 里 review 明确禁的 module/all-metric exclusion，改成 object-level + spec-category evidence。这是 spec 强制要求且 AGY 之前都在这里失败。
6. **Manifest JSON re-cataloging** — exclusion_manifest.json 需与新 .el 同步；每条 exclusion 必须挂 spec category（`UNREACHABLE_CURRENT_CONTRACT` / `STATIC_TIEOFF_RESERVED` / etc.）+ evidence 引用。

### 4.3 若数值仍无法收敛
7. Bump `NUM_TESTS` (stress regression seed 数) 从 10 到 20-30 提升 toggle 覆盖。
8. 分析 `build/signoff/current_contract/*/adjusted/*.txt` 找出仍 <99% 的具体 module × metric，追加窄 stimulus。

---

## 5. 关键脚本引用

- 主入口：`tb/uvm_tb/run_current_contract_signoff.sh`
- 子入口：`run_phase2_complete.sh` / `run_phase3_complete.sh` / `run_phase3b_complete.sh` / `run_phase3c_complete.sh`
- Coverage merge：`tb/coverage/refine_exclusions.py`, `generate_manifest_and_el.py`, `audit_exclusions.py`
- 报告：`build/signoff/current_contract/signoff_report.md`（成功时）
- Spec：`.agent/spec.md`（RUN-CURRENT-CONTRACT-COVERAGE-99-002）
- Review：`.agent/review.md`（REJECTED 分析）

---

## 版本记录

- v0 (2026-07-26)：初版，基于 session 加入的 2 个新 stimulus + 1 次实测 signoff 失败经验汇总。
