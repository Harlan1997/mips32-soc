# MIPS32 R2 Coprocessor 0 (CP0) 完整寄存器规格 (v0.1)

> 状态：v0.1 草案。作为 Phase B **`rtl/cpu/mips_cp0.v` 重写基线**。所有位段、复位值、访问规则以本文件为准，实现偏差需回填此规格并评审。
>
> 引用：MIPS® Architecture For Programmers Volume III: Privileged Resource Architecture, Revision 6.06。本项目当前不实现的字段用 "**RES**"（Reserved）或 "**tie**" 标注。

---

## 0. 范围与不做的事

**Phase B 目标**：完整实现 MIPS32 R2 Privileged 架构中一个 AP 级 (24Kc/34Kc 竞品) 芯片跑 Linux 所必需的 CP0 子集。

**做**：Status/Cause/EPC/PRId/EBase/Config[0-3]/Count/Compare/BadVAddr/Context/Wired/Random/Index/EntryHi/EntryLo0/1/PageMask/HWREna，共 20 个寄存器。

**不做**（本 phase）：
- Debug (`Debug` reg 23) / DEPC / DESAVE — EJTAG 深度调试，Phase 后期或独立评估
- Performance Counter (`PerfCnt` 25) — 性能计数器，Phase F 引入
- Watch (`WatchLo/Hi` 18/19) — 数据/取指 watchpoint，与 EJTAG 一起
- FPU 相关 CP0 状态镜像 — 与 CP1 一起在 FPU 子任务中实现
- MT ASE / MIPS DSP ASE — 不在 AP-lite 范围
- SmartMIPS / 加密 ASE — 独立评估

保留字段 (RES) 复位读全 0；写忽略。软件不得依赖读回值。

---

## 1. 寄存器总览

MIPS32 CP0 通过 `(regnum[4:0], sel[2:0])` 8 位地址访问，共 256 槽。本 phase 实现如下：

| regnum | sel | 名称 | 缩写 | 复位值 | 说明 |
|:-:|:-:|---|---|---|---|
| 0  | 0 | Index         | INDEX    | 32'h0000_0000 | TLBWI/TLBR 索引；P bit 表 TLBP 未命中 |
| 1  | 0 | Random        | RANDOM   | `TLB_ENTRIES-1` | 硬件递减的自由 TLB 索引 |
| 2  | 0 | EntryLo0      | ENTRYLO0 | 32'h0000_0000 | TLB 偶数页 PFN + 属性 |
| 3  | 0 | EntryLo1      | ENTRYLO1 | 32'h0000_0000 | TLB 奇数页 PFN + 属性 |
| 4  | 0 | Context       | CONTEXT  | 32'hxxxx_xxxx | PTEBase + BadVPN2 (fast refill) |
| 4  | 2 | UserLocal     | USERLOCAL| 32'h0000_0000 | 软件管理线程本地存储指针；kernel context-switch ABI |
| 5  | 0 | PageMask      | PAGEMASK | 32'h0000_0000 | 页尺度掩码 (4KB..16MB) |
| 6  | 0 | Wired         | WIRED    | 32'h0000_0000 | Random 下限 (锁定入口数) |
| 7  | 0 | HWREna        | HWRENA   | 32'h0000_0000 | RDHWR 用户可见寄存器使能（含 SYNCI_Step/UserLocal） |
| 8  | 0 | BadVAddr      | BADVADDR | 32'hxxxx_xxxx | 最近一次 addr 异常的虚拟地址 |
| 9  | 0 | Count         | COUNT    | 32'h0000_0000 | 自由运行计数器（每 2 cycles +1 可参数化） |
| 10 | 0 | EntryHi       | ENTRYHI  | 32'h0000_0000 | VPN2 + ASID |
| 11 | 0 | Compare       | COMPARE  | 32'h0000_0000 | 定时器比较器（与 Count 相等触发 IP[7]） |
| 12 | 0 | Status        | STATUS   | 见 §3 | 全局中断使能、异常级、KSU 模式、CU 位等 |
| 12 | 1 | IntCtl        | INTCTL   | 见 §3.4 | 向量间距 / VS |
| 12 | 2 | SRSCtl        | SRSCTL   | 32'h0000_0000 | 默认 SS=0；`SOC_SRS_ENABLE=1` 时支持软件选择的 CSS/PSS/ESS 字段子集 |
| 12 | 3 | SRSMap        | SRSMAP   | 32'h0000_0000 | `SOC_SRS_ENABLE=1` 时 8 个 Cause.IP[7:0] 到 shadow-set 的 4-bit 映射 |
| 13 | 0 | Cause         | CAUSE    | 32'h0000_0000 | 异常/中断原因 |
| 14 | 0 | EPC           | EPC      | 32'hxxxx_xxxx | 异常返回地址 |
| 15 | 0 | PRId          | PRID     | 见 §11 | 制造商/型号/版本，硬编码 |
| 15 | 1 | EBase         | EBASE    | 32'h8000_0000 | 异常向量基址（4KB 对齐）+ CPUNum |
| 16 | 0 | Config        | CFG0     | 见 §12 | 架构基础配置 |
| 16 | 1 | Config1       | CFG1     | 见 §12 | TLB/Cache/协处理器指示 |
| 16 | 2 | Config2       | CFG2     | 32'h8000_0000 | L2/L3 cache（此 phase 全 tie 0，M 位 → Config3） |
| 16 | 3 | Config3       | CFG3     | 见 §12 | R2 特性位 |
| 17 | 0 | LLAddr        | LLADDR   | 32'h0000_0000 | 只读映射 CPU 单核 LL/SC reservation 对齐地址；MFC0 可读，MTC0 不改变 reservation；多核一致性仍不在当前契约 |
| 30 | 0 | ErrorEPC      | ERR_EPC  | 32'hxxxx_xxxx | 错误异常返回地址（Reset/NMI/CacheErr） |

