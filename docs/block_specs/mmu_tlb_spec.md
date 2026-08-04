# MMU / TLB 微架构规格 (v0.4)

> 状态：v0.4 草案。作为 Phase B **新增 `rtl/cpu/mips_tlb.v` + 修改 `rtl/cpu/mips_cpu.v` / `mips_if_stage.v` / `mips_mem_stage.v`** 的实施基线。与 `cp0_spec.md` 配套读。
>
> 引用：MIPS® Volume III Rev 6.06 §4 (Memory Management)。

---

## 0. 目标与范围

**目标**：为 AP-lite (24Kc 竞品) MIPS32 R2 提供最小可运行 Linux 的 MMU：

- **软件管理** TLB（refill 由异常处理程序完成，非硬件 walker）。
- **64 entries**、fully-associative、双页 (each entry = even/odd VPN pair)。
- **可变页尺度**：4KB / 16KB / 64KB / 256KB / 1MB / 4MB / 16MB（用 PageMask 编码）。
- **ASID** 8 位，256 个进程域。
- **G (Global)** 位跨 ASID 匹配（内核代码用）。
- **精确异常**：TLB Refill / TLB Invalid / TLB Modified / TLB Machine Check（重复命中）。
- 单周期命中；miss/异常插泡冲刷流水线。

**不做**（本 phase）：
- 硬件 page table walker (HPTW) — 软件 refill 已足够；HPTW 属于 Phase B+。
- 32-bit segmentation extensions / 64-bit XKphys — MIPS32 只需 32-bit segmented。
- MT ASE 多线程 TLB 划分 — 单核单 hart。
- Guest Mode / VZ (虚拟化) — 不做。

---

## 1. 地址空间模型（MIPS32 分段）

MIPS32 硬编码 4 段：

| 名称 | 虚拟范围 | 大小 | 特权 | 走 TLB | Cache |
|---|---|---|---|:-:|---|
| **useg / kuseg** | 0x0000_0000 – 0x7FFF_FFFF | 2 GB | User+Kernel | ✓ | 依 EntryLo.C |
| **kseg0**        | 0x8000_0000 – 0x9FFF_FFFF | 512 MB | Kernel only | ✗ | Cacheable (Config.K0) |
| **kseg1**        | 0xA000_0000 – 0xBFFF_FFFF | 512 MB | Kernel only | ✗ | **Uncached** |
| **ksseg / kseg2**| 0xC000_0000 – 0xDFFF_FFFF | 512 MB | Kernel/Supervisor | ✓ | 依 EntryLo.C |
| **kseg3**        | 0xE000_0000 – 0xFFFF_FFFF | 512 MB | Kernel only | ✓ | 依 EntryLo.C |

**映射规则**：

- **kseg0**：`PA = VA & 0x1FFF_FFFF`，直通到低 512MB 物理空间，走 cache（属性由 `Config.K0` 决定）。
- **kseg1**：`PA = VA & 0x1FFF_FFFF`，直通、**强制 uncached**。启动向量 `0xBFC0_0000` 在此段。
- **useg/kseg2/kseg3**：走 TLB 翻译，权限 = TLB entry.V/D + 段特权。

**用户态访问 kseg\***：产生 Address Error (AdEL/AdES)，`BadVAddr = VA`，`ExcCode = 4/5`。

---

## 2. TLB 组织

### 2.1 结构

- **64 entries**，fully-associative。
- 每 entry 包含：
  - **Match 部分**：VPN2 (19 bit, 覆盖偶奇双页) + PageMask (16 bit) + ASID (8 bit) + G (1 bit) + Valid (硬件位)。
  - **Data 部分**：
    - Lo0：PFN0 (20 bit) + C0 (3 bit) + D0 (1) + V0 (1) + G0 (1)
    - Lo1：PFN1 (20 bit) + C1 (3 bit) + D1 (1) + V1 (1) + G1 (1)
- 一条 entry 同时映射**两页**（VPN2 = VA[31:13] 的偶数半；4 KiB 时选择位为 VA[12]，更大页按 PageMask 取页偏移范围以上的 VA 位）。

### 2.2 参数

| 参数 | 默认 | 说明 |
|---|:-:|---|
| `TLB_ENTRIES` | 64 | 条目数（`Config1.MMUSize` 报告 `-1`）|
| `PABITS` | 32 | 物理地址宽度 (PFN 20 位 = 32 bit PA @ 4KB) |
| `ASID_BITS` | 8 | ASID 宽度 |
| `MIN_PAGE_LOG2` | 12 | 最小页 = 4KB |
| `MAX_PAGE_LOG2` | 24 | 最大页 = 16MB |

