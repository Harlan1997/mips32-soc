# L2 统一缓存微架构规格 (v1.2)

> 状态：v1.2 Phase 4F 已闭环商业基线。DUT 默认（`SOC_L2_CACHING=1`）实例化
> **write-through / no-write-allocate** 实现 `rtl/cache/l2_cache_wt.v`：128 KB 8-way，
> 缓存读命中，所有写立即透传到下游 SRAM（L2 不持有 dirty 状态）。这是 SoC 级默认，
> 因为 TB 会在运行中脉冲异步全局 `rst_n`（JTAG reset-recovery 覆盖），write-back 会在
> 写回前被复位清掉 dirty 行而静默丢失 SRAM-alias 写；write-through 立即透传写，复位无损。
>
> **write-back / write-allocate** 实现 `rtl/cache/l2_cache_caching.v`（128 KB 8-way WB/WA
> NINE、PLRU、dirty eviction）保留在 `SOC_L2_WRITEBACK` 开关之后（默认关闭）。它同样是
> **复位安全**的：tag/data/valid/dirty/PLRU 阵列为 retention memory（仅冷启动 `initial`
> 初始化，warm `rst_n` 脉冲不清），与 SoC SRAM 模型 `axi_sram.v` 一致，因此复位前写入的
> dirty 行在复位后仍在（且为权威副本），提交写不会丢失、复位后读命中 L2 而非从下游 refill
> 陈旧数据。块级单元门槛（`tb/unit/l2/tb_l2.v` 的 19 项 WB 合同，含 Test 19 warm-reset
> 保持）显式用 `+define+SOC_L2_WRITEBACK` 编译；write-through 路径（含三处 WT 修复）由
> `tb/unit/l2/tb_l2_wt.v` 与 SoC 级回归验证。（silicon 注意：真实 valid 位在真正冷启动需
> power-on reset 做 flash-invalidate；行为模型用 `initial` 块承担该职责。）
> **write-back 已于 v1.4 完成 SoC 级签核**（构建开关 `L2_WRITEBACK=1`，详见版本记录）。
>
> 两种实现均为 blocking single-outstanding：对齐 word-INCR 突发（含跨 line，逐 beat
> 重新查表）正确服务，仅对真正非法请求（非 32 位、非对齐、非 INCR、len>7）返回 `SLVERR`。
> 完整验收序列通过（unit gate 5/5、`l2_cpu` 固件门槛、默认 `make uvm`
> soc_bus_stress_test 0 UVM_ERROR / 0 SB_RESP、soc_test run.sh、`git diff --check`）。
> MSHR、WB buffer、coherent snoop、ECC 标为后续 4G+ 商用增强项。

---

## 0. 目标

- **容量**：128 KB (可参数化 128/256/512 KB)
- **组织**：8-way 组相联，pseudo-LRU
- **行大小**：32 B
- **PIPT**（无 alias 顾虑）
- **策略**：
  - DUT 默认 `l2_cache_wt`：**Write-Through + No-Write-Allocate + NINE**（复位安全）
  - `SOC_L2_WRITEBACK` 可选 `l2_cache_caching`：**Write-Back + Write-Allocate + NINE**
