# AXI4 互联 (Fabric) 微架构规格 (v1)

> 状态：v1 已实现（Phase C.3 DELIVERED）。级联 2×1 arbiter + 1×3 decoder 已被真正的
> M×N crossbar `rtl/axi/axi_crossbar.v` 取代（旧 `axi_arbiter_2x1*.v` / `axi_decoder_1x3.v`
> 已删除），封装在 `soc_fabric.v`（扁平端口与 `ENABLE_EXT_AXI_MASTER` 参数不变）。
> 已交付：不同 slave 并发事务、per-slave QoS 优先 + RR 平局仲裁、per-slave outstanding
> FIFO {master_idx,id} 按序回路、合成 DECERR slave、AR/AW 授权锁保证地址通道 payload 稳定。
>
> **诚实范围**：per-slave `SOC_XBAR_N_OT=4` 深度在 crossbar 边界实现；端到端同-slave 深度
> 仍受当前单-outstanding L2/APB/flash 限制为 1（跨-slave 并发已实现，同-slave 吞吐待非阻塞
> slave / L2 MSHR）。QoS 为静态 per-master class（master 尚未输出 AxQOS）。无 formal 证明、
> 无商用 VIP compliance、无综合/时序/lint/CDC 收敛声明。验证：`make fabric-unit-gate` 3/3 +
> SoC 回归（phase2 16/16、phase3-complete、uvm、soc-smoke）全绿。详见 `docs/refactor_roadmap.md`
> "Phase C.3"。下文 §0 起为原始设计目标（v0）；未实现项（≥8 深度、动态 QoS、formal）为后续。

---

## 0. 目标

- **多 outstanding**：per-master 至少 4 未完成事务（可参数化 8/16）
- **乱序响应**：AXI ID tag 追踪，允许 slave 乱序返回，fabric 保序合并
- **Crossbar**：M×N 全连接 (M master, N slave)，非仲裁瓶颈
- **QoS 感知**：4-bit AXI QoS 影响 arbiter 优先级
- **PROT/CACHE 转发**：透明传递给 slave 无篡改
- **DECERR**：未映射地址自动产生 DECERR（decoder 内置 DECERR slave）
- **Deadlock free**：AR/R 与 AW/W/B 通道独立仲裁，无循环依赖
- **保留现有 subsystem 边界**：`soc_core_subsystem`、`soc_memory_subsystem`、`soc_peripheral_subsystem`、`soc_debug_subsystem` 接口不变，仅内部升级

---

## 1. 拓扑

### 1.1 Master

| ID | Master | 出处 |
|:-:|---|---|
| M0 | CPU I-cache | `soc_core_subsystem` |
| M1 | CPU D-cache | `soc_core_subsystem` |
| M2 | DMA         | `soc_peripheral_subsystem` |
| M3 | JTAG Debug  | `soc_debug_subsystem` |
| M4 | (预留) 外部 test master | verification only |

Phase C 后 L2 加入 → CPU I/D 先汇聚 → L2 → 单 master 上 fabric。此时 fabric 侧 masters 减少：

| ID (with L2) | Master |
|:-:|---|
| M0 | L2 (from CPU cluster) |
| M1 | DMA |
| M2 | JTAG Debug |

**Phase C 决策**：先做 L2 → fabric M0 单一（架构简化）；不加 L2 的备用配置 (`SOC_L2_ENABLE=0`) 保留 M0/M1 双端口。

### 1.2 Slave

| ID | Slave | 地址窗 |
|:-:|---|---|
| S0 | DDR / SRAM (memory subsystem) | 0x0000_0000 – 0x0FFF_FFFF + kseg alias |
| S1 | QSPI Flash | 0x1000_0000 – 0x1FFF_FFFF |
| S2 | APB Bridge (peripherals) | 0x4000_0000 – 0x4FFF_FFFF |
| S3 | Debug/Test | 0xE000_0000 – 0xEFFF_FFFF |
| SD | DECERR slave (auto) | 未映射区域 |

---

## 2. AXI ID 空间

