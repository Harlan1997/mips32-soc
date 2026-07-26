# 前端签核清单 (v0)

> 状态：v0 草案。逐 phase 展开 `docs/vplan.md` §3 phase gate 为**可勾选清单**。每 phase 结束时由验证 lead + 架构师逐条 sign-off；未打勾项进入 blocker list，不允许过 gate。
>
> 与 `docs/signoff_criteria.md`（当前"current-contract"签核，只覆盖既有 RTL 契约）互补：本文件是**面向 AP 级前端交付**的完整签核契约。

---

## Session 2026-07-26 进度速览

Phase B **CPU 内核商用化** 主体交付完成（core-done 或 partial），共 15 个 commit（`cedcd5f` – `8429467`）已推送至 origin/master。子系统在 `SOC_MMU_ENABLE=0`, `SOC_BPU_ENABLE=0` 默认下与前一 baseline 保持 bit-identical，或行为按规格改进（RI/ERET 计数下降）。

| Phase | 交付 | commits | unit tb |
|---|---|---|---|
| A 部分 | 仓库清理 + 前端文档基线（编码规范 / vPlan / 签核清单 / 13 块级 spec） | cedcd5f, edfa5c1, 91a3dab, c2f7c9e | — |
| B.1 | CP0 静态寄存器 (PRId/EBase/Config 0-3/HWREna/IntCtl/ErrorEPC) + sub-select | a9306ea | ✔ (cp0) |
| B.2 | CP0 Timer (Count/Compare/TI/DC/IPTI) | 8739eb8 | ✔ (cp0) |
| B.3.a | CP0 MMU 寄存器（Index/Random/Wired/EntryHi/EntryLo0/1/PageMask/Context/BadVAddr）| 0f6c7bd | ✔ (cp0) |
| B.3.b | TLB 数据阵列 (64-entry FA) + TLBR/TLBWI/TLBWR/TLBP | 4160ea1 | ✔ (cp0) |
| B.3.c | MMU 翻译模块 + TLB 双 lookup 端口 (identity 默认) | 0b63cb1 | ✔ (mmu) |
| B.3.d | MMU fault → 异常路径 + BadVAddr / Context.BadVPN2 硬件更新 | 43303b7 | ✔ (cp0) |
| B.4 | 用户/内核态 (KSU + CU0 + user-kseg AdEL/AdES + CpU 异常) | 11e3a9d | ✔ (cp0) |
| B.5 | 精确异常 (BD-in-pipeline + ErrorEPC/ERL 语义) | d3e0fd5 | ✔ (cp0) |
| B.6 | BPU (BTB/BHT/RAS, observer 模式) | b1183a4 | ✔ (bpu) |
| B ISA R2 | CLZ/CLO/SEB/SEH | 99c8bee | ✔ (alu) |
| B ISA R2 v2 | MOVN/MOVZ/WSBH/ROTR/ROTRV | 8429467 | ✔ (alu) |
| C.1 (rev) | tb mailbox 观察绑定改看 VA (mem_vaddr) — 未来 MMU 上线前置 | 15c50ed | — |

累计 unit tb 覆盖 ~130 checks，SoC 冒烟 `REGRESSION_TEST_SUCCESS` 全程保持。

**未完成 / 明确 deferred**：Phase A.1 覆盖率 99% 闭合；Phase B.7 MDU 商用重构；Phase B FPU (可选)；`SOC_MMU_ENABLE=1` 激活（需 Phase C L2 + fabric alias fold）；EBase-driven 异常向量（需 0xBFC00000 boot ROM）；BPU IF 重定向（需 speculative fetch queue）。

---

## 使用方式

- 每条清单格式：`- [ ] 描述  (依据文档 / 命令)`
- 已完成打勾 `[x]`；不适用打 `[N/A]` 且必须注明原因
- 每 phase 单独 Sign-off 记录段：日期 / 签核人 / 备注 / blocker

---

## Phase A — 稳定基础 & 清理 (Gate A)

### A.1 覆盖率 99% 闭合
- [ ] `make current-contract-signoff` 通过；退出码 0
- [ ] UVM 域 SCORE/LINE/COND/TOGGLE/FSM/BRANCH 全部 ≥ 99.00%（调整后）
- [ ] Product 域 6 指标全部 ≥ 99.00%（调整后）
- [ ] 15 功能覆盖组全部 100.00%（`docs/coverage_plan.md`）
- [ ] Exclusion manifest 无宽泛 module/all-metric 条目；全部 object-level + spec-category 证据
- [ ] URG 报告 0 warning / 0 error / 无 covered-object exclusion 尝试

