# ASIC 内存架构决策记录

> 版本：v0.1（2026-08-02）
> 决策：**Profile C 已选择**
> 状态：**需要在 C1/C2 中二选一，产品 memory entry blocked**

## 1. 决策含义

Profile C 表示采用 28nm 或更先进 ASIC 工艺，并切换到 DDR4 或 LPDDR4/4X
级别的商用 PHY。当前冻结的 `docs/block_specs/ddr3_spec.md` 只能保留为
DDR3 原型/行为模型契约，不能直接作为 Profile C 的产品内存契约。

现有 AXI fabric 地址窗口和 behavioral memory 测试仍可作为架构证据；它们
不证明 DDR4/LPDDR4 PHY、训练、校准、刷新、SI/PI 或真实板级启动。

## 2. 子选项

| 选项 | 产品内存 | 适用场景 | 主要代价 | 当前建议 |
|---|---|---|---|---|
| **C1** | DDR4，x32，single-rank，商用 DDR4 PHY | 标准板载 DDR、带宽优先 | IO/板级 SI 较复杂，功耗高于 LPDDR4 | **默认推荐** |
| **C2** | LPDDR4/LPDDR4X，x32，PoP/板载 | 移动/低功耗封装 | PHY、封装、训练和板级约束更专用 | 仅在明确低功耗/PoP 需求时选择 |

除非项目已经确定移动低功耗封装，否则选择 **C1 DDR4** 可以最大限度
复用现有 x32 AXI 主存架构，减少协议和板级变更。

## 3. Profile C 输入

| ID | 输入 | 状态 |
|---|---|---|
| `C-MEM-01` | C1 DDR4 或 C2 LPDDR4/4X | **待选择** |
| `C-MEM-02` | 工艺节点、foundry、PDK、IO library | **MISSING** |
| `C-MEM-03` | 封装、IO 电压、温度等级、板卡/PoP 拓扑 | **MISSING** |
| `C-MEM-04` | 对应代际的 foundry-approved PHY/IP、DFI 版本和 license | **MISSING** |
| `C-MEM-05` | DRAM part、rank、width、density、speed grade | **MISSING** |
| `C-MEM-06` | board/package SI/PI/timing/ODT 文件 | **MISSING** |
| `C-MEM-07` | 真实 memory model、训练/刷新仿真入口 | **MISSING** |
| `C-MEM-08` | PLL/reset/power-good 和 boot/WDT budget | **PARTIAL** |

## 4. 迁移门槛

1. 选定 `C-MEM-01` 后，复制并重写 DDR controller/PHY spec，明确 AXI、DFI、
   APB status/error ABI 和时钟复位语义；不得直接修改 DDR3 spec 冒充 DDR4。
2. 完成 `C-MEM-02..08` 的 artifact path、版本、SHA256、license、owner 和
   review sign-off 登记。
3. 通过新的 memory contract entry audit 后，才允许创建产品 PHY wrapper
   和 controller RTL。
4. 通过 init/training、refresh、error/backpressure、真实 model 和
   no-preload boot gate 后，才能将内存域升级为 `SOC_INTEGRATED`。

当前结论：Profile C 已选，但 `C-MEM-01..08` 未关闭，不能开始产品 DDR4/
LPDDR4 controller 实现。