**Sel != 已列** 值：读返回 0，写忽略。

---

## 2. 访问规则

- **指令**：`MFC0 rt, rd, sel`（读）；`MTC0 rt, rd, sel`（写）。
- **特权**：只在**内核态** (`Status.KSU=00` 或 `Status.EXL=1` 或 `Status.ERL=1`) 或 `Status.CU0=1` 时可访问；否则 Coprocessor Unusable 异常 (CpU=0)。
- **CP0 hazard**：`MTC0` 到 `Status/EPC/Cause/EBase/PageMask/EntryHi/EntryLo0/1/Wired/Compare` 之后到指令级依赖之间需 `EHB`（或 `SSNOP`×N）保证前作用可见。Phase B 实现 `EHB`（`SLL r0,r0,3`）为流水线冲刷点。

### Shadow register set instructions

`RDPGPR` (`COP0 rs=0x0a`) and `WRPGPR` (`COP0 rs=0x0e`) are Reserved
Instruction when `SOC_SRS_ENABLE=0`. With `SOC_SRS_ENABLE=1`, the RTL has
sixteen 32-register banks, software-selected `SRSCtl.PSS/CSS` access, and
the `RDPGPR`/`WRPGPR` data path. Exception entry saves `CSS` in `PSS` and
loads the software-selected `ESS` set; `ERET` restores `CSS` from `PSS`.
The verified contract is deliberately bounded: SRSMap IP-to-shadow-set
selection is covered for the opt-in IP-based interrupt path, and an EXL-held
nested synchronous exception preserves CSS/PSS/EPC state. External VEIC/EICSS
selection and scheduler/Linux SRS context ABI ownership remain outside this
slice.

---

## 3. Status (12,0)

复位值 `32'h00400004`（BEV=1、ERL=1；表示复位后从 `0xBFC0_0180` bootstrap 向量取指且不接受中断，与 MIPS spec 一致）。

