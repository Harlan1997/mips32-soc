# 验证计划 (vPlan) v0

> 状态：战略规划参考，不是当前功能状态或 signoff 依据。当前 RTL 状态以
> `docs/functional_completeness_plan.md` 和 `docs/functional_evidence_registry.md`
> 为准；当前签核门槛以 `docs/signoff_criteria.md` 为准。
>
> 目的：把每一个需要验证的 SoC 特性映射到明确的验证方法、覆盖率契约、责任子团队与状态。每次评审滚动更新。

---

## 0. 验证方法总览

| 方法 | 工具/环境 | 交付物 | 用途 |
|---|---|---|---|
| **块级 UVM** | VCS + UVM 1.2 (`tb/uvm_tb/`) | agent / seq / cov / scoreboard | 复杂子系统穷举 |
| **SoC UVM** | 同上 (`tb/uvm_tb/tests/`) | 端到端 test | 集成 + 契约 |
| **Firmware 回归** | `tb/soc_test/` MIPS 交叉编译 | .hex 固件 + 观测 | ISA / 中断 / DMA 场景 |
| **SVA 断言** | bind 挂 (`tb/uvm_tb/checkers/`) | 属性文件 | 协议 + 局部时序 |
| **Formal** | VC-Formal / JasperGold FPV | 属性 + 约束 + 报告 | 关键 FSM / arbitration / TLB |
| **ISA-Ref 联合仿真** | QEMU-MIPS (`tb/isa_ref/`) | retire differential harness | QEMU plugin + one-insn CPU snapshots + RTL JSONL compare；完整 SoC/长期 ISA signoff 仍未闭合 |
| **ISA Compliance** | MIPS compliance suite | pass/fail 报告 | ISA 合规 |
| **Linux Boot 回归** | U-Boot + kernel + rootfs (`tb/linux_boot/`) | 日志 + shell 提示符检测 | 端到端功能 |
| **Lint** | SpyGlass Lint 或 Ascent Lint | 报告 + waiver | 编码规范强制 |
| **CDC / RDC** | VC-CDC / SpyGlass CDC / Meridian | 报告 + waiver | 跨域收敛 |
| **性能基准** | CoreMark / Dhrystone / STREAM (`tb/perf/`) | CPI + 带宽指标 | 微架构目标验证 |
| **Fault Injection** | UVM sequence + SVA | 报告 | 错误恢复路径 |

---

## 1. 特性 × 方法 矩阵

图例：✓ 主验证方法；~ 辅助；空 不适用。责任子团队为占位符，待团队建立。

### 1.1 CPU 核心

| 特性 | 块 UVM | SoC UVM | Firmware | SVA | Formal | ISA-Ref | Compliance | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|---|---|
| MIPS32 R2 ISA 指令集 | ~ | | ✓ | | | ✓ | ✓ | CPU-DV | `cp0_spec.md`, ISA Vol II | Phase A 部分 |
| 5 段流水线 hazard/forwarding | | ✓ | ✓ | ✓ | | ✓ | | CPU-DV | RTL/现有验证 | 现有 |
| CP0 完整寄存器 (20 regs) | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | CPU-DV | `cp0_spec.md` | Phase B |
| 精确异常 (含 BD 位) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | CPU-DV | `cp0_spec.md` §14 | Phase B |
| 用户/内核态 (KSU) | ~ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | CPU-DV | `cp0_spec.md` §3 | Phase B |
| MMU / TLB (64-entry) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | CPU-DV | `mmu_tlb_spec.md` | Phase B |
| 中断 (8 IP + vectored) | ✓ | ✓ | ✓ | ✓ | ✓ | | | CPU-DV | `cp0_spec.md` §3.4 | Phase B |
| Count/Compare 定时器 | ✓ | ✓ | ✓ | ✓ | | | | CPU-DV | `cp0_spec.md` §9 | Phase B |
| 分支预测 (BTB + 2-bit) | ✓ | ~ | ✓ | ✓ | ~ | | | CPU-DV | `block_specs/bpu_spec.md` | 已有有限切片 |
| MDU 多周期 FSM | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | | CPU-DV | `block_specs/mdu_spec.md` | 当前合同已闭合 |
| FPU CP1 (可选) | | | | | | | | CPU-DV | 未建立 spec | 后续可选 |
| LL/SC 原子 | ~ | ~ | ✓ | ✓ | ✓ | | | CPU-DV | `cp0_spec.md` §1 LLAddr | Phase B (opt) |

### 1.2 缓存与总线

