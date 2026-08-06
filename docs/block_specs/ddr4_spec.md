# DDR4 Controller RTL Protocol Specification (v1.0)

> 状态：**RTL 协议契约已冻结，controller RTL 已实现**（2026-08-05）。
> 本文只定义 vendor-neutral DDR4 controller RTL 和功能仿真边界。

当前仓库中的
[`rtl/perips/axi_ddr4_controller.v`](../../rtl/perips/axi_ddr4_controller.v)
已按本文契约接入 SoC S3，并由 controller gate、fabric gate 和 SoC smoke
验证。历史 DDR4 behavioral model 不属于默认路径，也不作为 controller
RTL 完成证据。

## 0. 目标与边界

- controller 维护单 rank、单 chip-select、x32 的协议状态；本规格不选择具体器件或速度档位。
- AXI 前端使用 32-bit data、4-bit ID、`INCR` burst、1-16 beats、自然对齐，禁止跨 4-KB 边界。
- 地址窗口为 `SOC_DDR_BASE..SOC_DDR_BASE+SOC_DDR_SIZE-1`；越界返回 `DECERR`。
- controller 未初始化或 fatal 状态返回有界 `SLVERR`，不得静默死锁或折返地址。
- 首版不承诺 ECC、多 rank、多个 chip-select、低功耗 self-refresh 或温度补偿；这些是独立 RTL 需求。

## 1. AXI/APB 契约

- APB base 为 `0x4000_6000`，version/status/error offsets 与 `soc_config.vh` 一致。
- `STATUS.init_done=0` 时，AXI 请求可以暂停；仿真必须证明恢复后请求继续完成。
- status 提供初始化、refresh、busy、fatal/error 和最近错误信息，并支持规定的 W1C 清除。
- P1 DDR4 ECC IRQ Escalation 契约：`ddr4_fatal_error || ddr4_ecc_uncorrectable_error` 接入 `soc_peripheral_subsystem` 的 PIC source 5；Existing source IDs 0..4 保持不变。Correctable ECC 仍为 status-only，不触发 source 5 或 CPU IRQ。由 `ddr4-pic-integration-gate` 验证 source 5 raw/masked/CPU IRQ 和 APB status classification / W1C。
- AXI 读写必须保持 ID、beat 数、`R_LAST/W_LAST` 和 response code 的对应关系。
- reset 必须 flush 所有未完成事务，master 观察到有界错误响应或明确的取消语义。

## 2. Controller 状态与命令

controller 为每个 bank 保存 open-row 状态，并使用以下命令脉冲表达协议行为：

1. 初始化完成前进入 `INIT`，完成后置 `init_done`。
2. row hit 直接发起 `READ` 或 `WRITE`。
3. row miss 按 `PRE -> ACT -> READ/WRITE` 顺序发起命令。
4. 空闲 bank 按 `ACT -> READ/WRITE` 顺序发起命令。
5. refresh 请求暂停新 AXI 接受，完成 refresh 后恢复服务。
6. 命令脉冲、地址、bank、row、column 和写数据必须在对应 valid 周期稳定。

本版本只要求协议级状态和命令观测端口；命令观测用于 testbench checker，不构成外部实现接口。

## 3. 错误、背压与 reset

- 非法地址、非法 burst、未对齐访问和 4-KB crossing 必须被拒绝。
- 错误的 `WLAST`、非法读写状态和 fatal 状态必须产生确定的 AXI error response。
- refresh、初始化和 response backpressure 不得丢失事务、重复完成或改变 AXI ID。
- reset 期间不得继续发起命令；恢复后 bank 状态、事务队列和 sticky status 必须符合 reset contract。
- 所有 stall、错误和恢复路径都必须有 unit-level directed/negative test。

## 4. RTL 验收条件

最低验收集合：

- 四 beat 读写、row hit、row miss 及 `PRE -> ACT` 顺序；
- refresh 背压与恢复；
- 非法地址、4-KB crossing、错误 `WLAST` 和错误 response；
- reset flush、初始化状态和 APB status/W1C；
- controller gate、fabric gate、SoC smoke 和 RTL frontend compile 可重复通过。

本规格的完成结论为 `RTL_FUNCTIONAL_SIM_READY`。它不扩展到本项目未纳入的其他实现阶段或外部系统验证。
