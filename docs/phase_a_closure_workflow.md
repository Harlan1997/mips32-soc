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

**已知教训**（本 session 抓到）：APB peripheral 有 side-effect (GPIO DATA readback 依赖 DIR，Timer LOAD 会启动计数等)，seq 写模式前需先设置模式位。见 `axi_apb_bit_pattern_sweep_seq` GPIO DIR pre-config。

### 2c. Coverage threshold < 99%
所有 gate 都过后，`COVERAGE_THRESHOLDS` 检查失败。历史观察 (`.agent/review.md`)：
- UVM 域：Score 93.9 / Cond 97.4 / Toggle 79.1 / FSM 98.9 / Branch 94.1
- Product 域：Score 88.4 / Line 78.2 / Toggle 75.9 / FSM 94.3 / Branch 93.5

**主要 gap**：TOGGLE 覆盖率（79/76），因为 register 位模式 sweep 不够；Line/Branch 因 firmware 未穷举 ISA。

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

### 4.1 短期（下一 session）
1. **CPU firmware ISA sweep** — 在 `tb/soc_test/fw/` 加一段 C/asm 遍历所有 R1/R2 ALU 指令 + 各种 branch + load/store 变体。会显著提升 Product Line/Branch 覆盖率。
2. **Cache miss/hit variation** — 现有 firmware 触发 dcache 状态较少；加一段刻意跨越 cache line 的 memcpy 强制多次 refill/eviction。提升 dcache FSM。
3. **Fabric backpressure sweep** — 慢 slave 响应场景压 axi_arbiter FSM 少见状态。
4. **APB register additional patterns** — 若 signoff 报告显示某些 APB 寄存器仍未 100% toggle，加针对该寄存器的 seq。

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
