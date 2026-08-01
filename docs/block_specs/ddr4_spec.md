# DDR4 控制器/PHY 功能契约候选 (v0.1)

> 状态：**C1 已选择，契约待外部 PHY/工艺输入冻结**（2026-08-02）。
> 本文是 DDR4 产品契约候选，不代表 controller、PHY 或 DDR4 boot 已实现。

## 0. 目标与边界

- 产品基线：单 rank、单 chip-select、x32 DDR4；DDR4 speed grade 由选定 PHY、
  DRAM part 和板级 timing 文件共同确定，当前暂不假定具体 MT/s。
- AXI 前端保留当前 SoC 架构：32-bit data、4-bit ID、`INCR` burst、1-16
  beats、自然对齐、不得跨 4-KB 边界。
- 地址窗口保留 `SOC_DDR_BASE..SOC_DDR_BASE+SOC_DDR_SIZE-1`，越界返回
  `DECERR`；controller 未初始化、PHY/training/refresh fatal 返回有界
  `SLVERR`，不得静默死锁或折返地址。
- 首版不承诺 ECC、多 rank、多个 chip-select、低功耗 self-refresh 或
  DDR4 温度补偿；这些必须单独形成变更集和测试证据。

## 1. PHY 与 DFI

PHY 必须从 foundry-approved 商用 DDR4 catalog 选择。DFI 版本、frequency
ratio、完整 port list、训练状态和 APB 参数均以供应商交付物为准；不能从
旧 DDR3 DFI 3.1 文档推断。controller wrapper 必须记录：

1. DFI command/address、write-data、read-data 和 update/handshake port；
2. PHY init/training complete、fail、校准状态和 reset/power-good 时序；
3. `axi_clk`、controller clock、PHY clock 的 ratio、CDC 和 reset flush 语义；
4. synthesis/STA constraints、仿真 model、license 和支持的 DRAM part。

## 2. AXI/APB 行为

AXI 错误分类、ID/RLAST、背压、4-KB 边界和 reset flush 规则沿用当前
`ddr3_spec.md` 的 SoC-level 前端原则，但必须在 DDR4 contract review 中
重新签收。APB base 暂保留 `0x4000_6000`，version/status/error offsets
在新 ABI owner sign-off 前不修改 `soc_config.vh`。

初始化阶段 `STATUS.init_done=0` 时允许 AXI 暂停，但 Boot ROM 必须轮询
APB 并受 WDT 约束；fatal 状态必须在 bounded latency 内以 `SLVERR` 完成
请求，且软件可读 training/error code。清错后只有完整 re-init 成功才能
恢复正常 AXI 服务。

## 3. Entry / exit criteria

进入 DDR4 controller RTL 前，必须关闭
[`docs/ddr4_integration_inputs.md`](../ddr4_integration_inputs.md) 的
`DDR4-IN-01..08`。完成后才允许实现 AXI/DDR CDC、scheduler、DFI wrapper
和 APB status。产品功能关闭还需要真实 PHY/model 的 init/training、refresh、
read/write、backpressure、reset/error 和 no-preload boot gate。