### A.2 仓库清理
- [x] `.gitignore` 覆盖 `fullexclude.*` / `scratch/`
- [x] `tb/coverage/` 生产资产纳入 git 追踪
- [ ] `rtl/` 内无仿真产物 (simv, csrc, *.log) 与 patch_*.py 脚本 —— 移出到 `build/` / `scripts/`
- [ ] `git status --short` 除 build/ 外全干净

### A.3 Lint 基线（延后）
- [N/A] Lint 工具选型 —— 用户暂缓
- 记录：待后续 phase 引入；Phase F 前必须补上

### A.4 文档基线
- [x] `docs/rtl_coding_style.md` v0 通过
- [x] `docs/vplan.md` v0 通过
- [x] `docs/frontend_signoff_checklist.md` v0 建立
- [x] Phase B 前置 spec 全部 v0：cp0 / mmu_tlb / bpu / mdu (+ 可选 fpu)
- [x] Phase C 前置 spec 全部 v0：icache / dcache / l2 / axi_fabric
- [x] Phase D 前置 spec 全部 v0：vic / uart_16550 / qspi / ddr3（其余外设复用行业标准，spec 随实施同步补）
- [x] Phase E 前置 spec：clock_reset

### Gate A Sign-off

| 项 | 状态 | 签核人 | 日期 | 备注 |
|---|---|---|---|---|
| A.1 覆盖率 | ⬜ pending | | | |
| A.2 清理 | ✅ 部分 | Claude | 2026-07-26 | rtl/ 内 patch_*.py 与 simv 待移出 |
| A.3 Lint | ⏸ 延后 | | | 用户暂缓 |
| A.4 文档 | ✅ 全部 | Claude | 2026-07-26 | |

---

## Phase B — CPU 内核商用化 (Gate B)

### B.1 静态寄存器扩展 (commit a9306ea)
- [x] CP0 PRId 只读寄存器实现 (硬编码 vendor/PID/rev)
- [x] CP0 EBase 可写基址 + CPUNum 只读
- [x] CP0 Config / Config1 / Config2 / Config3 实现（值反映真实几何）
- [x] CP0 HWREna 存储 + 写掩码 (RDHWR 指令暂 defer 到 B.4.2)
- [x] CP0 内 `$display` 语句迁至 `SIMULATION` 围栏
- [x] 现有 firmware regression 全绿（不引入回归）
- [x] (bonus) sub-select routing (inst[2:0]) 支持 (regnum, sel) 全 8-bit CP0 地址

### B.2 定时器与中断 (commit 8739eb8)
- [x] CP0 Count 自由计数 + Compare 相等触发
- [x] Cause.TI / Cause.IV / IntCtl.IPTI 联动 Timer
- [ ] IntCtl.VS 向量间距实现（VS=0 非向量化，位存储已具备；向量化路由 defer）
- [x] 8 位 IM × 8 位 IP 中断裁决正确
- [x] Timer/UART/DMA/PIC 中断 firmware 场景全绿（regression preserved）

### B.3 MMU / TLB (commits 0f6c7bd + 4160ea1 + 0b63cb1 + 43303b7)
- [x] 64-entry 主 TLB (fully-assoc, PageMask-aware probe)
- [ ] 4/8-entry micro-TLB 分离 (I / D) — 现用 TLB 双 lookup port 顶替
- [ ] 7 种页尺度 — 目前 4KB assumption；PageMask-aware 变尺度 defer
- [x] TLBR / TLBWI / TLBWR / TLBP 指令语义正确 (35/35 unit tb)
- [x] Refill / Invalid / Modified 异常路径 (ExcCode 1/2/3) 挂到 pipeline
- [ ] Machine Check (multi-hit) 检测断言 — TLB spec 涵盖，实现 defer
- [ ] ASID 8-bit 隔离 firmware 测试 — unit tb 覆盖了 probe 侧
- [x] Wired / Random 语义（Random 硬件递减到 Wired，Wired 写重置 Random）
- [x] kseg0/1 直通决策、useg/kseg2/3 走 TLB 决策（gated by SOC_MMU_ENABLE=0 默认 identity 兼容当前 firmware）
- [x] `SOC_MMU_ENABLE=0` 兼容模式：现有 firmware regression 全绿
- [ ] `SOC_MMU_ENABLE=1` Linux head.S 集成 — 待 Phase C fabric alias fold 完成