| bit | 名 | RW | 说明 |
|:-:|---|:-:|---|
| 31 | CU3 | RW | CP3 使能（Phase B tie 0）|
| 30 | CU2 | RW | CP2 使能（Phase B tie 0，为未来加速器预留）|
| 29 | CU1 | RW | CP1/FPU 使能。无 FPU 时写忽略，读回 0 |
| 28 | CU0 | RW | CP0 用户态使能 |
| 27 | RP  | RW | Reduced Power (软件 hint，不改硬件行为)|
| 26 | FR  | RW | 64-bit FP register file (无 FPU 时 tie 0) |
| 25 | RE  | RW | Reverse Endian in user mode (tie 0：不支持) |
| 24 | MX  | RES | MDMX ASE (tie 0) |
| 23 | PX  | RES | 64-bit ops in 32-bit mode (tie 0) |
| 22 | BEV | RW | Bootstrap Exception Vector：1 → `0xBFC0_0200`；0 → EBase |
| 21 | TS  | RO | TLB Shutdown（重复 TLB 命中检测）— 硬件置位后必须复位才能清 |
| 20 | SR  | RW | Soft Reset 完成置位 (可选) |
| 19 | NMI | RO | 最近一次异常是 NMI |
| 18 | 0   | RES | |
| 17:16 | Impl | RES | 实现相关 (tie 0) |
| 15:8 | IM7:IM0 | RW | 8 位中断掩码（IM7 与 Compare 联动）|
| 7:5 | 0 | RES | |
| 4:3 | KSU | RW | 00=Kernel 01=Supervisor 10=User 11=RES。本 phase 只实现 Kernel/User (00/10)，Supervisor tie 到 Kernel |
| 2  | ERL | RW | Error Level（Reset/NMI/CacheErr 置位）|
| 1  | EXL | RW | Exception Level（一般异常置位）|
| 0  | IE  | RW | 全局中断使能 |

**中断裁决**：`IE && !EXL && !ERL && ((Cause.IP & Status.IM) != 0)` 时接受中断。

**模式**：有效模式 = ERL||EXL||KSU==0 ? Kernel : KSU==2 ? User : Kernel。

---

### 3.4 IntCtl (12,1)

| bit | 名 | 说明 |
|:-:|---|---|
| 31:29 | IPTI | Timer 中断挂到 IP 号（默认 111 = IP7）|
| 28:26 | IPPCI | PerfCounter 中断挂到 IP 号（Phase B tie 000）|
| 25:10 | 0 | RES |
| 9:5 | VS | 向量间距，5-bit×32B。0 → 非向量化，跳 EBase+0x180 |
| 4:0 | 0 | RES |

Phase B 默认 IPTI=7、VS=0 (非向量化)。VS>0 时中断向量 = EBase + 0x200 + (VN × VS × 32)。

---

## 4. Cause (13,0)

| bit | 名 | RW | 说明 |
|:-:|---|:-:|---|
| 31 | BD | RO | 上次异常发生在延迟槽 |
| 30 | TI | RO | Timer Interrupt (Count==Compare) |
| 29:28 | CE | RO | 触发 CpU 异常的协处理器号 |
| 27 | DC | RW | 禁用 Count 计数（省电）|
| 26 | PCI | RO | PerfCounter 中断挂起（Phase B tie 0）|
| 25:24 | 0 | RES | |
| 23 | IV | RW | 使用向量中断 (跳 EBase+0x200 而非 0x180) |
| 22 | WP | RW | Watch 挂起（Phase B tie 0）|
| 21:16 | 0 | RES | |
| 15:10 | IP7:IP2 | RO | 硬件中断挂起（IP7 = Timer 或 Perf；IP6:IP2 = 外设）|
| 9:8 | IP1:IP0 | RW | 软件中断挂起（软件写 1 触发）|
| 7 | 0 | RES | |
| 6:2 | ExcCode | RO | 异常码，见 §5 |
| 1:0 | 0 | RES | |

---

## 5. ExcCode 编码（Cause[6:2]）

