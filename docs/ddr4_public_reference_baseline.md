# DDR4 公共资料与临时验证基线

> 版本：v0.1（2026-08-05）
> 状态：`PUBLIC_REFERENCE_COLLECTED / PROVISIONAL / DDR4_ENTRY_READY=0`

本文把无需 NDA 即可获得的 DDR4 公开资料整理成当前项目的协议与 RTL
仿真基线。它用于 controller RTL、接口审查和软件时序假设。

## 1. 目标配置

| 项目 | 临时值 | 状态 |
|---|---:|---|
| DRAM | DDR4 SDRAM，x32，single-rank，1.2 V | `PROVISIONAL` |
| speed bin | DDR4-2133 / 1066 MHz，`tCK=0.9375 ns` | `PROVISIONAL` |
| 温度 | commercial，0..85 C | `PROVISIONAL` |
| ECC | disabled | 当前 C1 假设 |
| AXI data path | 32-bit，aligned INCR，1..16 beats | 当前 SoC contract |
| memory model | `rtl/perips/axi_ddr_model.v` + `rtl/perips/ddr4_phy_behavioral.v` | simulation reference |

DDR4-2133 是当前 controller 仿真的代表性速度档。不同 density、speed bin、
temperature 和 ordering code 可通过参数 profile 扩展。

## 2. 公开资料摘录

下表只摘录公开 datasheet/标准中用于 controller 预研的通用字段。数值是
DDR4-2133 的代表性初始值；不同密度、speed bin、温度和厂商 ordering code
可能不同，不能替代目标颗粒 datasheet 的最终 AC table。

| 参数 | 临时值 | 用途 |
|---|---:|---|
| `tCK(min)` | 0.9375 ns | 2133 MT/s 时钟周期 |
| `tRCD` | 13.75 ns | ACTIVATE 到 READ/WRITE |
| `tRP` | 13.75 ns | PRECHARGE 时间 |
| `tRAS(min)` | 32 ns | 行 active 最短时间 |
| `tRC(min)` | 45.75 ns | 行周期下限，按 `tRAS+tRP` 预估 |
| `tRFC` | 350 ns | 8 Gb 级别 refresh blocking 代表值 |
| `tREFI` | 7.8 us | normal-temperature refresh interval |
| `tFAW` | 21 ns | 4-bank activate window 代表值 |
| CL/CWL | CL15..16 / CWL12 | controller 参数 sweep 起点 |
| VDD/VDDQ | 1.2 V nominal | 仅 protocol/model 假设 |

`tRFC`、CL/CWL、ODT/Rtt、地址映射和训练相关参数必须在选定 ordering code
后替换为该颗粒的 speed-bin table。`tREFI` 还必须按温度等级和 self-refresh
策略重新确认。

## 3. WDT 与初始化临时预算

这是用于 RTL gate 的明确仿真假设：

| 阶段 | 临时预算 | 100 MHz controller clock 折算 |
|---|---:|---:|
| power-good/reset settle | 100 us | 10,000 cycles |
| JEDEC init command sequence | 200 us | 20,000 cycles |
| controller initialization/training abstraction | 5 ms | 500,000 cycles |
| retry budget | 2 次 | 每次重新进入 bounded init |
| boot WDT timeout | 20 ms | 2,000,000 cycles |

临时 gate 的要求是：init/training 成功或失败必须在 20 ms 内产生确定状态；
失败必须置位 sticky error、让 AXI 请求以 bounded `SLVERR` 完成，并允许 WDT
复位和 boot-status 保留。

## 4. 项目内模型映射

当前公开资料基线映射到已有模型如下：

- `rtl/perips/ddr4_phy_behavioral.v`：抽象 init、training、refresh、读写、
  backpressure 和 fatal/error；其 `INIT_CYCLES=4`、`TRAIN_CYCLES=4`、
  `REFRESH_CYCLES=3` 是仿真抽象 cycle。
