# 验证计划 (vPlan) v0

> 状态：v0 草案，前端签核范围。与 `docs/coverage_plan.md`（战术级 coverpoint 清单）与 `docs/signoff_criteria.md`（当前签核门槛）互补：本文件是**战略级 × 全特性 × 全方法**总览。
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
| **ISA-Ref 联合仿真** | QEMU-MIPS 或 Sail-MIPS (`tb/isa_ref/`) | co-sim harness | 每条 retire 指令架构状态比对 |
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
| 5 段流水线 hazard/forwarding | | ✓ | ✓ | ✓ | | ✓ | | CPU-DV | 待补 pipeline spec | 现有 |
| CP0 完整寄存器 (20 regs) | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | CPU-DV | `cp0_spec.md` | Phase B |
| 精确异常 (含 BD 位) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | CPU-DV | `cp0_spec.md` §14 | Phase B |
| 用户/内核态 (KSU) | ~ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | CPU-DV | `cp0_spec.md` §3 | Phase B |
| MMU / TLB (64-entry) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | CPU-DV | `mmu_tlb_spec.md` | Phase B |
| 中断 (8 IP + vectored) | ✓ | ✓ | ✓ | ✓ | ✓ | | | CPU-DV | `cp0_spec.md` §3.4 | Phase B |
| Count/Compare 定时器 | ✓ | ✓ | ✓ | ✓ | | | | CPU-DV | `cp0_spec.md` §9 | Phase B |
| 分支预测 (BTB + 2-bit) | ✓ | ~ | ✓ | ✓ | ~ | | | CPU-DV | 待写 bpu_spec.md | Phase B |
| MDU 多周期 FSM | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | | CPU-DV | 待写 mdu_spec.md | Phase B |
| FPU CP1 (可选) | ✓ | ~ | ✓ | ✓ | ~ | ✓ | ✓ | CPU-DV | 待写 fpu_spec.md | Phase B (opt) |
| LL/SC 原子 | ~ | ~ | ✓ | ✓ | ✓ | | | CPU-DV | `cp0_spec.md` §1 LLAddr | Phase B (opt) |

### 1.2 缓存与总线

| 特性 | 块 UVM | SoC UVM | Firmware | SVA | Formal | Compliance | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|---|---|
| L1 I-Cache 4-way + CACHE | ✓ | ✓ | ✓ | ✓ | ~ | | Cache-DV | 待写 icache_spec.md | Phase C |
| L1 D-Cache 4-way + WB/WA | ✓ | ✓ | ✓ | ✓ | ~ | | Cache-DV | 待写 dcache_spec.md | Phase C |
| L2 统一 8-way 非阻塞 | ✓ | ✓ | ✓ | ✓ | ✓ | | Cache-DV | 待写 l2_spec.md | Phase C |
| AXI 多 outstanding + 乱序 | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | Bus-DV | 待更新 axi_spec.md | Phase C |
| AXI QoS/PROT/CACHE 语义 | ~ | ✓ | | ✓ | | ✓ | Bus-DV | 同上 | Phase C |
| Crossbar 仲裁 (multi-M/S) | ✓ | ✓ | ~ | ✓ | ✓ | | Bus-DV | 待写 fabric_spec.md | Phase C |
| Cache 一致性接口 (预留) | ~ | | | ~ | ✓ | | Cache-DV | 待写 | Phase C 预留 |

### 1.3 外设

| 外设 | 块 UVM | SoC UVM | Firmware | SVA | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|---|---|---|
| UART 16550 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| QSPI Flash Ctrl | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| DDR3 Ctrl | ✓ | ✓ | ✓ | ✓ | Mem-DV | 待写 | Phase D |
| SD/eMMC | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| GMAC 千兆 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| USB 2.0 (采购 IP) | 供应商 | ✓ | ✓ | ✓ | IP-Integ | vendor | Phase D |
| I2C/SPI 主从 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| 高级 Timer/WDT/PWM | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| VIC 中断控制器 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| GPIO 边沿中断 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| DMA scatter-gather 多通道 | ✓ | ✓ | ✓ | ✓ | Perf-DV | 待写 | Phase D |
| eFuse/OTP | ✓ | ✓ | ~ | ✓ | Sec-DV | 待写 | Phase D |
| JTAG TAP + Debug Master | ~ | ✓ | | ✓ | Dbg-DV | 现有 | Phase A |

### 1.4 时钟 / 复位 / CDC

| 特性 | 块 UVM | SoC UVM | SVA | Formal | CDC | RDC | 责任 | Spec | 状态 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|---|---|---|
| 多时钟域架构 | | ✓ | ✓ | | ✓ | | Infra | 待写 clock_spec.md | Phase E |
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

**Exclusion 政策**：object-level 精化；6 类允许（`.agent/spec.md` 定义）；每条 exclusion 需 spec 引用 + evidence，manifest 审计。

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

## 5. 待补 spec 清单（Phase B-E 起动前必须完成）

优先级从高到低：

1. `docs/block_specs/cp0_spec.md` ✓ 已完成 v0
2. `docs/block_specs/mmu_tlb_spec.md` ✓ 已完成 v0
3. `docs/block_specs/bpu_spec.md`
4. `docs/block_specs/mdu_spec.md`
5. `docs/block_specs/fpu_spec.md` (可选)
6. `docs/block_specs/icache_spec.md` / `dcache_spec.md` / `l2_spec.md`
7. `docs/block_specs/axi_fabric_spec.md`（多 outstanding + QoS）
8. `docs/block_specs/vic_spec.md`
9. `docs/block_specs/uart_16550_spec.md` / `qspi_spec.md` / `ddr3_spec.md` / ...
10. `docs/block_specs/clock_reset_spec.md`
11. `docs/frontend_signoff_checklist.md`

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

`.agents/` 或 `scripts/env/` 增加对应工具模块加载脚本（沿用 EDA loader 约定）。

---

## 版本记录

- v0 (2026-07-26)：初版战略级 vPlan。列出全特性 × 全方法矩阵、覆盖率契约、phase gate、待补 spec 清单。