---

## 3. 匹配 (Lookup) 语义

给定 (`VA`, `ASID_curr`)：

1. 对每 entry i 并行比较：
   - `MASK_i = PageMask_i | 0x1FFF`（保底 4KB 位屏蔽）
   - `MATCH_VPN_i = (VA[31:13] & ~MASK_i[28:13]) == (VPN2_i & ~MASK_i[28:13])`
   - `MATCH_ASID_i = G_i || (ASID_i == ASID_curr)`
   - `HIT_i = Valid_i && MATCH_VPN_i && MATCH_ASID_i`
2. **奇偶选择位** = 页偏移范围以上的 VA 位：PageMask `0x0000/0x0003/0x000F/0x003F/0x00FF/0x03FF/0x0FFF/0x3FFF` 分别使用 `VA[12/14/16/18/20/22/24/26]`（等效于按页尺度将 entry 分成偶奇两半）。RTL 对非法/非连续 mask 回退到 4 KiB 选择位。
   - 若选择位 = 0 → 用 `Lo0`（PFN0/C0/D0/V0）
    - 若选择位 = 1 → 用 `Lo1`
   - PA 由现有 `{PFN, VA[11:0]}` MMU 接口形成；RTL 在大 PageMask 下将 `VA[13:12]` 等额外页内偏移位折入 PFN 低位，保持完整物理页内偏移。
3. **命中后属性检查**：
   - 若 `V=0` → **TLB Invalid** 异常（Load/Fetch → TLBL；Store → TLBS）
   - 若 `V=1 && op==store && D=0` → **TLB Modified** 异常
   - 否则命中，输出 `PA = {PFN, VA[LSB_BITS-1:0]}`、cache 属性 `C`。
4. **未命中**（无 entry HIT） → **TLB Refill** 异常（`ExcCode = TLBL/TLBS`，向量走 `EBase+0x000` 而非 `+0x180`，`Status.EXL` 之前进入是 refill 向量，之后进入是普通异常向量）。

**Multi-hit 检测**：若 `HIT_i` 与 `HIT_j` (i≠j) 同时为 1 → 立即 `Status.TS = 1` 并触发 **Machine Check** (`ExcCode = 24`)。软件必须复位芯片或 TLB 才能清 TS。

---

## 4. 时序（流水线接入）

### 4.1 IF 阶段 (指令取指)

- IF1: 组合查 TLB (I-TLB port)；ITLB miss 或 invalid → 冲刷 IF、生成异常在 ID 阶段捕获（保持精确异常）。
- 命中 → 传 PA + cache attr 给 I-cache。
- **建议实现**：I-cache 采用**物理索引物理标记 (PIPT)**，或最小 4KB 页 + I-cache 索引位 ≤ 4KB 的 **VIPT non-aliasing**。当前 8KB 4-way (=2KB per way) 满足 non-aliasing，可保留 VIPT。

### 4.2 MEM 阶段 (数据访问)

- MEM1: 组合查 TLB (D-TLB port)；DTLB miss/invalid/modified → 冲刷 MEM/WB、生成异常。
- 命中 → 传 PA + cache attr 给 D-cache。
- **写检查**：store 且 D=0 → TLB Modified。

### 4.3 双端口 TLB 实现选项

| 选项 | 优点 | 缺点 |
|---|---|---|
| A. 单份 64-entry CAM，双读端口 | 面积小 | 需双读比较端口，功耗高 |
| **B. Micro-TLB 分离 (推荐)** | 4-entry ITLB + 8-entry DTLB fully-assoc micro-TLB；主 TLB 64-entry 单端口，miss 时 fill micro-TLB | 二级复杂度，但吞吐好、功耗低（24Kc 采用此结构）|

**当前 RTL 基线**：采用方案 A 的 direct dual-lookup 变体。`mips_tlb` 保持一份主 TLB array，并为 I/D 两侧提供组合 lookup；当前没有独立 micro-TLB fill/flush 状态机。方案 B（I/D micro-TLB）作为后续性能/功耗优化，不属于当前 RTL 功能闭合条件；主 TLB miss 仍由软件 refill 处理。

### 4.4 TLB 指令 (TLBR/TLBWI/TLBWR/TLBP)

只允许内核态执行，否则 RI 异常。

