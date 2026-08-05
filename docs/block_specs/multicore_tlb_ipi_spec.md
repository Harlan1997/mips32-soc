# Multicore TLB Shootdown and IPI Contract (Draft)

状态：双核 opt-in RTL 集成基线 v0.7；默认单核配置不变，双核 IPI 正常与错误路径及异常隔离 gate 已通过。

## 1. 范围

本契约定义双核 MIPS32 CPU 的：

- IPI request/acknowledge；
- TLB shootdown payload 与完成语义；
- generation/ack 防止旧请求误确认；
- CPU 停止点与重新执行边界；
- 与现有软件管理 TLB 的连接方式。

硬件 page-table walker、scheduler、Linux/U-Boot、真实 cache coherency 实现尚未纳入本契约；是否属于当前阶段必须由项目需求确认，不能由本规格单方面排除。

## 2. 冻结基线

- `CORE_COUNT=2`；core ID 为 0 和 1。
- 当前基线继续软件管理 TLB；硬件 page-table walker 尚未实现，是否切换为硬件/混合管理待架构规格冻结。
- 每个 core 保持现有 direct dual-lookup TLB。
- shootdown 由 software/page-table manager 发起，硬件只提供 IPI 传递和本地 TLB invalidate。
- 当前单核 `mmu_tlb_shootdown_mailbox` payload 保持兼容。

## 3. IPI 寄存器契约

每个 core 有独立 IPI window，建议映射在 APB MMU context block：

| Offset | 名称 | 语义 |
|---|---|---|
| `0x20` | `IPI_TARGET_GEN` | bit[0] raw target；bit[15:8] generation |
| `0x24` | `IPI_ASID` | shootdown ASID |
| `0x28` | `IPI_VPN` | shootdown VPN[19:0] |
| `0x2c` | `IPI_SCOPE` | invalidate scope[1:0] |
| `0x30` | `IPI_SEND` | bit[0] 写 1 发送 |
| `0x34` | `IPI_STATUS` | bit[0] busy、bit[1] pending、bit[2] done、bit[3] timeout、bit[4] rejected、bit[5] stale ack |
| `0x38` | `IPI_CLEAR` | W1C 清除 done/timeout/rejected/stale ack |
| `0x3c` | `SIM_FAULT_CTL` | 仿真专用：bit[0] target absent、bit[1] ACK block、bit[2] stale ACK、bit[3] core 1 reset；复位值 0，生产路径不使用 |

shootdown payload 继续使用现有 `{ASID, VPN, scope}`，并增加 target core 和 generation。

## 4. 完成语义

1. 发起方分配 generation 并写入 payload。
2. 目标 core 收到 IPI 后，在指令提交边界停止新的 TLB-sensitive access。
3. 目标 core 执行 local invalidate。
4. 目标 core 返回同一 generation 的 ack。
5. 发起方只接受匹配 generation 的 ack；旧 ack 必须被拒绝。
6. timeout 不自动宣称成功，必须产生 sticky error。

## 5. Cache/coherency 边界

本阶段只冻结 TLB/IPI 行为，不宣称 cache coherency 已实现。双核 RTL gate 必须显式使用 uncached/shared-memory mailbox，直到 coherency contract 单独签收。

## 6. 当前 RTL 实现状态

- `soc_top.ENABLE_DUAL_CORE=1` 实例化第二个 CPU/MMU/L1 核。
- 核 1 的 I/D AXI 请求经独立 read arbitration 后接入现有 fabric external-master 槽位。
- 核 0 APB IPI request 可驱动核 1 local TLB invalidate 和 interrupt input。
- 单核默认路径仍使用 `ENABLE_DUAL_CORE=0`，不占用该 opt-in master 槽位。
- 已证明双核 opt-in firmware execution，以及 core 0 -> core 1 的 uncached APB IPI、local invalidate、ack 和 refill 前进路径。
- 已证明 core 0 使用 `0x4000_A000`、core 1 使用 `0x4000_B000` 独立 IPI controller；两个 controller 均完成 target 0/1 路由、generation ack 和对应 core 的 local invalidate。
- `0x4000_B000` 是核 1 AXI alias，controller 内部反转 raw target bit，使同一 freestanding firmware 可在两个核上验证相反的有效 target；这不是 cache coherency 或 OS scheduler。
- 已证明 SoC firmware 的 stale ACK、timeout 和 busy re-entry rejection；`0x3c` fault control 仅为仿真入口，不是生产功能。
- 已证明 core 1 独立 reset request 不阻断 core 0 的 firmware/mailbox 完成；该 reset request 仅为仿真入口。
- 已证明 core 1 的仿真专用 RI 异常 stimulus 被其自身 CP0 独立采样，且 core 0 仍可完成 mailbox；共享内存 coherency、page-table walker 和 scheduler 尚未实现，需求归属待确认。

## 7. 完成条件

- unit gate：IPI send/ack/timeout/stale-generation；
- dual-core SoC gate：独立 core 0/core 1 IPI controller、target 1/target 0 local invalidate 路由；
- stale ack、重复请求、busy 重入和 timeout；仿真故障入口必须与生产寄存器路径隔离；
- TLB invalidate 后重新 refill；
- 默认单核 baseline 全部回归通过。
