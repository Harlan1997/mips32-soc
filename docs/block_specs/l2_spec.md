# L2 统一缓存微架构规格 (v0)

> 状态：v0 草案。作为 Phase C **新增 `rtl/cache/l2_cache.v`** 的实施基线。当前 SoC 无 L2；新增以吸收 L1 miss、降低外存访问延迟、为将来多核 snoop 预留接口。

---

## 0. 目标

- **容量**：128 KB (可参数化 128/256/512 KB)
- **组织**：8-way 组相联，pseudo-LRU
- **行大小**：32 B（与 L1 相同，简化）或 64 B（可选，Phase C 后期评估）
- **PIPT**（无 alias 顾虑）
- **策略**：Write-Back + Write-Allocate + Inclusive w.r.t. L1
- **非阻塞**：8 MSHR
- **单口 AXI slave**（L1 侧汇聚）+ 单口 AXI master（DDR/存储侧）
- **Snoop 端口**：Phase C **预留但不实现**（tie off）
- **CACHE 指令穿透**：L1 CACHE 指令的 Index/Hit ops 需要透传或在 L2 层重放，Phase C 决策：L2 不响应 CACHE 指令，只被动接受 refill / eviction。

---

## 1. 参数

```verilog
`define SOC_L2_SIZE           131072      // 128 KB
`define SOC_L2_WAYS           8
`define SOC_L2_LINE_BYTES     32
`define SOC_L2_INDEX_BITS     9           // 128K / 8 / 32 = 512 sets
`define SOC_L2_OFFSET_BITS    5
`define SOC_L2_MSHR           8
`define SOC_L2_TAG_BITS       (32 - 9 - 5)  // 18
```

**地址分解**（PA）：

| 31 : 14 | 13 : 5 | 4 : 2 | 1 : 0 |
|:-:|:-:|:-:|:-:|
| Tag (18) | Index (9) | Word (3) | Byte (2) |

---

## 2. 结构

### 2.1 阵列

- **Data RAM**：8 way × 512 set × 32 B = 128 KB
  - 综合成 SRAM macro；面积紧张时可改 4 way × 1024 set
- **Tag RAM**：8 way × 512 set × (tag=18 + valid=1 + dirty=1) = 20 bit
- **LRU RAM**：512 set × 7 bit (8-way pseudo-LRU tree)
- **Inclusion 位**（可选，为将来 snoop 反向失效 L1）：per line 2 bit (L1I/L1D 存在指示)。Phase C 先不实现，为简化 non-inclusive。

### 2.2 MSHR

- 8 entries
- 每 entry：{addr line, tag, mshr_type, requestor_id (源 L1), pending_ops}
- 同 line 多请求合并

### 2.3 Write Back Buffer

- 4 entries
- 存储被驱逐的 dirty line，异步写 DDR
- 满则 stall eviction

### 2.4 FSM

```
ST_IDLE
ST_LOOKUP       → 查 tag/valid
ST_HIT_R        → 命中读
ST_HIT_W        → 命中写 + dirty
ST_MISS_ALLOC   → 分配 way, 检查 dirty → evict
ST_EVICT_WB     → dirty way → WB buffer (异步 AXI W)
ST_REFILL_AR    → 发 DDR 读
ST_REFILL_DATA  → 收 8 beat
ST_UPDATE       → 更新 tag/data/LRU
```

---

## 3. AXI 端口

### 3.1 Slave 端 (from L1s)

- 单端口 AXI4 slave
- 接受 L1 I-cache 与 L1 D-cache 的 refill + eviction
- 由 fabric 侧 arbitrate 两个 L1 master 到此单端口（fabric 责任）
- 或者：L2 内部 2 个 slave 端口 + 内部 arbiter（Phase C 决策：**内部 arbiter**，减轻 fabric 复杂度）
- 支持 8-beat burst、多 outstanding (up to MSHR count)

### 3.2 Master 端 (to DDR/DDR ctrl)

- 单端口 AXI4 master
- 8-beat burst refill + eviction
- 多 outstanding (up to WB buffer + MSHR)

### 3.3 Snoop 端口（预留 tie-off）

```verilog
// Phase C: unused, tied off
input  wire        snoop_req_valid,
input  wire [31:0] snoop_req_addr,
input  wire [1:0]  snoop_req_type,  // read/write/invalidate
output wire        snoop_req_ready, // tied 0
output wire        snoop_resp_valid,
output wire [1:0]  snoop_resp_state // I/S/E/M placeholder
```

将来多核 MP + coherency 启用时激活。

---

## 4. 一致性策略

**Phase C 决策：Non-Inclusive Non-Exclusive (NINE)**

- L1 refill 从 L2 拿 → L2 保留副本（typical inclusive-ish behavior）
- L2 eviction 不反向失效 L1（NINE）
- L1 eviction 若 dirty → 写回 L2 (WB) → L2 更新 line dirty=1
- 单核，L1 与 L2 不会有冲突副本

若将来多核 → 切换到 **Inclusive** 或加 **Directory** 追踪 L1 拥有权。

---

## 5. Miss 路径

```
On L2 miss:
  1. FSM → ST_MISS_ALLOC
  2. 选 way (LRU); 若 dirty → FSM → ST_EVICT_WB
     - 把 line 送 WB buffer
  3. FSM → ST_REFILL_AR: AXI AR 到 DDR (ARLEN=7)
  4. FSM → ST_REFILL_DATA: 收 8 beat
     - 若 RRESP=SLVERR/DECERR → 传回 L1 请求方的 DBE/IBE
  5. FSM → ST_UPDATE: 写 tag/data/valid=1/dirty=0/LRU
  6. 响应 L1 请求（forward critical word first 可选优化）
  7. FSM → ST_IDLE