- **TLBP**：以 `EntryHi.VPN2 + EntryHi.ASID` 查主 TLB。命中 → `Index[log2N-1:0] = 命中索引`, `Index[31] = 0`；miss → `Index[31] = 1`；重复命中置 `Status.TS`。
- **TLBR**：从主 TLB `[Index]` 读回 → 填充 `EntryHi/EntryLo0/EntryLo1/PageMask`。
- **TLBWI**：把 `EntryHi/EntryLo0/EntryLo1/PageMask` 写入主 TLB `[Index]`。
- **TLBWR**：同 TLBWI 但索引 = `Random`。

**执行时序**：单周期发射；当前无 micro-TLB 清空泡，lookup 直接观察主 TLB array。

---

## 5. Refill / Exception 异常路径

### 5.1 TLB Refill (最快路径)

当 useg/kseg2/kseg3 访问未命中且 `Status.EXL=0`：

1. 硬件更新：
   - `BadVAddr = VA`
   - `Context.BadVPN2 = VA[31:13]`
   - `EntryHi.VPN2 = VA[31:13]`, `EntryHi.ASID` 不变
   - `Cause.ExcCode = TLBL/TLBS`
   - `EPC = PC` (or PC of branch if BD)
   - `Status.EXL = 1`
2. PC ← **refill 向量**：`EBase + 0x000` (BEV=0) 或 `0xBFC0_0200` (BEV=1)。
3. 软件 refill handler 用 Context 快速拼出 PTE 地址，读两条相邻 PTE，写 `EntryLo0/1`，`TLBWR` 后 `ERET` 返回。

### 5.2 TLB Invalid / TLB Modified

当命中但 V=0 或 (store && D=0)，或 refill 时 `Status.EXL=1`（嵌套异常）：

1. 硬件更新同上，但**向量走通用异常** `EBase + 0x180`。
2. 软件按 `ExcCode` (`Mod`/`TLBL`/`TLBS`) 处理，可能是 CoW、demand paging、权限。

### 5.3 Machine Check

Multi-hit → `ExcCode = 24 (MCheck)`, `Status.TS = 1`。软件通常记录后重置。

---

## 6. 与 Cache 的接口

- **I-cache / D-cache 输入**：`{ PA[31:0], cache_attr[2:0], valid, wr_en, wr_data, byte_en, size }` 由 TLB/MEM 阶段提供。
- **Cache attr** (`EntryLo.C`)：
  - `010` → Uncached：绕过 cache 直接 AXI 事务。
  - `011` → Cacheable Write-back Write-allocate。
  - `000-001, 100-111` → Phase B 保留（视为 Uncached 兜底）。
- kseg0/kseg1 直通不走 TLB：
  - kseg0：使用 `Config.K0` 编码（软件写）。
  - kseg1：硬编码 `Uncached`。
- **CACHE 指令**：软件下发 line invalidate/writeback；TLB 参与地址翻译（Index ops 除外）。详见 Phase C cache spec。

---

## 7. ASID 管理与 TLB Flush

- 进程切换：OS 写 `EntryHi.ASID = new_asid`；micro-TLB 清空；主 TLB 保留（其他 ASID 的条目自然不命中）。
- ASID 溢出：OS 全 flush TLB（遍历 TLBWI 写非法条目，或 `Wired` 保留 + 其余置 V=0）。
- **Global 位**：内核 kseg2/kseg3 的映射通常 G=1，跨 ASID 命中，避免频繁 refill。

---

## 8. 参数化开关

`rtl/include/soc_config.vh` 新增：

```verilog
`define SOC_TLB_ENTRIES     64
`define SOC_TLB_UTLB_I      4      // I-TLB micro-TLB 条目数
`define SOC_TLB_UTLB_D      8      // D-TLB micro-TLB 条目数
`define SOC_TLB_ASID_BITS   8
`define SOC_TLB_MAX_PAGE_LOG2 24   // 16MB
`define SOC_MMU_ENABLE      1      // 0 = 直通物理，绕开 TLB（早期 bring-up）
```

`SOC_MMU_ENABLE=0` 提供快速回退：所有访问按 kseg0 规则直通。用于 Phase B 早期 bring-up。

---

## 9. 验证要求（对齐 `vplan.md`）

**块级**（`tb/uvm_tb/tlb/`）：
- Refill 路径：8 种页尺度 × 偶奇 × G/ASID 命中/未命中 = 覆盖组。
- Invalid / Modified 路径：全组合。
- TLBP hit/miss / TLBR / TLBWI / TLBWR 后一致性检查（读回相等）。
- Wired 语义：Random 不低于 Wired。
- ASID 隔离：两 ASID 相同 VPN 命中不同 PA。
- Multi-hit machine check：软件强制 TLBWI 写两条重叠 → TS=1 + MCheck。
- micro-TLB 一致性：TLB 指令后 micro-TLB 清空断言。