- **阻塞模型**：当前合同为 single-outstanding blocking L2（两实现相同）
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
`define SOC_L2_MSHR           0           // 当前基线：blocking / single outstanding
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

- 默认基线（`l2_cache_wt` / `l2_cache_caching`）不实现 MSHR，为 blocking single-
  outstanding。
- **非阻塞增强已交付**：`rtl/cache/l2_cache_nb.v`（`+define+SOC_L2_NONBLOCKING`）实现
  8-entry MSHR，支持 hit-under-miss、miss-under-miss、同 line secondary-miss 合并、跨-id
  乱序响应（同 id 保序）；MSHR/order-queue 满则反压上游（拉低 s_arready/s_awready）。
  下游 master 口保持单-outstanding（遵守 fabric 合同）。正确性以「in-order accept 为数据
  阵列唯一序列化点 + 乱序 responder 只读 per-entry 缓冲」保证，消除 eviction/fill 竞争。
- 单元证明：`tb/unit/l2nb`（multi-outstanding master + 记分板 + 下游单-outstanding 断言，
  peak_mshr=8、hit_under_miss_beats=26）。SoC 层 L1 仍阻塞，故为正确 drop-in、无 perf delta，
  并发收益待 CPU/L1 hit-under-miss。

### 2.3 Write Back Buffer

- 当前基线在阻塞 FSM 内直接完成 dirty victim writeback。
- 后续商用增强目标：4-entry write-back buffer，支持 eviction 与 refill 解耦。

### 2.4 FSM

```
ST_IDLE
ST_LOOKUP       → 查 tag/valid
ST_HIT_R        → 命中读
ST_HIT_W        → 命中写 + dirty
ST_MISS_ALLOC   → 分配 way, 检查 dirty → evict
ST_EVICT_AW/W/B → dirty way → downstream AXI writeback
ST_REFILL_AR    → 发 DDR 读
ST_REFILL_DATA  → 收 8 beat
ST_UPDATE       → 更新 tag/data/LRU
ST_ERR_RESP_*   → downstream RRESP/BRESP 错误向上游传播
```

---

## 3. AXI 端口

### 3.1 Slave 端 (from L1s)

- 单端口 AXI4 slave
- 接受 L1 I-cache 与 L1 D-cache 的 refill + eviction
- 由 fabric 侧 arbitrate 两个 L1 master 到此单端口（fabric 责任）
- 当前支持 aligned 32-bit INCR burst，长度不超过一条 32 B cache line。
- 当前不支持多 outstanding；后续 MSHR/fabric 合同扩展后再开放。

### 3.2 Master 端 (to DDR/DDR ctrl)

- 单端口 AXI4 master
- 8-beat burst refill + eviction
- 当前 single-outstanding。Dirty eviction 和 refill 通过阻塞 FSM 串行完成。

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
  2. 选 way (pseudo-LRU); 若 dirty → FSM → ST_EVICT_AW/W/B
     - 以 8-beat burst 写回 downstream
  3. FSM → ST_REFILL_AR: AXI AR 到 DDR (ARLEN=7)
  4. FSM → ST_REFILL_DATA: 收 8 beat
     - 若 RRESP=SLVERR/DECERR → 不安装 valid line，并向上游返回错误响应
     - 若 dirty eviction BRESP=SLVERR/DECERR → 保留 dirty victim，不覆盖 line，并向上游返回错误响应
  5. FSM → ST_UPDATE: 写 tag/data/valid=1/dirty=0/LRU
  6. 响应 L1 请求（forward critical word first 可选优化）
  7. FSM → ST_IDLE
```

---

## 6. Reset / Flush

- **冷启动（cold boot）**：`initial` 块置 valid=0, dirty=0, PLRU=0。行为模型用
  `initial` 承担；silicon 需 power-on reset flash-invalidate valid 位。
- **warm `rst_n` 脉冲**：仅复位 FSM 控制状态（state=IDLE、beat/fill/evict 计数、
  latched 请求）。tag/data/valid/dirty/PLRU 阵列为 retention memory，**不清**，与
  `axi_sram.v` 一致——故 write-back 复位安全，dirty 行跨复位保留。
- 无 pipeline flush 概念（L2 与 CPU 流水线解耦）。
- 若 L1 发 CACHE Hit_Writeback_Invalidate → 该行 dirty 数据经由正常 L1→L2 WB 路径进 L2；L2 保留副本。

---

## 7. 参数化开关

实现选择（编译期，`rtl/cache/l2_cache.v` 顶层 wrapper）：

```verilog
`define SOC_L2_CACHING      1       // 1 → 启用真实缓存；0 → 纯 pass-through (AXI 直通)
`define SOC_L2_WRITEBACK            // 定义 → write-back/write-allocate (l2_cache_caching.v)
                                     // 未定义（默认）→ write-through/no-write-allocate (l2_cache_wt.v)
```

- `SOC_L2_CACHING=1` 且未定义 `SOC_L2_WRITEBACK`（**DUT 默认**）→ `l2_cache_wt`。
- `SOC_L2_CACHING=1` 且定义 `SOC_L2_WRITEBACK` → `l2_cache_caching`。
- 未定义 `SOC_L2_CACHING` → 纯 pass-through。

未来扩展开关：