- **AXI ID width**：4 bit (per SOC_AXI_ID_WIDTH)
- **Master ID 编码策略**：
  - fabric 内部把 master 编号 (2 bit) prepend 到 master 出的 ARID/AWID (2 bit)
  - 拼成 4-bit fabric-side ID = `{master_num[1:0], local_id[1:0]}`
  - Slave 端见到全 4-bit ID
  - Response 返回时按高 2 bit route 回对应 master，低 2 bit 保留 master 内部区分
- Master 内部 outstanding limit：4 (低 2 bit ID 用尽) 或按需扩展
- Fabric 内部 outstanding tracking：per (master × slave) 计数器 or 简单全局队列

---

## 3. Crossbar 结构

**5 通道各自独立**：

### 3.1 AR / R (读路径)

```
Master AR → Address Decoder → Slave AR (routed)
Master ← Response merge/order ← Slave R (multiple)
```

- AR 有 arbitration per slave（多 master 竞争同 slave）
- R 有 demux per master（response route by ID[3:2]）
- 支持乱序：不同 ID 的 R 可交错返回，同 ID 保序

### 3.2 AW / W / B (写路径)

```
Master AW → Decoder → Slave AW
Master W → routed to same slave as pending AW (per master AW-W ordering FIFO)
Master ← B merge ← Slave B
```

- AW 与 W 必须**保序**：一个 master 的 W beats 必须匹配其 AW 顺序
- 用 per-master AW-order FIFO 追踪去向 slave；W 到达时按 FIFO 头 route
- B 通道 demux by ID

### 3.3 Arbitration 策略

- **Round-robin** 保底公平
- **QoS override**：AR.qos / AW.qos 更高的优先
- **Age-based fallback**：等待周期数 > threshold → boost 优先级（避免饥饿）
- Phase C 默认：Round-robin + QoS 4-bit（0-15）；不做 age-based

---

## 4. Address Decoder

```verilog
function [2:0] decode_slave(input [31:0] addr);
    case (addr[31:28])
        4'h0, 4'h1 (low part):  // 0x0000_0000 - 0x1FFF_FFFF 需再细分
            if (addr[31:28] == 4'h0) return S0_DDR_SRAM;
            else                       return S1_QSPI;
        4'h4:                     return S2_APB;
        4'hA:                     return S0_DDR_SRAM;  // kseg1 alias
        4'hE:                     return S3_DEBUG;
        default:                  return SD_DECERR;
    endcase
endfunction
```

**决策**：地址解码用 `soc_config.vh` 宏，避免 magic number。补齐 `SOC_ADDR_NIBBLE_*` 常量。

---

## 5. QoS / PROT / CACHE 语义

- **QoS[3:0]**：只影响 arbitration，不改变协议
- **PROT[2:0]**：
  - [0] Privileged: 转发给 slave；某些 slave 可能拒绝 (SLVERR)
  - [1] Non-secure: 保留（Phase C 无 secure world），全 1
  - [2] Instruction: I-cache 读设为 1
- **CACHE[3:0]**：
  - Bufferable / Cacheable / Read/Write allocate hints
  - Fabric 不做优化决策，透传 slave；DDR ctrl / L2 可能利用

- **LOCK**：Phase C 不支持 exclusive access（EXOKAY 不返回）；LOCK=1 视为普通事务

---

## 6. DECERR Slave

- 内置 tiny FSM，对未映射地址返回：
  - AR → RRESP=DECERR，8 beat 全 0
  - AW → BRESP=DECERR，接收 W beats（吞没）
- 保证 master 不 hang

---

## 7. 多 outstanding 追踪

- Per master：outstanding AR / AW / W-beat count
- Fabric 内部：per (master, slave) pending count
- Backpressure：master AR/AW valid 拉低当 outstanding 到限

**Phase C 参数化**：

```verilog
`define SOC_FABRIC_MAX_OUTSTANDING  4   // per master
`define SOC_FABRIC_AXI_ID_WIDTH     4
`define SOC_FABRIC_MASTERS          3   // L2 / DMA / JTAG (or 4 without L2)
`define SOC_FABRIC_SLAVES           4   // DDR/QSPI/APB/DEBUG + DECERR
```

---