| 特性 | 块 UVM | SoC UVM | Firmware | SVA | Formal | Compliance | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|---|---|
| L1 I-Cache 4-way + CACHE | ✓ | ✓ | ✓ | ✓ | ~ | | Cache-DV | `block_specs/icache_spec.md` | 当前合同范围 |
| L1 D-Cache 4-way + WB/WA | ✓ | ✓ | ✓ | ✓ | ~ | | Cache-DV | `block_specs/dcache_spec.md` | 当前合同范围 |
| L2 统一缓存 | ✓ | ✓ | ✓ | ✓ | ✓ | | Cache-DV | `block_specs/l2_spec.md` | 当前合同范围；增强项 deferred |
| AXI 多 outstanding + 乱序 | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | Bus-DV | 待更新 axi_spec.md | Phase C |
| AXI QoS/PROT/CACHE 语义 | ~ | ✓ | | ✓ | | ✓ | Bus-DV | 同上 | Phase C |
| Crossbar 仲裁 (multi-M/S) | ✓ | ✓ | ~ | ✓ | ✓ | | Bus-DV | `block_specs/axi_fabric_spec.md` | 当前单 outstanding 合同 |
| Cache 一致性接口 (预留) | ~ | | | ~ | ✓ | | Cache-DV | `block_specs/multicore_coherency_spec.md` | 有限双核合同；MESI deferred |

### 1.3 外设

| 外设 | 块 UVM | SoC UVM | Firmware | SVA | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|---|---|---|
| UART 16550 | ✓ | ✓ | ✓ | ✓ | Perf-DV | `block_specs/uart_16550_spec.md` | 当前合同范围 |
| QSPI Flash Ctrl | ✓ | ✓ | ✓ | ✓ | Perf-DV | `block_specs/qspi_spec.md` | 当前合同范围 |
| DDR4 Ctrl | ✓ | ✓ | ✓ | ✓ | Mem-DV | `block_specs/ddr4_spec.md` | 当前 RTL 合同 |
| SD/eMMC | | | | | Perf-DV | 未建立 spec | 后续产品范围 |
| GMAC 千兆 | | | | | Perf-DV | 未建立 spec | 后续产品范围 |
| USB 2.0 (采购 IP) | 供应商 | ✓ | ✓ | ✓ | IP-Integ | vendor | Phase D |
| I2C/SPI 主从 | | | | | Perf-DV | 未建立 spec | 后续产品范围 |
| 高级 Timer/WDT/PWM | ✓ | ✓ | ✓ | ✓ | Perf-DV | RTL/现有验证 | 当前有限范围 |
| VIC 中断控制器 | ✓ | ✓ | ✓ | ✓ | Perf-DV | `block_specs/vic_spec.md` | 当前合同范围 |
| GPIO 边沿中断 | | | | | Perf-DV | 未建立 spec | 后续产品范围 |
| DMA scatter-gather 多通道 | ✓ | ✓ | ✓ | ✓ | Perf-DV | `block_specs/dma_spec.md` | 当前合同范围 |
| eFuse/OTP | | | | | Sec-DV | 未建立 spec | 后续产品范围 |
| JTAG TAP + Debug Master | ~ | ✓ | | ✓ | Dbg-DV | 现有 | Phase A |

### 1.4 时钟 / 复位 / CDC

| 特性 | 块 UVM | SoC UVM | SVA | Formal | CDC | RDC | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|---|---|
| 多时钟域架构 | | ✓ | ✓ | | ✓ | | Infra | `block_specs/clock_reset_spec.md` | 规划/尚未闭合 |
| 复位同步器 (AASD) | ✓ | ✓ | ✓ | ✓ | | ✓ | Infra | 同上 | Phase E |
| CDC 单元库 (FIFO/handshake/pulse) | ✓ | | ✓ | ✓ | ✓ | | Infra | 同上 | Phase E |

### 1.5 系统级

| 场景 | SoC UVM | Firmware | Linux Boot | Perf | Fault | 责任 | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|---|---|
| Boot from QSPI (BEV) | ~ | ✓ | ✓ | | | Integ | Phase B/F |
| U-Boot → kernel handoff | | | ✓ | | | Integ | Phase F |
| Busybox shell prompt | | | ✓ | | | Integ | Phase F |
| CoreMark / Dhrystone | | ✓ | ✓ | ✓ | | CPU-Perf | Phase F |
| STREAM / memcpy 带宽 | ✓ | ✓ | ✓ | ✓ | | Mem-Perf | Phase F |
| AXI DECERR / SLVERR 恢复 | ✓ | ✓ | | | ✓ | Bus-DV | 现有 |
| Watchdog 复位 | | ✓ | ✓ | | ✓ | Infra | Phase D/E |
| ECC 单/双 bit 错误 (未来) | ✓ | | | | ✓ | Mem-DV | 后续 |

---

## 2. 覆盖率契约

### 2.1 代码覆盖率（Phase A 后强制）

| 指标 | 门槛 | 域 |
|---|---|---|
| LINE | ≥ 99% | UVM adj + Product adj |
| COND | ≥ 99% | 同上 |
| BRANCH | ≥ 99% | 同上 |
| TOGGLE | ≥ 99% | 同上 |
| FSM (state) | ≥ 99% | 同上 |
| FSM (transition) | ≥ 95% | 同上 |
| SCORE | ≥ 99% | 同上 |

