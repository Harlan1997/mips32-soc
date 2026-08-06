# Dual-Core Coherency Contract

状态：v0.1，当前阶段 ACTIVE；需求已纳入，但完整 MESI/目录协议尚未冻结。

## 1. 当前实现基线

双核 opt-in (`ENABLE_DUAL_CORE=1`) 先采用可验证的 write-invalidate 子集：

- 双核 D-cache 的 store 走 uncached/no-write-allocate 路径；
- store 收到成功 AXI `B` 响应后产生一次 line-addressed write notification；
- 另一核的 L1 D-cache 对匹配的 valid line 清除 valid 位；
- load 仍允许在 L1 D-cache 中缓存；失效后再次 load 必须从共享内存重新取值；
- 默认单核路径和 `ENABLE_DUAL_CORE=0` 不启用该逻辑；
- 当前不宣称 MESI/MOESI、写回 store、目录、snoop retry 或多 outstanding。

该基线的目标是先建立明确的双核共享内存可见性语义。它不是最终性能优化方案，后续可在规格评审后替换为完整 MESI/目录协议。

## 2. 可观察事件

`coh_store_valid` 只在 uncached store 收到 OKAY `B` 响应的周期有效，`coh_store_addr` 为物理字节地址。snoop 接收方按 `[31:11]` tag 和 `[10:5]` index 匹配所有 way，并清除匹配 line 的 valid 位。

## 3. 暂定顺序规则

- 成功 store 的 AXI `B` 响应先于 write notification；
- notification 在对端下一个时钟边界生效；
- 对端正在 refill 或维护操作时，必须在后续 directed gate 中定义阻塞/重试行为；
- 同一 line 的双核并发 store 顺序由共享 AXI fabric 的 accepted write 顺序决定，当前不提供 software-visible total-order register。

## 4. 必须关闭的验证项

- cached load -> peer store -> cached load 重新取值；
- 不同 word、同一 line 的 partial-byte store；
- 双核同时 store 的 accepted-order 可重复性；
- snoop 与 refill、writeback、CACHE invalidate 的冲突；
- reset 时通知丢失和 reset 后重新取值；
- LL/SC 在 peer store 后的 reservation 失效语义；
- AXI error 时不得产生 coherency notification。

## 4A. 当前已验证证据

`make dcache-coherency-gate` 已通过：覆盖 cached load -> peer store ->
peer notification -> line refill、同一 line 不同 word、partial-byte store，
并确认 AXI `B` error 不产生 notification。双核参数化 RTL 由
`make dual-core-frontend-compile` 通过 elaboration。CPU/firmware 级 LL/SC
peer store coherency gate 由 `make llsc-coherency-gate` 闭合：在 dual-core opt-in
和 `SOC_COHERENCY_LL_SC` 下注入 core-0 匹配 peer store notification，验证
core-0 reservation 被正确清除，后续 SC 返回失败 0 且内存数据未被修改。
该 gate 仍然不宣称完整 MESI/MOESI 协议、Directory、写回 coherency、multi-outstanding
内存序或全共享内存 coherency。

## 5. 后续架构决策

完整 MESI/目录、写回 store、snoop backpressure、硬件 page-table walker、scheduler/OS 与本契约分别关联，但不再被本文件单方面归类为后置或排除项；是否以及何时切换由项目需求和架构评审确认。
