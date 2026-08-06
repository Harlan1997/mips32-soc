# L1 指令缓存 (I-Cache) 微架构规格 (v1)

> 状态：v1 部分实现。已交付 **8 KB 4-way 组相联 + tree-PLRU 替换**（`rtl/cache/icache.v`：
> 64 sets、index [10:5]、tag [31:11]、物理寻址、只读、单-outstanding 阻塞式 refill）。
> 单元测试 `tb/unit/icache/tb_icache.v`（冷 miss/refill/hit、行内顺序命中、4-way 填满不误逐出、
> PLRU 逐出且 MRU way 保留、数据完整性）通过，纳入 `make dut-block-unit-gate`（[7/7]）。
> 全部固件测试经指令取指路径 + phase3/uvm/smoke 全绿。
>
> 已实现的 CACHE 子集：`Index_Invalidate_I`、`Hit_Invalidate_I`、
> `Index_Store_Tag_I`、`Index_Load_Tag_I`。这些操作均为阻塞式维护，
> 不发起 AXI 写事务；Hit invalidate 未命中时为成功 no-op。`SYNCI` 映射为
> 同一条 Hit invalidate 维护路径；完整 OS cache-ordering ABI 仍为后续工作。

---

## 0. 目标

- **容量**：8 KB (可参数化 16 KB / 32 KB)
- **组织**：4-way 组相联，LRU 替换
- **行大小**：32 B (8 × 32-bit)
- **索引方式**：**VIPT non-aliasing**（每 way 2 KB ≤ 最小页 4 KB 保证不 alias）
- **访问**：单周期命中；miss 走 AXI4 8-beat burst
- **写行为**：只读（指令流），无 write allocate
- **一致性**：无（单核；D-cache 与 I-cache 通过 CACHE 指令 + `SYNCI` 显式同步）
- **CACHE 指令**：`Index_Invalidate`、`Hit_Invalidate`、`Index_Store_Tag`、`Index_Load_Tag`
- **报告**：`Config1.IS/IL/IA` 与实际组织一致

---

## 1. 参数与地址划分

```verilog
`define SOC_ICACHE_SIZE        8192       // bytes
`define SOC_ICACHE_WAYS        4
`define SOC_ICACHE_LINE_BYTES  32
`define SOC_ICACHE_INDEX_BITS  6          // 8192 / 4 / 32 = 64 sets
`define SOC_ICACHE_OFFSET_BITS 5          // log2(32)
`define SOC_ICACHE_TAG_BITS    (32 - `SOC_ICACHE_INDEX_BITS - `SOC_ICACHE_OFFSET_BITS)
```

**地址分解**（32-bit VA / PA）：

| 31 : 11 | 10 : 5 | 4 : 2 | 1 : 0 |
|:-:|:-:|:-:|:-:|
| Tag (21) | Index (6) | Word (3) | Byte (2) |

- Index 用**虚拟地址** VA[10:5]（VIPT）。
- Tag 用**物理地址** PA[31:11]（PIPT 标签）。
- 每 way 大小 = 8192/4 = 2048 B ≤ 4 KB 最小页 → 不同虚拟地址映射同物理页时 index 一致 → **无 alias**。

---

## 2. 结构

### 2.1 数据阵列

- **Data RAM**：4 way × 64 set × 32 B = 8 KB。
  - 每 way 单口同步 RAM。
  - 读延迟 1 cycle（组合读输出 latch 后一拍到 IF+1）。
- **Tag RAM**：4 way × 64 set × (`TAG_BITS + valid` = 22 bit)。
  - 单口同步。
- **LRU 状态**：4-way pseudo-LRU (3 bit per set) 或真 LRU (log2(4!)=5 bit)。**Phase C 默认 pseudo-LRU 3-bit**。

### 2.2 Miss FSM

```
ST_IDLE   → hit 检查 & 送 IF
ST_MISS   → 发起 AXI ARVALID, len=7
ST_REFILL → 收 8 beat 数据, 写 way (LRU 决定)
ST_UPDATE → 更新 tag + valid + LRU；送 hit 数据给 IF
```

**MSHR**：单条 miss FIFO（1 outstanding refill）。多 outstanding 视 L2 支持在 Phase C 后期扩展。

---

## 3. 命中路径 (读)

```
IF stage:
  1. IF 传 VA + TLB 结果 (PA[31:11] + cache_attr)
  2. Index = VA[10:5]
  3. 并行读 4 way Tag & Data (同拍)
  4. way_hit[i] = valid[i] && (tag[i] == PA[31:11])
  5. hit = |way_hit
  6. data = mux(way_hit, data_way[])[VA[4:2]]  // 选 32-bit word
  7. IF+1: hit → 送指令；miss → 送 nop + assert stall
```

**Cache attr 检查**：
- `cache_attr == uncached (010)` → 强制 miss → 走 AXI **单 beat** 读，不填 cache。
- `cache_attr == cacheable_wb (011)` → 正常 cache 路径。

---

## 4. Miss 路径 (refill)

```
On miss (cacheable):
  1. FSM → ST_MISS
  2. 发 AXI AR:
       ARADDR = {PA[31:5], 5'b0}  // 行对齐
       ARLEN  = 7                  // 8 beat
       ARSIZE = 3'b010             // 4 byte
       ARBURST= 2'b01              // INCR
       ARID   = ICACHE_ID
       ARCACHE= 4'b0011            // Normal Non-cacheable Bufferable (或按 cache_attr)
       ARPROT = 3'b100             // Instruction fetch
  3. FSM → ST_REFILL
  4. 收 R beat 0..7：写入 replaced_way 的 line buffer
  5. 收到 RLAST → ST_UPDATE
  6. 写 Tag RAM (tag, valid=1), 更新 LRU
  7. 组合返回 hit 数据给 IF
  8. FSM → ST_IDLE
```