## 8. Deadlock 避免

- **AR 与 AW 通道独立**，无循环
- **B 通道优先级**：不能被 R 阻塞（分离 buffer）
- **DECERR slave 快速响应**，避免未映射事务堵塞
- **W-beat 顺序**：per-master AW FIFO 保证 W 按 AW 顺序 route，slave 不会等错 master 的 W

---

## 9. Reset / Flush

- Reset：所有 arbiter FSM = IDLE，所有 outstanding counter = 0，AW FIFO 清空
- 无 pipeline flush（fabric 与 CPU 流水线解耦）

---

## 10. 接口 (crossbar 顶层)

```verilog
module axi_crossbar #(
    parameter MASTERS = 3,
    parameter SLAVES  = 4,      // 不含 DECERR，DECERR 内置
    parameter ID_WIDTH = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MAX_OUTSTANDING = 4
)(
    input  wire clk,
    input  wire rst_n,

    // MASTERS × AXI4 slave 端 (fabric 视角)
    // ... 
    
    // SLAVES × AXI4 master 端 (fabric 视角)
    // ...
);
```

生成器可用 Chisel / SpinalHDL / Python 脚本；Phase C 决策：**手写 Verilog** 保持可读 + 逐 case 覆盖率。参数化 for-generate 展开 masters/slaves。

---

## 11. 验证要求

**块级** (`tb/uvm_tb/fabric/`)：

- 每 (master, slave) 组合读/写。
- Multi-outstanding：单 master 连发 4 AR，slave 乱序返回。
- ID 交错：同 master 不同 ID 事务并行。
- QoS 仲裁：高 QoS 优先。
- Round-robin 公平性：长期无饥饿。
- DECERR 覆盖：未映射地址、部分覆盖 nibble。
- AW-W 保序：多 master 混发 AW/W，验证 W 按 AW 顺序到 slave。
- Backpressure：outstanding 到限 → AR/AW valid 降。
- Slave 慢响应：ready 拉低导致 arbitration 停滞不 hang。
- Slave SLVERR/DECERR 传播到 master。

**SVA**（bind 至 crossbar）：

- AR handshake 后必收到对应 R 完成 (bounded)。
- AW handshake 后 W-beat count == AWLEN+1；然后收到 B。
- 同 ID R 保序。
- Outstanding count 不超参数。
- W 到达 slave 的顺序匹配同 master AW 顺序。
- 无 deadlock (bounded liveness proof)。

**Formal** (VC-Formal / JasperGold)：

- **Arbitration liveness**：任何 valid 请求最终会被服务（无饥饿证明）。
- **Deadlock freedom**：所有通道任意状态可到 IDLE (bounded 64 cycles)。
- **AW-W 保序**：per master 保序 assertion proven。
- **ID 保序**：同 ID R/B 保序 assertion proven。
- **地址路由正确**：地址 → slave 映射函数与 decoder 等价。

**AXI Compliance**：
- 复用现有 `tb/uvm_tb/checkers/axi_protocol_checker.sv`，扩展到多 outstanding 场景。
- 参考 ARM AMBA AXI4 Assertion PSL/SVA 库（或商用 VIP：ARM Cycle Model / Cadence AMBA VIP）。

**性能门槛**：
- 单 master 独占 slave 带宽 = slave 峰值。
- 双 master 竞争同 slave 公平分带宽 (±10%)。
- QoS 15 事务延迟 ≤ QoS 0 事务延迟 × 0.5 in contention。

---

## 12. 演进路径

- **Phase D**：加 DDR/QSPI/APB 真外设，验证 QoS 与外设带宽匹配。
- **Phase E**：跨时钟域端口（如 DDR clock domain）→ 每 slave/master 加 CDC async FIFO。
- **未来多核**：加 coherency 端口 + snoop network；从 crossbar 升级到 NoC (mesh / ring)。
- **安全**：per-master security tag，slave 端 firewall 检查。

---

## 版本记录

- v0 (2026-07-26)：初版规格，M×N crossbar + 多 outstanding + 乱序响应 + QoS 仲裁 + 内置 DECERR。等待 Phase C 启动评审。