当前已有的独立契约 gate `tb/unit/tlb/run_tlb_asid_policy.sh` 使用 `SOC_MMU_ENABLE=1`
直接连接 `mips_tlb` 和 `mips_mmu`，验证 4KB 页的 ASID 隔离、Global 跨 ASID 命中、
matching-invalid 的 TLBL/TLBS 分类，以及清页 store 的 Modified 分类。该 gate 只关闭
上述 ASID/异常分类子集；同一 TLB index 的 `0xfe -> 0xff` replacement/旧 ASID 隔离
已有 rollover slice。新增 `tb/unit/tlb/run_tlb_os_context.sh` 以真实
`mips_tlb + mips_mmu` 建立软件页表 fixture，验证两个 ASID 对同一 VA 的不同 PFN、
VPN pair even/odd、wired global 保留、非 wired flush 以及 ASID 1..255 回卷后的重新填充。
这关闭了 software-managed TLB context-switch 的硬件边界子集。该 gate 还验证 PageMask `0x0003`
的 16 KiB even/odd 选择及 `VA[12]` offset 保持，以及重叠 valid 项的 MCheck 分类；其余页尺度尚未由 SoC/OS 压力覆盖。新增
`tb/soc_test/run_product_mmu_asid_context.sh` 在真实 SoC firmware 上验证 ASID 1/2
同 VA 不同 PFN、切回命中、`TLBWI` 清空动态槽、wired APB 保留和重新 refill。可变页大小、
micro-TLB、TLB shootdown/IPI 和 SoC/OS 级 allocator 压力仍未实现或未验证。

**SoC 级**：
- Linux boot：kernel 早期 head.S 建映射 → paging on → init 进程 → busybox shell。
- 上下文切换压力：多进程 ASID rollover。
- CoW / demand paging：用户程序触发写保护 → Mod 异常 → OS 处理。

**Formal**：
- micro-TLB coherence with main TLB (bind checker)。
- Multi-hit detection completeness。
- 异常向量正确性 (EBase + 0x000 vs 0x180 vs BEV 变体)。

**覆盖率门槛**：
- 8 种页尺度全命中 (100%)。
- 3 种异常路径 (Refill/Invalid/Modified) 每 slot × 每 exec mode。
- ASID rollover + Wired 边界。

---

## 10. Phase B 实施拆分建议（配合 `cp0_spec.md` §15）

按 CP0 §15.3 (B.3 MMU/TLB) 展开：

- **B.3.1**：主 TLB 数据结构 + TLBR/TLBWI/TLBWR/TLBP 指令。用 `SOC_MMU_ENABLE=0` 保守跑通现有 firmware。
- **B.3.2**：Lookup 路径 + kseg0/1 直通 + micro-TLB (I/D 分离)。启用 `SOC_MMU_ENABLE=1`，加内核态自测。
- **B.3.3**：异常路径 (Refill / Invalid / Modified / MCheck) + 向量分派 (EBase/BEV/refill vs general)。
- **B.3.4**：Linux 头 (head.S) 移植 + 早期 paging 打开跑通。
- **B.3.5**：完整 Linux boot 到 busybox shell。

### 10.1 已解除的前置阻塞与当前边界

历史上，`SOC_MMU_ENABLE` 由 0 翻转为 1 后，现有 prototype `soc_smoke` 在早期超时。该 firmware 的
reset/vector 链接仍在 useg，不能作为产品 MMU boot 的验收程序。这个原型限制仍然存在，
但已经不再阻塞当前的产品 kseg0 指令交接子集。

**根因（架构级，非 firmware 缺陷）**：
- prototype 配置的复位向量固定为 `0x0000_0000`，异常向量固定为 `0x0000_0180`。产品 opt-in
  配置已实现 `0xBFC0_0000` 复位、普通异常与真实 TLB miss 的
  `BEV ? BFC0_0200/BFC0_0380 : EBase/EBase+0x180` 选择。该路由已由完整
  SoC directed I-side 和 D-side 测试验证；它仍没有产品 linker/TLB firmware，不能解除本节的 MMU
  启动阻塞。
- 当前 firmware 链接脚本（`tb/soc_test/fw/common/link.ld`）把 `_start` 和 `_except_handler` 都放在
  useg（VA[31]=0）。
