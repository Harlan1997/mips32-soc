# ASIC DDR 输入获取计划

> 版本：v0.1（2026-08-01）  
> 路线：**ASIC**  
> 当前状态：**ASIC_SELECTED / DDR_ENTRY_BLOCKED**

本文把 ASIC 目标与 DDR3 controller/PHY 的外部依赖分开管理。ASIC 路线
已经确定，但在工艺、foundry、封装/板卡和 PHY/IP 选型落定前，不允许把
`axi_ddr_behavioral` 或 FPGA MIG/EMIF 证据升级为商用 DDR 证据，也不允许
开始无输入约束的 `ddr3_ctrl` RTL 实现。

## 1. ASIC 目标输入

| ID | 输入 | 当前状态 | 关闭证据 | owner |
|---|---|---|---|---|
| `ASIC-DDR-01` | 工艺节点、foundry、PDK/标准单元版本 | **MISSING** | 项目目标和 foundry/PDK 版本登记，含 NDA/访问责任人 | SoC/实现 |
| `ASIC-DDR-02` | 封装、DDR IO 电压、温度等级和板卡目标 | **MISSING** | package/IO/温度约束与单 rank x32 拓扑签收 | 封装/板级 |
| `ASIC-DDR-03` | foundry-approved 或商用 PHY/IP 候选 | **MISSING** | vendor、release、license entitlement、交付包路径和 SHA256 | memory/实现 |
| `ASIC-DDR-04` | DFI 3.1 port list、frequency ratio、训练语义 | **MISSING** | vendor port declaration、ratio、init/calibration 状态和 wrapper 假设 | memory/实现 |
| `ASIC-DDR-05` | 精确 DDR3 part、rank、width、density | **MISSING** | DRAM ordering code、datasheet 版本和 x32/single-rank 签收 | 板级 |
| `ASIC-DDR-06` | board timing/electrical/constraint 文件 | **MISSING** | trace length、CK/DQS/ODT、SI/PI、corner 和约束文件 hash | 板级/实现 |
| `ASIC-DDR-07` | 可运行真实 memory model 和仿真许可 | **MISSING** | model 版本/许可、init/refresh/timing/calibration 可执行日志 | 验证 |
| `ASIC-DDR-08` | PLL/reset/power-good 具体实现及 boot/WDT budget | **PARTIAL** | macro/时钟树、reset ownership、power-good 时序和 timeout 数值签收 | 时钟/系统 |

这些输入与 [`ddr_integration_inputs.md`](ddr_integration_inputs.md) 的
`DDR-IN-01..08` 一一对应；两份文档必须在同一 integration commit 更新。

## 2. 获取顺序

1. 由 SoC owner 固定本项目的工艺节点、foundry、封装、IO 电压、温度等级
   和目标 DDR3-1600 x32 单 rank 拓扑。
2. 向 foundry-approved catalog 以及 Synopsys/Cadence/Rambus 等 PHY 供应商
   发出 RFI/RFQ；确认支持该节点、封装和 DDR3 speed grade。
3. 在 NDA 和 license entitlement 生效后，索取完整交付包：DFI 3.1
   wrapper、port list/ratio、RTL/netlist、仿真模型、SVA/例程、时钟复位
   说明、综合/STA 约束和 APB/错误 ABI。
4. 以 PHY 支持列表反选具体 DRAM part 和板级拓扑，取得 memory datasheet、
   SI/PI/ODT/终端参数、trace/timing 文件及 corner 约束。
5. 获取供应商允许分发的真实 DDR3 model，建立无 preload 的 init、training、
   refresh、read/write、backpressure 和 failure 仿真入口。
6. 将每个交付物登记到输入 manifest：`path | version | SHA256 | license |
   owner | review date`。只有登记完整且 owner 签收，才允许把 entry audit
   从 `DDR_ENTRY_READY=0` 改为 `1`。

## 3. 硬门槛

- 缺少 `ASIC-DDR-01..06` 任一项：不锁定 PHY，不创建产品 wrapper。
- 缺少 `ASIC-DDR-07`：不宣称 controller block verification 完成。
- 缺少 `ASIC-DDR-08`：不定义 boot timeout/failure code，不运行产品 DDR boot gate。
- entry audit 通过只证明输入和接口一致；仍需 controller/PHY 的 init、
  calibration、refresh、错误路径、真实 memory model 和 no-preload boot gate。

## 4. 当前行动项

| 顺序 | 行动 | 产出 | 状态 |
|---|---|---|---|
| 1 | 提供工艺节点/foundry/封装/IO 电压/温度等级 | `ASIC-DDR-01..02` | **待项目决策** |
| 2 | 确认 PHY vendor/IP 候选并完成 NDA/RFQ | `ASIC-DDR-03..04` | **阻塞于 1** |
| 3 | 选定 DRAM part 和板卡约束 | `ASIC-DDR-05..06` | **阻塞于 2** |
| 4 | 取得 model、clock/reset 和 WDT budget | `ASIC-DDR-07..08` | **阻塞于 2/3** |
| 5 | 更新 manifest、运行 entry audit、评审 wrapper 变更集 | `DDR_ENTRY_READY=1` | **未开始** |