- `rtl/perips/axi_ddr_model.v`：AXI memory、随机 backpressure 和周期性
  refresh stall；不模拟 DQ/DQS、CA timing、ODT、校准或电气行为。
- `rtl/perips/apb_ddr4_status.v`：软件可见的 controller/init/training/
  fatal/error status 和 W1C contract。

因此当前模型用于验证 controller-facing behavior、错误恢复和协议时序假设。

## 5. 公开来源登记

| 来源 | 内容 | 当前用途 | 状态 |
|---|---|---|---|
| [JEDEC DDR4 SDRAM standard page](https://www.jedec.org/standards-documents/focus/DRAM) | DDR4 命令、模式寄存器和标准入口 | 协议字段核对 | 公共索引；2026-08-05 自动访问返回 403，具体标准版本待项目获取 |
| [Micron DRAM technical documentation](https://www.micron.com/products/memory/dram-components/ddr4-sdram) | DDR4 datasheet、speed bin、timing 和 model 入口 | 2133 参数预筛选 | 官方入口已核验 HTTP 200（2026-08-05）；目标 ordering code 待选 |
| [Samsung semiconductor DRAM](https://semiconductor.samsung.com/dram/ddr/ddr4/) | DDR4 产品和 datasheet 入口 | 候选颗粒交叉检查 | 官方入口已核验 HTTP 200（2026-08-05）；目标 ordering code 待选 |
| [ISSI DDR4 SDRAM](https://www.issi.com/DDR4) | DDR4 产品、datasheet 和 model 入口 | 兼容替代料调研 | 官方入口已核验 HTTP 200（2026-08-05）；具体 part 待 PHY 支持列表确认 |
| [Micron DDR4 technical note index](https://www.micron.com/support/technical-documents) | DDR4 training、初始化和应用说明入口 | controller 初始化参考 | 官方公开索引；版本需随选型冻结 |

### 5.1 可下载的公开 RTL/model 参考

| 公开项目 | 固定版本 | 获取内容 | 许可/结论 |
|---|---|---|---|
| [KMKTR/DDR4-Memory-Model](https://github.com/KMKTR/DDR4-Memory-Model) | `7d39cb45caa75dd7f00b867b860ea0d9dadf4925`（2025-07-05） | `ddr4rtl.sv`、`dfiinterface.sv`、`mem_controller.sv`、`top.sv`，包含 MRS、ACT/READ/WRITE/PRECHARGE、burst 和简化 CAS latency | GitHub API 未声明 license；只能作为公开参考，不能直接 vendoring 或作为产品证据 |
| [bhunt2/DDR4Sim](https://github.com/bhunt2/DDR4Sim) | `636b8611cad3dbbf468f6895ca547086146bd547`（2014-08-18） | SystemVerilog DDR4 simulation project、设计/研究资料和 `ProjectPkg.zip` | GitHub API 未声明 license；只能作为公开参考，不能直接 vendoring |

上述项目已实际读取 README 和主要 RTL 文件，并固定了 commit；本仓库不复制其
无明确许可的代码。当前项目继续使用自有的
`rtl/perips/ddr4_phy_behavioral.v` 和 `rtl/perips/axi_ddr_model.v`，公开项目只
用于核对命令流程、DFI 命名和模型边界。

项目没有复制厂商 PDF、仿真 model 或受许可约束的 PHY 文件；接收正式资料后
应登记 `path | version | SHA256 | license | owner | review date`。

## 6. 结论与下一步

本资料包已经解除“没有公开预研参数”的问题，可直接支持当前
`RTL_FUNCTIONAL_SIM_READY` 范围；不涉及产品 PHY、封装、板级或其他物理实现入口。

公开资料实际支持的是：DDR4 协议、代表性 timing、controller/model、错误分类
和临时 boot/WDT 仿真假设。

当前仅维护 RTL/model 参数 profile，并持续运行 init/training/refresh/no-preload
等功能仿真 gate。