### B.4 用户 / 内核态 (commit 11e3a9d)
- [x] Status.KSU=00/10 切换正确 (RTL 支持，unit tb 验证)
- [x] User 模式访问 kseg0/1/2/3 → AdEL/AdES (MMU 硬架构性检查)
- [x] User 模式访问 CP0 → Coprocessor Unusable 异常 (id_cpu_unusable 门)
- [x] Status.CU0 使能允许 User 模式访问 CP0
- [ ] RDHWR $rd, sel 指令 (Count/CPUNum/UserLocal) — B.4.2 defer

### B.5 精确异常 (commit d3e0fd5)
- [x] BD-in-pipeline: 前一 cycle branch/jump → 下一 cycle ID 指令标 delay slot
- [x] Cause.BD 正确设置; EPC = PC-4 (延迟槽异常)
- [x] Status.ERL 可写; ERET 按 ERL 优先级清 ERL 或 EXL
- [x] intr_req 加 !ERL 条件
- [x] epc_out 按 ERL 选 ErrorEPC / EPC
- [ ] EBase-driven 异常向量 — 保持 literal 0x00000180 直到 boot ROM 就绪
- [ ] BEV=1 时向量走 0xBFC0_0180/0x0200 — 同上
- [ ] Formal proof: 异常优先级正确 — 待 Phase F formal 设施

### B.6 分支预测 (commit b1183a4)
- [x] BTB 256 + BHT 256 (2-bit sat) + RAS 8 存储与预测逻辑 (12/12 unit tb)
- [x] `SOC_BPU_ENABLE=0` 兼容模式 (预测输出不消费)
- [ ] IF next_pc 从 BPU 重定向 — 需 speculative fetch queue，独立架构决策
- [ ] CoreMark / Dhrystone 分支命中率 ≥ 88%/90% — 需 CoreMark 集成
- [ ] 误预测 1-bubble 冲刷 — 待 IF 重定向

### B.7 MDU 多周期
- [ ] Booth radix-4 乘法 5-cycle
- [ ] Radix-2 除法 18-cycle，早退出到 3 cycle
- [ ] MADD/MADDU/MSUB/MSUBU + CLO/CLZ 实现
- [ ] MFHI/MFLO stall 遇 busy MDU
- [ ] Flush-to-IDLE 语义（异常/mispredict 时）
- [ ] MDU stall 占正常 workload < 5% cycles

### B.8 FPU CP1（可选）
- [N/A] 决策：Phase B 是否含 FPU
- 若含：IEEE 754 单精度加减乘除/sqrt/比较/转换全通过 SoftFloat compliance

### B.9 综合验证
- [ ] MIPS32 R2 ISA compliance test suite 100%
- [ ] ISA-Ref 联合仿真 (QEMU-MIPS 或 Sail-MIPS) ≥ 1e9 retired instructions 无 mismatch
- [ ] CoreMark 基线跑通 + CPI 建档
- [ ] Dhrystone 基线跑通
- [ ] SVA 断言库 (bind checker) 全 assert 通过 + 关键 property 100% cover
- [ ] Formal proof 记录：TLB FSM / 异常优先级 / BPU FSM (proven or bounded)

### Gate B Sign-off

| 项 | 状态 | 签核人 | 日期 | 备注 |
|---|---|---|---|---|
| B.1 静态寄存器 | ✅ core done | Claude | 2026-07-26 | 存储/写掩码/读回全套；RDHWR defer B.4.2 |
| B.2 Timer      | ✅ core done | Claude | 2026-07-26 | Count/Compare/TI/DC/IPTI 全落地；VS 向量化 defer |
| B.3 MMU/TLB    | ⚠ partial   | Claude | 2026-07-26 | Register+array+lookup+fault path 全套；micro-TLB / PageMask 变尺度 / Linux boot defer |
| B.4 用户态     | ✅ core done | Claude | 2026-07-26 | KSU/CU0/kseg 保护/CpU 全套；RDHWR defer |
| B.5 精确异常   | ⚠ partial   | Claude | 2026-07-26 | BD-in-pipeline + ErrorEPC/ERL 落地；EBase-vector defer |
| B.6 BPU        | ⚠ partial   | Claude | 2026-07-26 | BTB/BHT/RAS 全套；IF 重定向待 speculative fetch |
| B.7 MDU 多周期 | ⬜ pending   |        |            | 现有 MDU 是简单实现；商用重构未开始 |
| B.8 FPU CP1    | ⏸ deferred  |        |            | 决策：Phase B 不含 FPU |
| B.9 综合验证   | ⬜ pending   |        |            | 依赖 Phase F formal 与 CoreMark/Dhrystone/ISA compliance 基础设施 |

