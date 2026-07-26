# L1 数据缓存 (D-Cache) 微架构规格 (v0)

> 状态：v0 草案。作为 Phase C **重写 `rtl/cache/dcache.v`** 的实施基线。当前是 8KB 2-way；升级为 8KB 4-way LRU + VIPT + WB/WA + CACHE 指令 + 单/多 MSHR 非阻塞。

---

## 0. 目标

- **容量**：8 KB (可参数化 16 KB / 32 KB)
- **组织**：4-way 组相联，pseudo-LRU 替换
- **行大小**：32 B (8 × 32-bit)
- **VIPT non-aliasing**：每 way 2 KB ≤ 4 KB 页 → 无 alias
- **写策略**：**Write-Back + Write-Allocate**（唯一）
- **非阻塞**：2 个 MSHR（1 load miss + 1 store miss，或 2 load miss）
- **Store buffer**：4-entry 合并写
- **CACHE 指令**：`Index_Invalidate`、`Index_Writeback_Invalidate`、`Hit_Invalidate`、`Hit_Writeback`、`Hit_Writeback_Invalidate`
- **Uncached 直通**：绕过 cache 直接 AXI
- **报告**：`Config1.DS/DL/DA` 与实际组织一致

---

## 1. 参数与地址划分

同 icache（参见 `icache_spec.md` §1），tag/index/offset 布局一致。

```verilog
`define SOC_DCACHE_SIZE         8192
`define SOC_DCACHE_WAYS         4
`define SOC_DCACHE_LINE_BYTES   32
`define SOC_DCACHE_MSHR         2
`define SOC_DCACHE_STORE_BUF    4
```

---

## 2. 结构

### 2.1 数据 / 标签阵列

- **Data RAM**：4 way × 64 set × 32 B
- **Tag RAM**：4 way × 64 set × (Tag + valid + **dirty**) ≈ 23 bit
- **LRU RAM**：64 set × 3 bit (pseudo-LRU)
- **Dirty bit per line**（不是 per byte —— 写回时整行）

### 2.2 Store Buffer

- 4-entry FIFO，条目 = {addr, data, byte_en, size}
- 合并到 same line：如果新 store 地址在 buffer 内已存在 line → 合并 byte_en
- 排空时机：cache hit 后立即写；cache miss 走 MSHR
- 加速：MEM 阶段 store 直接入 store buffer，写不 stall（除非 buffer 满）

### 2.3 MSHR (Miss Status Holding Register)

- 2 entries
- 每 entry 记录：{addr line, dst way, mshr_type (load/store/rmw), pending_reqs}
- 允许一个 MSHR 服务多个访问同 line 的请求（合并）
- MSHR 满 → stall MEM 阶段

### 2.4 Miss FSM

```
ST_IDLE      → hit 检查
ST_ALLOC     → 选 way（LRU），若 dirty → 记录 evict
ST_WB_EVICT  → dirty way 写回 AXI (8-beat W burst)
ST_MISS_AR   → 发起 refill AXI R (8-beat)
ST_REFILL    → 收 8 beat 写入 way + 合并 pending store（write-allocate）
ST_UPDATE    → 更新 tag/valid/dirty/LRU；send response
```

对 store miss (WA)：refill 后合并 pending store 的 byte_en → dirty=1。

---

## 3. 命中路径

### 3.1 Load 命中 (1 cycle)

同 icache：
```
1. Index = VA[10:5]
2. 并行读 4 way tag/data
3. way_hit[i] = valid[i] && (tag[i] == PA[31:11])
4. hit = |way_hit
5. word = mux(way_hit, data)[VA[4:2]]
6. byte_sel = size-shift-select on VA[1:0]
7. load_data = sign/zero extend
```

### 3.2 Store 命中 (1 cycle + store buffer)

```
1. 同 load 命中检查
2. 命中 → 入 store buffer (合并策略)
3. Store buffer 排空时：写 data RAM + set dirty=1 + 更新 LRU
```

Store buffer 排空与 load 无冲突 (LRU 更新可能有 race，Phase C 用简单锁：store 写入时 load 与 store 互斥同 cycle)。

### 3.3 Cache attr 分派

- `uncached (010)` → 绕 cache，直接走 AXI 单 beat R/W；不查 tag。
- `cacheable_wb (011)` → 正常 cache 路径。
- 其他 → Phase C 视 uncached 兜底。

---

## 4. Miss 路径

### 4.1 Load Miss

```
1. hit=0, cache_attr=cacheable
2. 检查 MSHR
   若已有 in-flight 同 line MSHR → 合并 (设置 pending_load flag, register 目标 dst_reg)
   否则分配新 MSHR，FSM 启动 refill
