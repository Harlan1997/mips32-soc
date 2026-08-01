# ASIC C1 DDR4 参数决策包

> 版本：v0.1（2026-08-02）
> 阶段：**A：参数决策**
> 状态：**IN_PROGRESS / B_PHY_SELECTION_BLOCKED**

本文件用于在进入 PHY 供应商筛选前签收工艺、封装、板级和 DDR4 运行参数。
表中的“建议基线”是推进用默认值，不是 foundry 或 PHY 支持证据；最终值
必须由项目 owner 和供应商交付物签收后写入
[`docs/ddr4_integration_inputs.md`](ddr4_integration_inputs.md)。

## 1. 必须决策的参数

| ID | 决策项 | 可选值 | 建议基线 | 状态 |
|---|---|---|---|---|
| `A-DDR4-01` | 工艺档位 | 28nm LP；22/16nm；其他有 DDR4 PHY 的节点 | 28nm LP | **待确认** |
| `A-DDR4-02` | foundry/PDK | TSMC N28/28HPC、Samsung 28nm、GF 22FDX 或其他；均须核对 PHY catalog | 与目标 PHY 配套的 foundry | **待确认** |
| `A-DDR4-03` | 封装/板级拓扑 | 带 DDR IO 的 BGA；PoP；其他 | BGA、板载 x32、single-rank | **待确认** |
| `A-DDR4-04` | DDR4 IO/温度 | DDR4 nominal 1.2 V；commercial 0..85 C；industrial -40..105 C | 1.2 V、commercial | **待确认** |
| `A-DDR4-05` | DDR4 speed grade | 1600/1866/2133/2400/3200 MT/s | DDR4-2133，2400 作为性能选项 | **待确认** |
| `A-DDR4-06` | DRAM 拓扑 | x32 single-rank；x16 多颗；多 rank | x32 single-rank | **已由 C1 选择** |
| `A-DDR4-07` | ECC | 关闭；SECDED；端到端 ECC | 首版关闭，单独保留扩展点 | **待确认** |
| `A-DDR4-08` | controller/PHY 时钟 | vendor ratio；PHY CK 由 speed grade 推导 | 由 PHY/PLL 交付物确定 | **待确认** |
| `A-DDR4-09` | boot/WDT budget | 由 PHY training worst-case 和系统 boot 预算确定 | 暂不假设数值 | **待确认** |

## 2. 选择规则

1. `A-DDR4-01..02` 必须先于 PHY RFQ 完成；不能先选一个与 foundry/PDK
   不匹配的 PHY。
2. `A-DDR4-03..05` 必须与 PHY supported-part list、IO library 和 board
   SI/PI 约束一致；建议基线不是自动批准值。
3. 若选择 industrial 温度、DDR4-2400 以上或 ECC，必须重新评估 PHY、封装、
   WDT timeout 和验证矩阵，不能沿用默认预算。
4. `A-DDR4-06` 是当前 C1 架构固定项；若改变 rank/width，需要重新做 AXI
   address mapping、容量和 boot contract review。

## 3. 阶段退出条件

阶段 A 只有在 `A-DDR4-01..09` 有 owner、版本/来源和签收记录后才关闭。
关闭后进入阶段 B：按工艺/foundry/package/速度约束筛选 PHY vendor/IP，取得
DFI port list、训练语义、模型、license 和约束文件。阶段 A 未关闭时，
`DDR4_ENTRY_READY` 必须保持 `0`，不得创建产品 PHY wrapper 或 controller RTL。
