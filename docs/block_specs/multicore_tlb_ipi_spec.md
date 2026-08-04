# Multicore TLB Shootdown and IPI Contract (Draft)

状态：下一阶段架构契约，当前未接入 RTL；不改变现有单核 CPU/MMU baseline。

## 1. 范围

本契约定义双核 MIPS32 CPU 的：

- IPI request/acknowledge；
- TLB shootdown payload 与完成语义；
- generation/ack 防止旧请求误确认；
- CPU 停止点与重新执行边界；
- 与现有软件管理 TLB 的连接方式。

硬件 page-table walker、scheduler、Linux/U-Boot、真实 cache coherency 实现不属于本阶段。

## 2. 冻结基线

- `CORE_COUNT=2`；core ID 为 0 和 1。
- TLB 继续软件管理；不新增硬件 page-table walker。
- 每个 core 保持现有 direct dual-lookup TLB。
- shootdown 由 software/page-table manager 发起，硬件只提供 IPI 传递和本地 TLB invalidate。
- 当前单核 `mmu_tlb_shootdown_mailbox` payload 保持兼容。

## 3. IPI 寄存器契约

每个 core 有独立 IPI window，建议映射在 APB MMU context block：

| Offset | 名称 | 语义 |
|---|---|---|
| `0x30` | `IPI_SEND` | bit[0] target core，写 1 发送 |
| `0x34` | `IPI_STATUS` | pending/busy/ack/timeout/rejected |
| `0x38` | `IPI_CLEAR` | W1C 清除 pending/ack/timeout |
| `0x3c` | `IPI_GEN` | 当前 generation token |

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

## 6. 完成条件

- unit gate：IPI send/ack/timeout/stale-generation；
- dual-core SoC gate：core 0 -> core 1 shootdown 和反向 shootdown；
- stale ack、重复请求、busy 重入和 timeout；
- TLB invalidate 后重新 refill；
- 默认单核 baseline 全部回归通过。

