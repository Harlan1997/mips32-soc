# 前端签核清单 (v0)

> 状态：v0 草案。逐 phase 展开 `docs/vplan.md` §3 phase gate 为**可勾选清单**。每 phase 结束时由验证 lead + 架构师逐条 sign-off；未打勾项进入 blocker list，不允许过 gate。
>
> 与 `docs/signoff_criteria.md`（当前"current-contract"签核，只覆盖既有 RTL 契约）互补：本文件是**面向 AP 级前端交付**的完整签核契约。

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

### B.1 静态寄存器扩展
- [ ] CP0 PRId 只读寄存器实现 (硬编码 vendor/PID/rev)
- [ ] CP0 EBase 可写基址 + CPUNum 只读
- [ ] CP0 Config / Config1 / Config2 / Config3 实现（值反映真实几何）
- [ ] CP0 HWREna 实现（RDHWR $0/$2 至少）
- [ ] CP0 内 `$display` 语句迁至 `SIMULATION` 围栏
- [ ] 现有 firmware regression 全绿（不引入回归）

### B.2 定时器与中断
- [ ] CP0 Count 自由计数 + Compare 相等触发
- [ ] Cause.TI / Cause.IV / IntCtl.IPTI 联动 Timer
- [ ] IntCtl.VS 向量间距实现（VS=0 非向量化默认可）
- [ ] 8 位 IM × 8 位 IP 中断裁决正确
- [ ] Timer/UART/DMA/PIC 中断 firmware 场景全绿

### B.3 MMU / TLB
- [ ] 64-entry 主 TLB + 4/8-entry micro-TLB 分离 (I / D)
- [ ] 7 种页尺度 (4KB / 16KB / 64KB / 256KB / 1MB / 4MB / 16MB) 全覆盖
- [ ] TLBR / TLBWI / TLBWR / TLBP 指令语义正确
- [ ] Refill / Invalid / Modified 三类异常路径 SVA 通过
- [ ] Machine Check (multi-hit) 检测断言
- [ ] ASID 8-bit 隔离测试通过
- [ ] Wired / Random 语义验证
- [ ] kseg0 / kseg1 直通、useg / kseg2 / kseg3 走 TLB 分派正确
- [ ] `SOC_MMU_ENABLE=0` 兼容模式：现有 firmware regression 全绿
- [ ] `SOC_MMU_ENABLE=1`：Linux 早期 head.S 触发 paging on 后可继续执行

### B.4 用户 / 内核态
- [ ] Status.KSU=00/10 切换正确
- [ ] User 模式访问 kseg0/1/2/3 → AdEL/AdES
- [ ] User 模式访问 CP0 → Coprocessor Unusable 异常
- [ ] Status.CU0 使能允许 User 模式访问 CP0

### B.5 精确异常
- [ ] 所有 ExcCode（Int/Mod/TLBL/TLBS/AdEL/AdES/IBE/DBE/Sys/Bp/RI/CpU/Ov/Tr/MCheck）单元测试
- [ ] EPC 记录正确（含 BD 位 = 1 时保存分支 PC）
- [ ] ERET 正确恢复 (EPC or ErrorEPC 依 ERL/EXL)
- [ ] BEV=1 时向量走 0xBFC0_0180/0x0200；BEV=0 走 EBase
- [ ] Formal proof：异常优先级正确

### B.6 分支预测
- [ ] BTB 256 entry + BHT 256 entry(2-bit) + RAS 8 深度
- [ ] CoreMark 分支命中率 ≥ 88%
- [ ] Dhrystone 分支命中率 ≥ 90%
- [ ] 误预测 1-bubble 冲刷正确
- [ ] `SOC_BPU_ENABLE=0` 兼容模式 (静态不跳)

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
| B.1 – B.9 | ⬜ pending | | | 等 Phase B 启动 |

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