**Uncached** 路径：ARLEN=0，读单 beat，直接给 IF，不填 cache RAM。

**Replacement**：pseudo-LRU 3-bit tree。若有 invalid way → 优先填 invalid。

---

## 5. CACHE 指令

MIPS CACHE `op[4:0]` 编码，本 phase 实现子集：

| op | 助记 | 行为 |
|:-:|---|---|
| 5'b00000 | Index_Invalidate_I  | 清除由 VA `[12:11]` 选择的 way、VA `[10:5]` 选择的 set 的 valid |
| 5'b01000 | Index_Store_Tag_I    | 用 TagLo (CP0) 写 tag/valid 到 index |
| 5'b00001 | Index_Load_Tag_I     | 读 index 的 tag 到 TagLo |
| 5'b10000 | Hit_Invalidate_I     | 若 physical tag 命中 → 清该 way valid；miss → 成功 no-op |

**决策**：TagLo/TagHi CP0 寄存器（`(28, 0)` / `(29, 0)`）需要在 CP0 spec 补齐（当前 Phase B spec 未列 → v1 增补）。

CACHE 指令走 MEM 阶段发到 I-cache 控制端口（新增），产生 1-3 cycle bubble。

**SYNCI**：软件工具用来同步 I-cache 与 D-cache（比如 JIT）。当前实现将
`SYNCI offset(base)` 解码为 I-cache `Hit_Invalidate_I`，并依靠 in-order
pipeline 保证此前存储已完成；额外 `SYNC` 仍是 ordered no-op。

---

## 6. 与 TLB / 异常交互

- IF 阶段 TLB miss → 冲刷 I-cache 请求；exception 走 TLB refill 向量。
- TLB Invalid → 同上，走 general exception。
- I-cache miss **发起后** TLB 命中/未命中不变（TLB 命中已锁定 PA，refill 用 PA）。
- AXI 返回 SLVERR/DECERR → Instruction Bus Error (IBE, `ExcCode=6`)，冲刷 IF 与 refill。

---

## 7. Reset 与 Flush

- Reset：所有 valid=0，LRU=0，FSM=IDLE。**不需清 tag/data**。
- Pipeline flush（异常/mispredict）：**不影响 cache 状态**，只弃当前 in-flight refill 的写回结果（若已开始 refill，让其完成以避免协议错误 —— refill 数据仍写 way，可能提前学习）。
- TLB 更新后：软件负责 CACHE Hit_Invalidate 与 SYNCI。

---

## 8. Config1 报告

I-cache 部分：

| 字段 | 编码 | 值 |
|---|---|---|
| Config1.IS[24:22] | log2(sets/64) | 0 (64 sets) |
| Config1.IL[21:19] | log2(line/2)+1 | 5 (32 B) |
| Config1.IA[18:16] | ways-1 | 3 (4 ways) |

---

## 9. 接口

```verilog
module l1_icache #(
    parameter SIZE_BYTES = 8192,
    parameter WAYS       = 4,
    parameter LINE_BYTES = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Fetch interface (from IF stage)
    input  wire        fetch_valid,
    input  wire [31:0] fetch_va,
    input  wire [31:0] fetch_pa,       // from TLB (VIPT tag = PA)
    input  wire [2:0]  fetch_cache_attr,
    output wire        fetch_ready,    // hit or refill done
    output wire        fetch_hit,
    output wire [31:0] fetch_data,
    output wire        fetch_ibe,      // bus error

    // CACHE instruction port
    input  wire        cache_op_valid,
    input  wire [4:0]  cache_op,
    input  wire [31:0] cache_op_addr,
    output wire        cache_op_ready,

    // AXI4 read-only master
    output wire [3:0]  m_arid,
    output wire [31:0] m_araddr,
    output wire [7:0]  m_arlen,
    output wire [2:0]  m_arsize,
    output wire [1:0]  m_arburst,
    output wire [3:0]  m_arcache,
    output wire [2:0]  m_arprot,
    output wire        m_arvalid,
    input  wire        m_arready,

    input  wire [3:0]  m_rid,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready
);
```

---

## 10. 验证要求

**块级** (`tb/uvm_tb/icache/`)：

- 每 way × 每 set × hit/miss 全覆盖。
- Refill 全 8 beat、SLVERR/DECERR、部分 beat error。
- LRU 4-way rotation：连续访问 5 个不同 tag 同 index → 最老 way 被替换。
- CACHE Index_Invalidate / Hit_Invalidate 命中/未命中。
- Uncached vs cacheable attr 混合。
- VIPT non-aliasing：同 PA 不同 VA (若 index 相同) 命中同 way。
- Reset 后首次访问 → miss → refill。
- AXI 协议合规（bind 现有 axi_protocol_checker）。

**SVA**：
- Hit 唯一（∑way_hit ≤ 1）。
- Refill 期间 FSM 不 IDLE。
- ARLEN=7 for cacheable line refill。
- valid 位不出现 X。

**Formal**：
- LRU 更新等价软件模型。
- Refill FSM 无死锁（bounded 32 cycles）。
- CACHE Hit_Invalidate 后再访问同地址 → miss。

**性能门槛**：
- CoreMark I-cache hit rate ≥ 95%。
- 冷启动 refill 全流 8 beat 无 stall（除 AXI backpressure）。

---

## 版本记录

- v0 (2026-07-26)：初版规格，8 KB 4-way VIPT + pseudo-LRU + 1 MSHR + CACHE 指令子集。等待 Phase C 启动评审。