3. Refill 完成 → 从 buffer 取 word → 完成 load
```

### 4.2 Store Miss (Write-Allocate)

```
1. hit=0, cache_attr=cacheable
2. Store data 保留在 store buffer
3. MSHR 记录 pending store
4. Refill 完成后合并 store（byte_en 覆盖）→ dirty=1
```

### 4.3 Uncached Store / Load

```
Uncached load:  AXI R 单 beat，不入 cache
Uncached store: AXI W 单 beat，不入 store buffer 合并 (spec: strong ordering)
```

Uncached 严格顺序：等前一 uncached 完成才发下一。

### 4.4 Eviction

替换选中 dirty way：
```
1. FSM → ST_WB_EVICT
2. AXI W 8-beat burst 写 dirty line 到 memory
3. 收 BRESP=OKAY → 继续 refill
4. BRESP=SLVERR/DECERR → Data Bus Error (DBE, ExcCode=7)
```

---

## 5. CACHE 指令

MIPS `CACHE op[4:2]==001` (D-cache) 子集：

| op[4:0] | 助记 | 行为 |
|:-:|---|---|
| 5'b00001 | Index_Writeback_Invalidate_D | 若 dirty → writeback；然后 clear valid |
| 5'b10001 | Index_Load_Tag_D             | 读 tag 到 TagLo |
| 5'b01001 | Index_Store_Tag_D            | 写 TagLo 到 index |
| 5'b10101 | Hit_Invalidate_D             | 若命中 → clear valid（不 writeback，可能丢失 dirty）|
| 5'b11001 | Hit_Writeback_Invalidate_D   | 若命中 → writeback + clear valid |
| 5'b11101 | Hit_Writeback_D              | 若命中且 dirty → writeback + clear dirty，保留 valid |

CACHE 指令走 MEM 阶段专用端口；产生 1-16 cycle bubble（Hit_Writeback 需等 AXI）。

---

## 6. 与 TLB / 异常交互

- MEM TLB miss/invalid/modified → 冲刷 dcache 请求；异常。
- Refill 期间 AXI SLVERR/DECERR → DBE (ExcCode=7)；EPC 定位到发起的 load/store。
- Store buffer 中的 store 遇 TLB modified → 回滚 store buffer 项 + Mod 异常。

---

## 7. 一致性 / SYNC

- 单核，无 D↔D 一致性问题。
- I ↔ D：软件下发 CACHE + SYNC 序列（JIT / self-modifying code）。
- SYNC 指令：等所有 in-flight AXI store 完成 (BRESP 收齐) + 排空 store buffer。可能耗时 10+ cycle。
- 未来多核（Phase 后）：预留 snoop 接口。

---

## 8. Reset / Flush

- Reset：valid=0, dirty=0, LRU=0, MSHR 空, store buffer 空, FSM=IDLE。
- Pipeline flush（异常）：**cache 状态不清**；store buffer 中未提交的 store **回滚**（异常发生前的 store 保留，异常发生后的 store 弃）。**决策**：store 只在 commit（WB 阶段）时入 store buffer，避免回滚。
- 严格：MEM 阶段计算 addr + data，WB 阶段（若无异常）才入 store buffer。这样 store buffer 内容全是已提交，异常无需回滚。

---

## 9. Config1 报告

D-cache 部分：

| 字段 | 编码 | 值 |
|---|---|---|
| Config1.DS[15:13] | log2(sets/64) | 0 (64 sets) |
| Config1.DL[12:10] | log2(line/2)+1 | 5 (32 B) |
| Config1.DA[9:7]   | ways-1 | 3 (4 ways) |

---

## 10. 接口

```verilog
module l1_dcache #(
    parameter SIZE_BYTES = 8192,
    parameter WAYS       = 4,
    parameter LINE_BYTES = 32,
    parameter MSHR       = 2
)(
    input  wire        clk,
    input  wire        rst_n,

    // MEM stage interface (from WB commit for stores)
    input  wire        req_valid,
    input  wire        req_write,
    input  wire [31:0] req_va,
    input  wire [31:0] req_pa,
    input  wire [2:0]  req_cache_attr,
    input  wire [1:0]  req_size,       // 00=byte, 01=half, 10=word
    input  wire [3:0]  req_byte_en,
    input  wire [31:0] req_wdata,
    output wire        req_ready,
    output wire        req_hit,
    output wire [31:0] req_rdata,
    output wire        req_dbe,        // data bus error
    output wire        req_mod_exc,    // TLB modified (from upstream)

    // CACHE instruction port
    input  wire        cache_op_valid,
    input  wire [4:0]  cache_op,
    input  wire [31:0] cache_op_addr,
    output wire        cache_op_ready,

    // SYNC
    input  wire        sync_req,
    output wire        sync_done,

    // AXI4 master (R/W)
    // ... 完整 AXI4 端口 (AR/R/AW/W/B) ...
);
```

---

## 11. 验证要求

**块级** (`tb/uvm_tb/dcache/`)：

- Load hit/miss × 4 way × 64 set。
- Store hit/miss (WA)。
- Dirty eviction × 4 way。
- MSHR 满 stall / 合并同 line 请求。
- Store buffer 满 stall / 合并同 line。
- CACHE 6 种 op × hit/miss。
- Uncached load/store 单 beat 直通。
- SYNC 排空 store buffer + in-flight AXI。
- SLVERR/DECERR 转 DBE。
- LRU 5-way rotation。
- VIPT non-aliasing 双 VA 同 PA。
- TLB Modified → Mod 异常 + store buffer 回滚（decision §8）。
- Reset + 立即访问 → miss → refill。

**SVA**：
- Hit 唯一。
- Dirty=1 → 该行必定曾 write hit 或 refill 后合并 store。
- MSHR 计数 ≤ 2。
- Store buffer 计数 ≤ 4。
- SYNC 完成时 store buffer 空 & 无 in-flight AXI W。

**Formal**：
- LRU 与软件模型等价。
- WB/WA 语义：write-hit + writeback + read → 读到最新值。
- MSHR merge：多请求同 line → 单一 refill + 全部响应正确。

**性能门槛**：
- CoreMark D-cache hit rate ≥ 92%。
- Store buffer 满 stall < 3% total cycles。

---

## 版本记录

- v0 (2026-07-26)：初版规格，8 KB 4-way VIPT + WB/WA + 2 MSHR + 4-entry store buffer + CACHE 6 op。等待 Phase C 启动评审。
