# ASIC C1 DDR4 PHY/IP 筛选计划

> 版本：v0.1（2026-08-02）
> 阶段：**B：PHY/IP 筛选准备**
> 状态：**RFQ_PREPARATION / PHY_NOT_SELECTED**

本计划在 C1 推荐基线已接受后启动。供应商和 foundry 仍未签约，以下名单
只是 RFQ 候选，不代表任何 vendor 已确认支持本项目工艺、封装或 DDR4
speed grade。

## 1. RFQ 候选池

| 候选 | 询价对象 | 必须核对 | 当前状态 |
|---|---|---|---|
| `PHY-CAND-01` | Synopsys DDR4 PHY / controller 组合 | 28nm LP、BGA、x32 single-rank、DDR4-2133/2400、DFI、model、license | **待 RFQ** |
| `PHY-CAND-02` | Cadence DDR4 PHY / controller 组合 | 同上，并确认 foundry-approved delivery 和 APB/training ABI | **待 RFQ** |
| `PHY-CAND-03` | Rambus 或 foundry-approved 等效 PHY | 同上，需确认交付形式、模型和板级工具 | **待 RFQ** |

候选只有在 `A-DDR4-02` 的 foundry/PDK、IO library 和 package ball map 确认后
才可进入正式技术评分。

## 2. 必须向供应商索取的交付物

1. 支持的 process/foundry/PDK、IO library、package 和温度/电压 corner；
2. DDR4-2133 与 DDR4-2400 的 speed grade、x32 single-rank supported-part list；
3. 完整 DFI port list、DFI version/frequency ratio、update handshake；
4. init/training/calibration success/fail 状态、timeout 和 reset/power-good 顺序；
5. synthesizable RTL/netlist、simulation model、license entitlement 和 SHA256；
6. synthesis/STA/IO/SI/PI constraints、ODT/termination 配置和 board tool；
7. APB/software configuration、error/status ABI、ECC/低功耗功能边界；
8. vendor reference design、memory model、training log 和已验证 DRAM part。

## 3. 评分门槛

| 维度 | 通过条件 |
|---|---|
| 工艺适配 | vendor 明确书面确认 selected node/foundry/PDK/package |
| 功能适配 | DDR4-2133、x32、single-rank、init/training/refresh 全部支持 |
| 验证交付 | model 可在本地仿真，能观察 success/fail/error/backpressure |
| 实现交付 | RTL/netlist、constraints、IO/SI/PI 工具和 license 可用 |
| 软件接口 | APB status/error/timeout 与 `ddr4_spec.md` ABI 可映射 |

任一硬门槛不通过，候选不能进入 `DDR4-IN-03/04/07` 的签收状态。

## 4. B 阶段产出

- `phy_vendor_comparison.md`：候选的版本、报价、license、支持矩阵和风险；
- vendor response artifact path/version/SHA256/owner 登记；
- 选定 PHY 后的 DFI wrapper port map 和 clock/reset review；
- 更新 `docs/ddr4_integration_inputs.md`，再运行 entry audit。

在这些产出完成前，`PHY_NOT_SELECTED` 和 `DDR4_ENTRY_READY=0` 必须保持。