---

## Phase C — 缓存与总线 (Gate C)

### C.1 L1 升级
- [ ] I-cache 8KB 4-way VIPT non-aliasing + pseudo-LRU
- [ ] D-cache 8KB 4-way VIPT + WB/WA + 2 MSHR + 4 store buffer
- [ ] CACHE 指令子集（I: Index/Hit Invalidate; D: 6 op）
- [ ] Uncached bypass 正确
- [ ] AXI 8-beat burst 正确

### C.2 L2 新增
- [ ] 128 KB 8-way NINE + 8 MSHR + 4 WB buffer
- [ ] Snoop 端口 tie-off 且无副作用
- [ ] L1→L2→DDR 三级 miss 端到端通
- [ ] CoreMark L2 hit rate ≥ 80% (L1 miss 的 80% 命中 L2)

### C.3 多 outstanding AXI Fabric
- [ ] Crossbar M×N 全连接
- [ ] Per-master 至少 4 outstanding
- [ ] 乱序响应 + ID tag 正确 route
- [ ] QoS 4-bit 仲裁生效
- [ ] Round-robin 公平性长期无饥饿
- [ ] 内置 DECERR slave 未映射地址响应
- [ ] AXI Compliance (VIP or 自建) 通过
- [ ] Formal：arbitration liveness / deadlock freedom / ID 保序 proven

### Gate C Sign-off

⬜ pending

---

## Phase D — 外设商用化 (Gate D)

### D.1 UART 16550
- [ ] 波特率 115200 @ 48MHz APB clock 精度 ≤ 3%
- [ ] 帧格式全组合 (5-8 位 × 1/1.5/2 stop × 5 种 parity)
- [ ] FIFO 64 深度 + 阈值中断
- [ ] Loopback 模式回环
- [ ] Linux 8250 driver 挂载 + printk 输出

### D.2 QSPI Flash
- [ ] 8-LUT 各阶段 lane 切换 (x1/x2/x4)
- [ ] XIP 单/多 beat + continuous mode
- [ ] Erase / Program / Read status 命令 API
- [ ] 4 CS 多片切换
- [ ] Linux MTD driver 挂载

### D.3 DDR3
- [ ] Init 序列符合 JEDEC
- [ ] Timing (tRCD/tRP/tRAS/tFAW/tRRD/tWTR/tRTP) SVA 通过
- [ ] Auto-refresh tREFI 遵守
- [ ] U-Boot memtest 全 DDR 空间通
- [ ] STREAM 带宽 ≥ 60% 峰值
- [ ] Linux 引导 kernel 加载到 DDR

### D.4 VIC
- [ ] 32 源 × 4-bit 优先级 + 嵌套 + 软触发
- [ ] Formal：优先级编码器 max 正确性 proven

### D.5 其他外设（SD/eMMC, GMAC, USB, I2C/SPI, WDT/PWM, DMA, GPIO, eFuse）
- 每外设完成时逐条添加子清单，本 v0 不展开

### Gate D Sign-off

⬜ pending

---

## Phase E — 时钟 / 复位 / CDC / 电源意图 (Gate E)

### E.1 多时钟域
- [ ] 8 时钟域独立时钟树声明
- [ ] PLL wrapper + lock 检测 + bypass 模式
- [ ] ICG cell wrapper (latch-based)

### E.2 复位架构
- [ ] AASD (async assert / sync deassert) 统一实现
- [ ] 每域独立复位同步器 (STAGES ≥ 3)
- [ ] POR / 软复位 / WDT / JTAG / PLL-lost-lock 聚合正确
- [ ] 复位顺序 FSM 正确 (PLL lock → CPU → DDR → APB → 外设)