| 值 | 助记 | 说明 |
|:-:|---|---|
| 0  | Int  | 中断 |
| 1  | Mod  | TLB modification (写只读页) |
| 2  | TLBL | TLB load / instruction fetch miss (Invalid 或 refill) |
| 3  | TLBS | TLB store miss |
| 4  | AdEL | Address error load / fetch |
| 5  | AdES | Address error store |
| 6  | IBE  | Instruction bus error |
| 7  | DBE  | Data bus error |
| 30 | CacheErr | Cached instruction/data refill or writeback error |
| 8  | Sys  | SYSCALL |
| 9  | Bp   | BREAK |
| 10 | RI   | Reserved instruction |
| 11 | CpU  | Coprocessor unusable |
| 12 | Ov   | Arithmetic overflow (ADD/SUB/ADDI 有符号溢出) |
| 13 | Tr   | Trap (TEQ/TNE 等) |
| 15 | FPE  | FP exception (无 FPU 不产生) |
| 23 | WATCH | Watch (Phase B tie 不产生) |
| 24 | MCheck | Machine check（TLB 重复命中）|

其余值 RES。

---

## 6. EPC (14,0)

- 异常发生时保存导致异常的指令 PC；若指令在延迟槽 (`Cause.BD=1`)，保存**分支指令**的 PC。
- `EXL=1` 或 `ERL=1` 时**硬件不更新** EPC —— 允许软件读写调试。
- ERET 用 EPC 返回（跳过 EPC，直接置 PC=EPC）。

## 7. ErrorEPC (30,0)

同 EPC，但用于 Reset/NMI/CacheError 异常 (`ERL=1` 时使用)。`ERL=1` 时不更新。ERET when ERL=1 用此。

CacheErr (`Cause.ExcCode=30`) 由 I/D-cache 的 dedicated cache-error
sideband 触发。CPU 使用 CacheErr vector：`BFC0_0100` when `BEV=1`，或
`EBase+0x100` when `BEV=0`；CP0 置 `Status.ERL=1`、写入 `ErrorEPC`，不置
`EXL`。uncached AXI response error 仍为 DBE/IBE 的普通 EPC 路径。

---

## 8. TLB 相关寄存器（§9 MMU/TLB spec 详述）

### Index (0,0)
| 31 | 30:log2(N) | log2(N)-1:0 |
|:-:|:-:|:-:|
| P (probe fail) | RES | Index[log2(TLB_ENTRIES)-1:0] |

### Random (1,0)
- 硬件计数器，从 `TLB_ENTRIES-1` 递减到 `Wired`，然后循环回 `TLB_ENTRIES-1`。
- 只读。用于 TLBWR 随机替换。

### Wired (6,0)
- 软件写下限，Random 不会低于此值。可用来锁定关键条目。
- 写 Wired 会重置 Random = TLB_ENTRIES-1。

### EntryHi (10,0)
| 31:13 | 12:8 | 7:0 |
|:-:|:-:|:-:|
| VPN2 (虚拟页号偶数半) | RES | ASID |

TLB miss 时硬件更新 VPN2 + ASID (只更新 ASID 若发生异常时保留)。

### EntryLo0/1 (2,0)/(3,0)
| 31:26 | 25:6 | 5:3 | 2 | 1 | 0 |
|:-:|:-:|:-:|:-:|:-:|:-:|
| RES | PFN (20 位物理页号) | C (Cache attr) | D (Dirty/写允许) | V (Valid) | G (Global) |

- PFN：物理页号 20 位 → 32 位物理地址空间。
- C：cache 属性编码，Phase B 支持 `010=Uncached`, `011=Cacheable Write-back`, 其他 RES/预留。
- D=0 且发生写 → TLB Modified 异常。
- V=0 → TLB Invalid 异常。
- G：偶奇两半均置 G 时忽略 ASID 比较（全局映射）。

### PageMask (5,0)
| 31:29 | 28:13 | 12:0 |
|:-:|:-:|:-:|
| RES | Mask（对应 VPN 上位比较屏蔽）| RES |

支持页尺度：4KB (Mask=0), 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 256MB（Phase B 到 16MB 即可）。

### Context (4,0)
| 31:23 | 22:4 | 3:0 |
|:-:|:-:|:-:|
| PTEBase (软件) | BadVPN2 (硬件填) | RES |

TLB refill 时硬件把 BadVAddr[31:13] → BadVPN2，方便快速 refill 处理程序拼接 PTE 地址。