- `SOC_MMU_ENABLE=1` 时，useg 的任何访问（包括取指）都必须先过 TLB 查找（`mips_mmu.v`），kseg0/1
  才是永久直通（`pa = {3'b000, va[28:0]}`，与 MMU 开关无关）。
- 于是形成死锁：复位后 CPU 要取 `_start`（useg）→ 触发 TLBL miss → 跳转到 `_except_handler`
  （同样在 useg）→ 取这条异常处理指令本身又需要一个已存在的 TLB entry → 而这正是 handler
  要去安装的东西。CPU 连第一条指令、第一条异常处理指令都取不出来，firmware 层面无法打破这个循环。

**已完成的前置子任务**：development manifest handoff image 已将 stage 1 放在物理 SRAM
`0x0000_1000`，并以 kseg0 VA `0x8000_1000` 作为入口。`make product-kseg0-runtime-gate`
在 `SOC_MMU_ENABLE=1` 下观察到 instruction request 的 PA 为 `0x0000_1000`，并由 stage 1
额外观察到单次 kseg0 data request `0x8000_7000 -> 0x0000_7000`；有效、header/CRC
negative、XIP-timeout 场景均通过。它与 fabric alias fold（`mips_mmu.v` 注释里提到的
`0xA000_0000` SRAM 别名问题）无关，是两个独立问题。

**当前结论**：kseg0 的 instruction fetch/handoff、单次 data translation slice、software-managed
TLB context-switch 硬件边界和 bounded 4-ASID round-robin/shootdown slice 已达到
`BLOCK_VERIFIED`，但 B.3.2 仍未整体完成。尚未证明完整 runtime data mapping、SoC 多进程
page-table allocator/scheduler 压力、IPI shootdown、cache maintenance、完整异常 handler
或 Linux/kernel boot，因此不能把此 gate 标为 MMU 产品完成。

**已保留的验证脚手架**（prototype useg 链接仍会触发上述历史死锁；产品切片使用独立 linker）：
- `tb/soc_test/fw/tests/mmu_refill/`：最小 TLB-refill handler（TLBWR 安装 identity map + ERET 重试）。
- `tb/soc_test/run_mmu_refill.sh`：独立跑该固件的 gate 脚本（当前会因上述阻塞而失败，属预期）。
- `rtl/include/soc_config.vh` 中 `SOC_MMU_ENABLE` 的 `ifndef` 保护，允许通过
  `+define+SOC_MMU_ENABLE=1` 命令行覆盖，不影响项目默认值 0。

**下一项**：在已验证的 bounded 4-ASID slice 上补齐完整 runtime data mapping、SoC 多进程
page-table/ASID allocator、scheduler 与 shootdown IPI 压力、cache-error/EIC policy 和
kernel-mode firmware gate。
在这些 gate 通过前，MMU 仍不是可启动的
完整产品功能。

---

## 版本记录

- v0 (2026-07-26)：初版规格，64-entry TLB + micro-TLB 分离 + 软件 refill 模型。等待 Phase B 起始时评审。
- v0.1 (2026-07-30)：记录 `SOC_MMU_ENABLE=1` 架构级阻塞点（useg 向量死锁），见 §10.1。
- v0.2 (2026-08-01)：产品 opt-in 实现并验证 refill 与 Invalid 的 BEV/EBase 向量分派；产品 linker 和 handler 继续为 P0。
- v0.3 (2026-08-02)：新增并通过 `product-mmu-process-pressure-gate`，覆盖 ASID 1..4 round-robin、动态 TLB shootdown 和清空后的重新 refill；完整 OS allocator/scheduler/IPI 仍为后续任务。
- v0.3 (2026-08-01)：新增 `tlb_asid_policy` directed gate，闭合 4KB ASID/Global/Invalid/Modified
  翻译边界；不扩大对可变页、multi-hit、micro-TLB 或 Linux/ASID rollover 的功能声明。
- v0.4 (2026-08-01)：新增 MMU-enabled kseg0 stage-1 instruction handoff gate，证明
  `0x8000_1000 -> 0x0000_1000`；明确该子集不等于完整 runtime 或 kernel boot。
- v0.5 (2026-08-02)：新增 `tlb_os_context` gate，证明软件页表/context-switch 的硬件边界、
  wired global 保留与 ASID 1..255 回卷清空；不扩大到 SoC/OS allocator、shootdown 或 Linux boot。
- v0.6 (2026-08-02)：新增 `product_mmu_asid_context` SoC firmware gate，证明 ASID 1/2
  同 VA 不同 PFN、软件 `TLBWI` 动态清空与重新 refill；不扩大到 IPI、multi-core 或调度压力。