### E.3 CDC 单元库
- [ ] sync_2ff / pulse_sync / handshake_sync / async_fifo / mux_sync 五类实现
- [ ] CDC 静态验证工具 0 违规
- [ ] 100% CDC 路径被工具识别为已同步
- [ ] `docs/cdc_waivers.md` 建立（可空但存在）

### E.4 RDC
- [ ] RDC 静态验证 0 违规

### E.5 UPF 声明层
- [ ] `upf/soc.upf` 声明 PD_AON / PD_CPU / PD_L2 / PD_DDR / PD_PERI
- [ ] RTL 侧跨域信号命名规范 (`<dst_pd>_from_<src_pd>_<name>`)
- [ ] 每电源域边界处 register 输出，供后端插入 iso cell
- [ ] Always-on 逻辑（VIC/RTC/PMU/WDT）位于 PD_AON

### Gate E Sign-off

⬜ pending

---

## Phase F — 验证扩展与前端签核 (Gate F — 前端最终签核)

### F.1 SVA 断言库
- [ ] AXI / APB / cache FSM / TLB / interrupt / CDC 全类别 bind checker
- [ ] 关键 property 100% assert 通过 + 100% cover 命中
- [ ] SVA 断言覆盖率纳入 gate 门槛

### F.2 Formal Verification
- [ ] Fabric arbitration liveness + deadlock freedom proven
- [ ] Cache 控制 FSM proven or bounded ≥ 32 cycles
- [ ] TLB FSM proven
- [ ] 中断优先级 / VIC 编码器 proven
- [ ] 每个 formal proof 报告状态记录（proven / bounded / cex）

### F.3 静态验证收敛
- [ ] Lint 0 violation (waiver 有据)
- [ ] CDC 0 violation
- [ ] RDC 0 violation

### F.4 ISA 参考模型联合仿真
- [ ] QEMU-MIPS 或 Sail-MIPS harness 集成到回归
- [ ] > 1e9 retired instructions 累计无 mismatch
- [ ] 每次 major RTL 变更后重跑至少 1e8 instructions

### F.5 MIPS ISA Compliance Suite
- [ ] 100% test cases 通过（含 privileged）

### F.6 Linux Boot 回归
- [ ] U-Boot 从 QSPI Flash boot 到 shell 提示符
- [ ] Linux kernel 从 U-Boot 加载并 boot 到 busybox shell prompt
- [ ] 100 次连续 boot 无 hang / 无 kernel panic
- [ ] 纳入夜间回归

### F.7 性能基准
- [ ] CoreMark 达标（AP-lite 目标：≥ 1.6 CoreMark/MHz）
- [ ] Dhrystone 达标（≥ 1.5 DMIPS/MHz）
- [ ] STREAM 带宽建档
- [ ] memcpy 带宽建档

### F.8 Fault Injection
- [ ] AXI SLVERR / DECERR 传播恢复
- [ ] WDT reset 场景
- [ ] ECC 错误注入（若 DDR ECC 启用）
- [ ] 复位场景全组合

### F.9 覆盖率最终
- [ ] 代码覆盖率 ≥ 99% (LINE/COND/TOGGLE/FSM/BRANCH)
- [ ] 功能覆盖率 100% (含新增 Phase B-E 覆盖组)
- [ ] SVA 断言覆盖率 100% cover on critical properties

### F.10 文档最终
- [ ] 所有 block spec v1+（每模块变更完成后更新）
- [ ] `docs/rtl_coding_style.md` v1+
- [ ] `docs/vplan.md` 反映实际覆盖
- [ ] `docs/frontend_signoff_release.md` 记录版本 / SHA / 报告链接
- [ ] 交付后端团队的 handoff 包（RTL 版本冻结 + 约束假设 + 未决问题清单）

### Gate F Sign-off — 前端交付后端

⬜ pending

**签核人**：CPU-DV lead / Cache-DV lead / Bus-DV lead / Perf-DV lead / Infra lead / Integ lead / 架构师 / 项目 PM

---

## 附录 A：跨 Phase 通用要求

- 每次 RTL 变更 → 相应 SVA / UVM 更新 → 回归
- 每次 spec 变更 → 版本记录段更新
- Phase gate 失败允许回滚到上一 gate 状态并重跑
- 所有工具版本 (VCS / URG / formal / CDC) 在 sign-off 报告中登记

---

## 版本记录

- v0 (2026-07-26)：初版清单，覆盖 Phase A – F 全部 gate。Phase A 部分已 sign-off；Phase B-F 待启动。