```verilog
`define SOC_L2_ENABLE       1       // 0 → 旁路 L2，L1 直接对接 DDR (面积 gate)
`define SOC_L2_INCLUSIVE    0       // 0 = NINE, 1 = strictly inclusive (Phase 后)
`define SOC_L2_CRITICAL_WORD_FIRST 1
`define SOC_L2_PREFETCH     0       // Phase 后期 next-line prefetch
```

### 7.1 Write-Through 默认实现 (`l2_cache_wt`)

- 读命中缓存；读缺失整行 refill（`WORDS_PER_LN` beats），再从缓存服务。
- 每次写立即透传下游 SRAM（no-write-allocate、无 dirty 位），复位不丢已提交写。
- 已修复三处 WT 缺陷（见版本记录 v1.2），由 `tb/unit/l2/tb_l2_wt.v` 覆盖：
  1. 多 beat 写只发一次 AW（`m_aw_sent` 保护），避免下游 slave 死锁。
  2. 读缺失 refill 整条对齐 line，避免未取字命中返回 stale 0。
  3. 跨 line 读突发逐 beat 以 `beat_addr` 重新查表/中途 refill。

---

## 8. 接口

```verilog
module l2_cache #(
    parameter SIZE_BYTES = 131072,
    parameter WAYS       = 8,
    parameter LINE_BYTES = 32
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
- Dirty eviction 阻塞写回压测。
- 后续 MSHR 满 stall + 同 line 合并。
- LRU 9-way rotation。
- SLVERR/DECERR 从 DDR 传播到 L1。
- 两 L1 master 并发当前由 fabric/single-outstanding 合同约束；内部 arbiter/MSHR 为后续增强。
- Snoop 端口 tie-off 无副作用（发 snoop req 不影响 hit/miss FSM）。
- Reset + 首次 miss 完整链路。

**SVA**：
- 命中唯一。
- Dirty line 被替换必先 WB。
- 当前 single-outstanding 不重入；后续 MSHR 数 ≤ 8。
- AXI master 侧协议合规（bind checker）。
- Inclusive/NINE 策略断言：L2 valid 状态与 L1 请求响应一致。

**Formal**：
- L2 miss FSM 无死锁 (bounded 64 cycles)。
- Dirty eviction 与 refill 无死锁（依赖 AXI slave 端 ready）。
- LRU 更新等价软件模型。

**性能门槛**：
- CoreMark：L2 hit rate ≥ 80%（L1 miss 的 80% 在 L2 命中）。
- 冷启动 refill 到 L1 CWF 优化命中时 latency ≤ (L2 lookup 3 + DDR RTT 20 + L1 fill 8) cycles。

---

## 10. 未来扩展

- **MSHR + WB buffer**：8-entry MSHR、4-entry writeback buffer、同 line 合并。
- **Prefetch**：next-line、stride、临近 SW-hint（Phase 后期）
- **Inclusive/Directory + Snoop**：多核前提
- **QoS-aware 分配**：per-master way partition
- **ECC**：per-word / per-line SECDED（Phase 后期，与 DDR ECC 联动）

---

## 版本记录

- v1.5 (2026-07-30)：Phase C.2 交付非阻塞 full-MSHR L2（`rtl/cache/l2_cache_nb.v`，
  `+define+SOC_L2_NONBLOCKING`）：8-entry MSHR、hit-under-miss、miss-under-miss、
  同 line secondary-miss 合并、跨-id 乱序响应（同 id 保序）、下游单-outstanding。新增
  `tb/unit/l2nb/tb_l2nb.v`（multi-outstanding master + 记分板 + 下游单-outstanding 断言
  + 并发证明 peak_mshr=8 / hit_under_miss_beats=26），并入 dut-block-unit-gate（7/7）。
  SoC drop-in smoke green（`L2_NONBLOCKING=1 make soc-smoke`）。默认 WT / WB 实现与行为
  不变；因 SoC L1 仍阻塞，为正确 drop-in、无 perf delta。详见 §2.2。
- v1.4 (2026-07-29)：write-back 完成 **SoC 级签核**（此前仅块级）。新增可选构建开关
  `L2_WRITEBACK=1`（`run_uvm.sh`/`run_testlist.sh`/`run_regression.sh`/`tb/soc_test/run.sh`
  与 Makefile `uvm`/`phase3-complete`/`soc-smoke` 目标），置位时向 vcs 追加
  `+define+SOC_L2_WRITEBACK`；默认不变（write-through）。此前顾虑"scoreboard 以 SRAM 为
  权威、write-back 延迟写回会破坏它"经核查不成立：scoreboard（`tb/uvm_tb/env/soc_scoreboard.sv`）
  的 SRAM 内容模型完全构建在 **L2 上游** 的 AXI tap（external master 口做内容
  `update_sram_model`/`check_sram_read_data`；fabric `s0` 做响应/DMA），从不读物理 SRAM；
  L2 是所有 master 汇聚的单一 coherence 点且读命中返回 dirty 数据，故上游模型与 L2 何时下刷
  无关，无需改 scoreboard。以 `L2_WRITEBACK=1` 验证：phase3-complete PASS、`soc_bus_stress_test`
  0 UVM_ERROR/0 UVM_FATAL、soc-smoke PASS，且 phase2 定向 16 项全 PASS（关键含
  `soc_jtag_reset_recovery_test`——即注入 async `rst_n` 脉冲、直接验证复位安全修复的用例）。
- v1.3 (2026-07-29)：write-back 实现 `l2_cache_caching.v` 现为复位安全。原先在 async
  `rst_n` 分支清 valid/dirty/PLRU 阵列，warm 复位脉冲会在写回前丢弃 committed dirty 行。
  改为：阵列为 retention memory（冷启动 `initial` 初始化，warm `rst_n` 不清），仅 FSM 控制
  状态随 `rst_n` 复位——与 `rtl/perips/axi_sram.v` retention 语义对称。这消除了 DUT 选用
  write-back 时的静默丢写隐患。`tb/unit/l2/tb_l2.v` 新增 Test 19（写 dirty 行 → 脉冲
  `rst_n` → 读回，必须 L2 命中返回原值且无下游 refill）。验证：`dut-block-unit-gate` 5/5
  （L2 19/19 with `+define+SOC_L2_WRITEBACK`），write-through `tb_l2_wt.v` 仍 `WT_TEST_SUCCESS`。
- v1.2 (2026-07-29)：DUT 默认缓存实现切换为 write-through / no-write-allocate
  (`rtl/cache/l2_cache_wt.v`)。原因：TB 在运行中脉冲异步全局 `rst_n`（JTAG
  reset-recovery 覆盖），write-back L2 会在写回前被复位清掉 dirty 行而静默丢失
  SRAM-alias 写（`soc_axi_attribute_cross_sweep_test` 读回 0）。write-through 立即
  透传写，复位无损。write-back/write-allocate (`l2_cache_caching.v`) 保留在
  `SOC_L2_WRITEBACK` 开关之后（默认关闭）。闭环期间修复三处 WT 缺陷：多 beat 写重复
  发 AW 死锁、读缺失部分行 refill 返回 stale 0、跨 line 读突发未逐 beat 重查表。
  端到端验证通过：phase3 完成门槛（8 directed×2 no-cov + coverage、必需覆盖组 100%、
  CPU/CP0 固件门槛）、DUT block unit gate、0 UVM error/fatal。
- v1.1 (2026-07-28)：Phase 4F 已闭环商业基线：128 KB 8-way WB/WA NINE，
  single-outstanding 阻塞响应，caching FSM 逐 beat 重新查表正确服务对齐 word-INCR
  突发（含跨 line），仅对真正非法请求（非对齐、非 32 位、非 INCR、len>7）返回
  SLVERR，下游 refill/eviction 错误传播与脏行保护，16 项单元门槛与 `l2_cpu` 固件
  门槛通过。闭环期间修复两处缺陷：移除 `l2_cache_caching` FSM 中每拍无条件
  `$display`；修正 `tb_l2.v` `cache_write_raw` 中导致跨 line 写突发挂死的 WLAST
  采样/驱动竞态（DUT FSM 本身跨 line 行为正确，先前报告的 `SB_RESP` 回归在当前
  代码树不复现）。
- v1 (2026-07-27)：更新为当前 DUT 已启用基线：128 KB 8-way WB/WA
  NINE，blocking single-outstanding，dirty eviction/refill/error propagation，
  snoop tie-off。MSHR、WB buffer、coherent snoop、ECC 标为后续商用增强项。
- v0 (2026-07-26)：初版规格，128 KB 8-way NINE + 8 MSHR + 4 WB buffer + snoop 预留。等待 Phase C 启动评审。