### BadVAddr (8,0)
- 只读。地址异常（AdEL/AdES）或 TLB 异常 (TLBL/TLBS/Mod) 时保存虚拟地址。

---

## 9. Count / Compare (9,0) / (11,0)

- `Count` 自由递增（`Cause.DC=1` 时暂停），周期 = `parameter COUNT_DIV`（默认 2 cycles per tick，模拟 24Kc 半频计数）。
- `Compare` 由软件写；写 `Compare` 时**清除** `Cause.TI` 并撤销 IP7 挂起。
- 当 `Count == Compare` 时置 `Cause.TI=1`，向 IP7（受 IntCtl.IPTI 配置）注入中断。

---

## 10. EBase (15,1)

| 31:30 | 29:12 | 11:10 | 9:0 |
|:-:|:-:|:-:|:-:|
| 10 (只读) | EBase 基址 (18 位，4KB 对齐) | RES | CPUNum (只读) |

- 复位 EBase = `0x8000_0000` (等价 kseg0，二进制 10_00...)。上 2 位硬件固定 10。
- 只在 `Status.EXL=0` 且 `Status.BEV=0` 时可写。
- `BEV=1` 时 refill/general 向量固定在 `0xBFC0_0200/0xBFC0_0380`，不使用 EBase。

**向量地址表**：
| 情形 | BEV | Cause.IV | 向量 |
|---|:-:|:-:|---|
| TLB refill (32-bit) | 0 | x | EBase + 0x000 |
| TLB refill | 1 | x | 0xBFC0_0200 |
| 通用异常 | 0 | 0 | EBase + 0x180 |
| 通用异常 | 1 | 0 | 0xBFC0_0380 |
| 中断（vectored） | 0 | 1 | EBase + 0x200 + (VN × VS × 32) |
| Reset/NMI | x | x | 0xBFC0_0000 |
| Cache Error | 0 | x | EBase + 0x0000_0100 |
| Cache Error | 1 | x | 0xBFC0_0100 |

**当前实现边界（2026-08-01）**：产品 opt-in 配置已实现 refill、Invalid
和 IP-based vectored interrupt 的分派。CPU 以 TLB lookup 的 `hit=0` 识别
refill；`hit=1,V=0` 保留为通用异常，即使两者 `ExcCode` 同为 TLBL/TLBS。
向量中断使用最高编号的 `Cause.IP & Status.IM` pending 位作为 VN，向量间距
为 `IntCtl.VS * 32`，并只在真实 interrupt 被接受、`BEV=0`、`Cause.IV=1`
时生效；`Config3.VEIC=0`，不宣称外部 VIC vector ID。I-side 的 BEV=1/0
miss/invalid、D-side BEV=1 miss/invalid，以及软件 IP1 的 `EBase+0x220`
SoC directed 证据均已通过。CacheErr sideband、ExcCode=30、ERL/ErrorEPC
和 `EBase+0x100`/`BFC0_0100` hardware vector 另有 CPU directed gate；该结论不覆盖
Modified 的完整策略、production cache-error handler 或可启动的完整 MMU firmware。

---

## 11. PRId (15,0)

Read-only，硬编码。建议格式：

| 31:24 | 23:16 | 15:8 | 7:0 |
|:-:|:-:|:-:|:-:|
| Company Options (0x00) | Company ID (0x01 = MIPS Technologies 或自定义 0x8x) | Processor ID (自定义，例 0x80 表 "MIPS32 R2 AP-lite") | Revision |

Phase B 默认 `32'h0000_8010`（自定义 vendor 0x00、company 0x00、PID 0x80、Rev 0x10）。参数化 `PRID_COMPANY`/`PRID_PROCESSOR`/`PRID_REVISION`。

---

## 12. Config / Config1 / Config2 / Config3

**Config (16,0)**

| 31 | 30:16 | 15 | 14:13 | 12:10 | 9:7 | 6:4 | 3 | 2:0 |
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| M=1 | 0 | BE (endian, 0=LE) | AT (MIPS32=00) | AR (Rev, 0=R1, 1=R2 → 001) | MT (2=TLB) | 0 | VI (I-cache virtual index, 0) | K0 (kseg0 cache attr) |

