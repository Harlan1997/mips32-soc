# C1 DDR4 外部输入缺失的推进方案
DDR4 完成证据。
> 版本：v0.1（2026-08-02）
> 状态：**EXTERNAL_INPUTS_UNAVAILABLE / DDR4_PRODUCT_BLOCKED**

当 TSMC N28 PDK、Synopsys PHY 交付包或真实 DDR4 model 暂时不可获取时，
项目可以继续推进 SoC 功能，但必须把证据等级限制在 prototype/contract；
任何替代物都不能发布为 ASIC DDR4 PHY 或 `PRODUCT_FUNCTION_READY` 证据。

## 1. 可选推进路径

| 路径 | 做什么 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| **F1：vendor-neutral contract/model，推荐** | 完成 DDR4 AXI/APB/error contract、抽象 DFI adapter、init/training/refresh/error/backpressure behavioral model 和 directed gate | SoC 前端行为、软件 ABI、错误分类、reset/WDT、协议和控制器算法 | 真实 PHY port/ratio、SI/PI、timing、training margin、tapeout DDR4 |
| **F2：FPGA 原型** | 用 MIG/EMIF 运行 AXI/firmware/boot 场景 | 软件、AXI、内存访问和系统启动流程 | ASIC 工艺、Synopsys PHY、N28 IO、ASIC 时序和板级 DDR4 |
| **F3：DDR-less SoC 功能推进** | 保持 behavioral DDR/SRAM，完成 MMU、boot、QSPI、UART、WDT、异常和系统软件 | 非 DDR 域的 SoC 功能完整性 | 真实主存初始化、PHY、DDR4 boot |
| **F4：暂停 DDR，清理 P0** | 推进完整 kseg0 runtime、page-table/ASID rollover、cache-error/EIC、QSPI production path、UART pad/RX gate | 其他 P0 功能的产品证据 | DDR4 域任何产品结论 |

推荐组合：**F1 + F4**。有 FPGA 条件时可以额外做 F2，但 F2 报告必须单独
标记为 FPGA prototype evidence。

## 2. F1 的边界

F1 可以实现内部稳定的 `ddr_phy_adapter` 抽象接口，但不得伪造 Synopsys
DFI port list、frequency ratio、training timing 或 N28 IO 行为。behavioral
model 必须显式注入：

- init/training success、timeout、failure；
- refresh busy、self-refresh（若契约需要）；
- read/write backpressure、AXI error、reset flush；
- APB status/error/W1C 和 WDT timeout。

F1 完成后最多标记为 `BLOCK_VERIFIED (vendor-neutral)`，不能标记为
`SOC_INTEGRATED` 的真实 DDR4 产品证据。

## 3. 外部资料恢复后的切换

当资料可获取时，必须重新核对：

1. TSMC N28/28HPC PDK、DDR IO library、package ball map；
2. Synopsys PHY 版本、DFI port/ratio、training 状态和 license；
3. DDR4 part/speed grade、SI/PI/timing/ODT constraints；
4. vendor model、STA/SI/PI artifacts 和 boot/WDT worst-case。

只有这些输入替换 F1 假设、通过 `DDR4_ENTRY_READY=1`，才能创建产品 PHY
wrapper、接入真实 controller 并运行 no-preload DDR4 boot gate。

## 4. 当前决定

在外部资料不可得期间，默认执行 **F1 + F4**；C1 DDR4 产品 entry 保持
`BLOCKED`，不把 behavioral DDR、FPGA MIG/EMIF 或抽象 DFI model 当作 ASIC
DDR4 完成证据。

F1 gate 已通过：`make ddr4-phy-behavioral-gate` 验证 init/training success、
training/init failure、refresh backpressure、读写、fatal 和非法命令分类。
该结果等级为 `BLOCK_VERIFIED (vendor-neutral)`，不关闭 `DDR4-IN-01..08`。