**Exclusion 政策**：object-level 精化；每条 exclusion 需 spec 引用和 evidence，
并由当前 signoff 流程审计。历史 session 规则不再作为本 vPlan 的外部依赖。

### 2.2 功能覆盖率

- **必须 100%**：`coverage_plan.md` 定义的所有 15+ 覆盖组（含 Phase B-E 新增）。
- **每新增子系统**：至少 1 组功能覆盖，含关键 cross。

### 2.3 断言覆盖率（Phase F 起）

- 所有 SVA property 必须至少一次 `cover` 命中。
- 关键属性（AXI 握手、TLB 命中/未命中、中断优先级）100% cover + 100% assert 通过。

### 2.4 Formal 覆盖率（Phase F 起）

- 每个 formal proof 报告 proven / bounded / cex 状态。
- Bounded proof 需注明 bound 深度（≥ 20 cycles 或功能等价证明）。

---

## 3. 门槛 (Phase Gate) 汇总

| Phase | Gate 条件 | 参考 |
|---|---|---|
| A 结束 | 覆盖率 ≥99% + Lint 0 error + 仓库清理 + tb/coverage 决策落地 | `signoff_criteria.md` (现有 3D) |
| B 结束 | CP0 完整 + MMU + BPU + MDU + 精确异常 + MIPS ISA compliance 100% + ISA-Ref co-sim >1e9 指令 无 mismatch + CoreMark 通过 | 本文件 §1.1 |
| C 结束 | L1 4-way + L2 + 多 outstanding AXI + AXI compliance + 缓存一致性 formal | 本文件 §1.2 |
| D 结束 | 所有外设块级 + SoC 级 pass + register model (RAL) 覆盖 100% | 本文件 §1.3 |
| E 结束 | 多时钟域 + CDC 0 违规 + RDC 0 违规 + AASD 复位 | 本文件 §1.4 |
| F 结束（前端签核） | SVA 库 + formal 关键模块 proven + Linux boot 稳定 + 所有 §2 覆盖率契约达标 + `docs/frontend_signoff_checklist.md` 全绿 | 本文件 §1.5 |

---

## 4. 责任分配（占位）

| 子团队 | 覆盖 |
|---|---|
| CPU-DV | 内核 + CP0 + MMU + BPU + MDU + FPU + 异常 |
| Cache-DV | L1 I/D + L2 + CACHE 指令 + 一致性 |
| Bus-DV | AXI fabric + QoS + protocol + crossbar |
| Perf-DV (外设) | UART/QSPI/SD/GMAC/I2C/SPI/Timer/GPIO/DMA/VIC |
| Mem-DV | DDR3 ctrl + ECC (未来) |
| Sec-DV | eFuse + secure boot (未来) |
| Dbg-DV | JTAG TAP + debug master + EJTAG (未来) |
| Infra | 时钟/复位/CDC/Lint/CDC-CI |
| IP-Integ | 外部 IP 接口集成 |
| Integ | 系统级 boot + Linux + 性能 |

每 phase 起始由 verification lead 分工登记 + owner 签字。

---

## 5. Spec 与后续工作状态

The block specs listed in the matrix are now present under
`docs/block_specs/`. Their presence does not imply that every planned feature
is implemented: each spec records its current RTL boundary and deferred work.

Current contract work is tracked by the functional completeness plan and
evidence registry. The following remain future work or optional scope:

- FPU/CP1 and full ISA compliance.
- Multi-outstanding AXI/QoS beyond the current single-outstanding contract.
- Full Linux/OS boot, production boot policy, and long-duration stress.
- Lint, CDC/RDC, formal proof, and final release packaging.

Do not add a new block spec to this list unless the corresponding module is
actually in project scope. Optional FPU work has no spec in the current tree.

---

## 6. 工具与环境依赖

| 依赖 | 现状 | 需要 |
|---|---|---|
| VCS | ✓ | 保持 |
| UVM 1.2 | ✓ | 保持 |
| MIPS 交叉编译 (gcc-mips) | ✓ | 保持 |
| SpyGlass Lint 或 Ascent Lint | ✗ | Phase A |
| VC-CDC / SpyGlass CDC | ✗ | Phase E |
| VC-Formal 或 JasperGold FPV | ✗ | Phase B/F |
| QEMU-MIPS (build for co-sim) | ✗ | Phase B |
| MIPS Compliance Suite | ✗ | Phase B |
| U-Boot MIPS port | ✗ | Phase F |
| Linux kernel + busybox rootfs | ✗ | Phase F |

工具环境和 EDA module 加载约定见仓库根目录 `AGENTS.md`。

---

## 版本记录

- v0 (2026-07-26)：初版战略级 vPlan。
- 2026-08-08：标注当前合同来源，移除已完成 spec 的“待写”表述，明确后续产品范围。