Phase B: `M=1, AR=001, MT=010, K0=011` → `32'h8004_4283` 之类。K0 软件可写 (0/2/3)。

**Config1 (16,1)**

| 31 | 30:25 | 24:22 | 21:19 | 18:16 | 15:13 | 12:10 | 9:7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| M=1 | MMUSize-1 (TLB_ENTRIES-1) | IS | IL | IA | DS | DL | DA | C2 | MD | PC | WR | CA | EP | FP |

Cache 编码：IS/DS = log2(sets/64)、IL/DL = log2(line/2)+1、IA/DA = ways-1。
- I-cache 8KB 4-way 32B: IS = log2(64/64)=0, IL=log2(32/2)+1=5, IA=3 → `000_101_011`
- D-cache 8KB 4-way 32B: DS=0, DL=5, DA=3
- WR=1 (Watch)、CA=1 (Code compression? 0), MD=0, PC=1 (perf ctr present, Phase F 前 tie 0), FP=0 (Phase B 无 FPU)

**Config2 (16,2)**：L2/L3 cache 报告；Phase B L2 未做，`M=1` (指向 Config3) 其余 0。

**Config3 (16,3)**：R2 特性位。

| bit | 名 | 值 |
|:-:|---|---|
| 31 | M | 0 |
| 13 | ULRI | 1（UserLocal (4,2) 与 RDHWR $29 已实现） |
| 5  | VEIC | 0 (无外部中断控制器接口) |
| 3  | VInt | 1 (支持 vectored interrupts via IntCtl.VS) |
| 2  | SP  | 0 |
| 1  | CDMM | 0 |
| 0  | TL   | 0 |

---

## 13. HWREna (7,0)

| bit | 使能位 | RDHWR 目标 |
|:-:|---|---|
| 0 | CPUNum | 允许用户 RDHWR $0 → EBase.CPUNum |
| 1 | SYNCI_Step | 允许用户 RDHWR $1 → cache line size |
| 2 | CC | 允许用户 RDHWR $2 → Count |
| 3 | CCRes | 允许用户 RDHWR $3 → Count 分辨率 |
| 29 | ULR | 允许用户 RDHWR $29 → UserLocal |

其余 bits RES。复位 0（全部禁用）。

---

## 14. 硬件行为汇总

- **复位 (Reset)**：`Status = {BEV=1, ERL=1}`（其他清 0）；`Random = TLB_ENTRIES-1`；`Wired = 0`；`Config` 按 §12 静态值；PC = `0xBFC0_0000`。
- **异常入口**：硬件动作按序
  1. 若 `EXL=0` 且非 ERL：`EPC = PC (or PC-4 if BD)`, `Cause.BD = 延迟槽标志`
  2. `Status.EXL = 1`
  3. `Cause.ExcCode = 异常码`
  4. PC ← 向量地址（§10 表）
- **ERET**：`if (ERL) { PC = ErrorEPC; ERL = 0; } else { PC = EPC; EXL = 0; } LLbit = 0;`
- **CP0 hazard**：写 CP0 到读取影响需 `EHB` 冲刷（1 个 cycle bubble 起）。

---

## 15. Phase B 实施拆分建议

1. **B.1 — 基础异常路径**：Status (含 KSU/EXL/ERL/BEV)、Cause、EPC、ErrorEPC、EBase、PRId、Config[0-3] 骨架 + 复位模型 + ERET 语义。可先跑通所有当前 firmware regression。
2. **B.2 — 定时器与中断**：Count/Compare、Cause.IP/TI/IV、IntCtl (IPTI/VS)、HWREna（RDHWR $2）。
3. **B.3 — MMU/TLB**：Index/Random/Wired/EntryHi/EntryLo0/1/PageMask/Context/BadVAddr、TLBR/TLBWI/TLBWR/TLBP 指令、refill/invalid/modified 异常路径（详见 `mmu_tlb_spec.md`）。
4. **B.4 — 用户态**：KSU 生效、CU0 检查、User-mode 内存访问受 TLB 保护、Coprocessor Unusable 路径。
5. **B.5 — 可选**：LLAddr + LL/SC 已完成单核 reservation/只读可见性；UserLocal (4,2) 与 RDHWR $29 用户态读取已实现；EJTAG Debug (延后)。

