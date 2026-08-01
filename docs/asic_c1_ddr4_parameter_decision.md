# ASIC C1 DDR4 参数决策包

> 版本：v0.2（2026-08-02）
> 阶段：**A：参数决策**
> 状态：**BASELINE_ACCEPTED / A-02-A-09_OPEN / B_RFQ_PREPARATION**

本文件用于在进入 PHY 供应商筛选前签收工艺、封装、板级和 DDR4 运行参数。
表中的“建议基线”是推进用默认值，不是 foundry 或 PHY 支持证据；最终值
必须由项目 owner 和供应商交付物签收后写入
[`docs/ddr4_integration_inputs.md`](ddr4_integration_inputs.md)。

## 1. 必须决策的参数

| ID | 决策项 | 可选值 | 建议基线 | 状态 |
|---|---|---|---|---|
| `A-DDR4-01` | 工艺档位 | 28nm LP；22/16nm；其他有 DDR4 PHY 的节点 | 28nm LP | **BASELINE ACCEPTED** |
| `A-DDR4-02` | foundry/PDK | TSMC N28/28HPC、Samsung 28nm、GF 22FDX 或其他；均须核对 PHY catalog | TSMC N28/28HPC 为 RFQ 首选，其他为备选 | **外部确认待定** |
| `A-DDR4-03` | 封装/板级拓扑 | 带 DDR IO 的 BGA；PoP；其他 | BGA、板载 x32、single-rank | **BASELINE ACCEPTED** |
| `A-DDR4-04` | DDR4 IO/温度 | DDR4 nominal 1.2 V；commercial 0..85 C；industrial -40..105 C | 1.2 V、commercial | **BASELINE ACCEPTED** |
| `A-DDR4-05` | DDR4 speed grade | 1600/1866/2133/2400/3200 MT/s | DDR4-2133，2400 作为性能选项 | **BASELINE ACCEPTED** |
| `A-DDR4-06` | DRAM 拓扑 | x32 single-rank；x16 多颗；多 rank | x32 single-rank | **已由 C1 选择** |
| `A-DDR4-07` | ECC | 关闭；SECDED；端到端 ECC | 首版关闭，单独保留扩展点 | **BASELINE ACCEPTED** |
| `A-DDR4-08` | controller/PHY 时钟 | vendor ratio；PHY CK 由 speed grade 推导 | 由 PHY/PLL 交付物确定 | **待确认** |
| `A-DDR4-09` | boot/WDT budget | 由 PHY training worst-case 和系统 boot 预算确定 | 暂不假设数值 | **外部确认待定** |

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

推荐基线已接受；阶段 A 仍需关闭 `A-DDR4-02` 的 foundry/PDK/IO 书面确认和
`A-DDR4-09` 的训练/WDT 数值。阶段 B 已进入 RFQ 准备，筛选规则见
[`docs/asic_c1_ddr4_phy_selection_plan.md`](asic_c1_ddr4_phy_selection_plan.md)。
在外部签收完成前，`DDR4_ENTRY_READY` 必须保持 `0`，不得创建产品 PHY
wrapper 或 controller RTL。