```

---

## 6. Reset / Flush

- Reset：valid=0, dirty=0, LRU=0, MSHR 空, WB buffer 空, FSM=IDLE。
- 无 pipeline flush 概念（L2 与 CPU 流水线解耦）。
- 若 L1 发 CACHE Hit_Writeback_Invalidate → 该行 dirty 数据经由正常 L1→L2 WB 路径进 L2；L2 保留副本。

---

## 7. 参数化开关

```verilog
`define SOC_L2_ENABLE       1       // 0 → 旁路 L2，L1 直接对接 DDR (面积 gate)
`define SOC_L2_INCLUSIVE    0       // 0 = NINE, 1 = strictly inclusive (Phase 后)
`define SOC_L2_CRITICAL_WORD_FIRST 1
`define SOC_L2_PREFETCH     0       // Phase 后期 next-line prefetch
```

---

## 8. 接口

```verilog
module l2_cache #(
    parameter SIZE_BYTES = 131072,
    parameter WAYS       = 8,
    parameter LINE_BYTES = 32,
    parameter MSHR       = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 slave (from L1 arbiter or 2 L1 masters via internal arb)
    // ... 完整 AXI4 slave 端口 ...

    // AXI4 master (to DDR ctrl / memory)
    // ... 完整 AXI4 master 端口 ...

    // Snoop port (reserved, tied off Phase C)
    input  wire        snoop_req_valid,
    input  wire [31:0] snoop_req_addr,
    input  wire [1:0]  snoop_req_type,
    output wire        snoop_req_ready,
    output wire        snoop_resp_valid,
    output wire [1:0]  snoop_resp_state,

    // Perf counters (optional, Phase F)
    output wire [31:0] perf_hit_cnt,
    output wire [31:0] perf_miss_cnt,
    output wire [31:0] perf_wb_cnt
);
```

---

## 9. 验证要求

**块级** (`tb/uvm_tb/l2/`)：

- Hit/miss × 8 way × 512 set 抽样覆盖。
- Dirty eviction × WB buffer 深度压测。
- MSHR 满 stall + 同 line 合并。
- LRU 9-way rotation。
- SLVERR/DECERR 从 DDR 传播到 L1。
- 两 L1 master 并发 (I-cache refill + D-cache refill 同时) 通过内部 arbiter。
- Snoop 端口 tie-off 无副作用（发 snoop req 不影响 hit/miss FSM）。
- Reset + 首次 miss 完整链路。

**SVA**：
- 命中唯一。
- Dirty line 被替换必先 WB。
- MSHR 数 ≤ 8。
- AXI master 侧协议合规（bind checker）。
- Inclusive/NINE 策略断言：L2 valid 状态与 L1 请求响应一致。

**Formal**：
- L2 miss FSM 无死锁 (bounded 64 cycles)。
- WB buffer 与 refill 无死锁（依赖 AXI slave 端 ready）。
- LRU 更新等价软件模型。

**性能门槛**：
- CoreMark：L2 hit rate ≥ 80%（L1 miss 的 80% 在 L2 命中）。
- 冷启动 refill 到 L1 CWF 优化命中时 latency ≤ (L2 lookup 3 + DDR RTT 20 + L1 fill 8) cycles。

---

## 10. 未来扩展

- **Prefetch**：next-line、stride、临近 SW-hint（Phase 后期）
- **Inclusive + Snoop**：多核前提
- **QoS-aware 分配**：per-master way partition
- **ECC**：per-word / per-line SECDED（Phase 后期，与 DDR ECC 联动）

---

## 版本记录

- v0 (2026-07-26)：初版规格，128 KB 8-way NINE + 8 MSHR + 4 WB buffer + snoop 预留。等待 Phase C 启动评审。