每小步独立回归 + SVA + firmware sanity + 覆盖率增量。

---

## 16. 验证要求

- **每个 CP0 寄存器**：一条覆盖点覆盖所有可写字段读写、复位值、非法写忽略。
- **异常路径**：每个 ExcCode 至少 1 条 firmware 测试触发 + EPC/BD/Cause 断言。
- **中断**：8 条 IM 位独立 + 联合，vectored / non-vectored 双向。
- **TLB**：miss/hit/invalid/modified/multi-hit（machine check）全覆盖。
- **hazard**：MTC0 → 依赖读之间 EHB 缺失场景断言。
- **ISA compliance**：MIPS32 R2 privileged compliance suite 100% 通过。

---

## 版本记录

- v0 (2026-07-26)：初版规格，20 CP0 寄存器完整位段 + 复位 + 异常模型。等待 Phase B 起始时评审。
- v0.1 (2026-08-04)：UserLocal (4,2) MTC0/MFC0 存储契约实现并通过 CP0 directed gate；Config3.ULRI 置位。RDHWR `$29` 与完整 TLS linker/runtime 保持后续范围。
- v0.2 (2026-08-04)：SPECIAL3 `RDHWR rt,$29` 接入 CP0 (4,2) 回写路径，用户态受 `HWREna[29]` gating；RTL frontend 与 CP0 regression 通过，完整 firmware TLS runtime 仍后续验证。
- v0.4 (2026-08-05)：CP0 `(17,0)` LLAddr 接入单核 reservation 地址只读路径；CP0 block gate 覆盖 MFC0 读回。多核 coherency 与软件写入语义保持 deferred。
- v0.5 (2026-08-05)：完成 `RDHWR $1` SYNCI_Step（32-byte line step）解码、HWREna[1] user 权限和 CP0 readback；其余 HWR 目标仍 deferred。
- v0.6 (2026-08-05)：完成 `RDHWR $2` Count 解码、HWREna[2] user 权限和 CP0 Count readback；CPUNum/CCRes 等其余 HWR 目标仍 deferred。
- v0.7 (2026-08-05)：加入 `RDHWR $0` CPUNum（单核返回 0）和 `$3` CCRes（Count resolution=2 cycles）的 CP0 映射与 HWREna 权限路径。
- v0.8 (2026-08-05)：修正标准 RDHWR 的 `rs=3` 与 `rd=0/1/2/3/29` 指令编码、`$1/$3` CP0 selector/address 映射，并在 CPU 中串行化相邻 CP0 read；SoC gate 验证 `$0..$3/$29` kernel readback 及 user HWREna 权限矩阵。
- v0.9 (2026-08-07)：CP0 firmware gate 以 `UserLocal=0x00006000` 作为真实 TLS 基址，验证用户态通过 `RDHWR $29` 读取 TLS 槽位并写回第二槽位；完整 TLS linker/多线程调度 ABI 仍未闭合。
- v1.0 (2026-08-07)：`cp0_sweep` 使用专用 linker script 固定 `.tdata`/`.tbss`，由 `__tls_start`/`__tbss_start` 导出 TLS 布局；SoC gate 验证初始化槽、清零槽和用户态 TLS store。完整 TLS relocation/model 仍 deferred。
- v1.1 (2026-08-07)：ID-stage hazard decode 将 COP0/MTC0 的 `rt` 标记为真实源操作数，复用 EX/MEM/WB GPR forwarding；RTL frontend、CP0 firmware、ASID allocator 和 MMU context contract 均通过。
- v1.2 (2026-08-07)：`cp0_sweep` 增加无显式 `nop` 的连续 UserLocal A->B->A MTC0/RDHWR context-switch 检查并通过；当前 CPU/CP0 contract 已闭合，完整 scheduler 保存/恢复 ABI 仍 deferred。
