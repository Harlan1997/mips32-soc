# Hardware Page-Table Walker Contract

状态：v0.1，当前 RTL/仿真阶段 ACTIVE；walker block 和 TLB refill ownership gate 已通过。

当前证据：`make page-table-walker-gate` 与
`make page-table-tlb-refill-gate` 通过。后者覆盖 walker leaf PTE 到 MIPS
EntryLo、VPN2/ASID 传递和 TLB write ready 握手。

- 两级、4KB 页，VA 分解为 `[31:22] / [21:12] / [11:0]`。
- `PTBR[31:12]` 指向 4KB 对齐根表；每级 PTE 为 32 bit、按 4 byte 索引。
- 非叶 PTE 要求 `V=1,TABLE=1`；叶 PTE 要求 `V=1,TABLE=0`、`PFN[31:12]`，权限位为 `W[1]`、`X[2]`、`U[3]`。
- access `00=fetch`、`01=load`、`10=store`；fetch 要求 X，load 要求 W 或 X，store 要求 W；user access 要求 U。
- walker 只允许一个 outstanding memory read；`mem_ready` 完成请求，`mem_error` 产生 bus fault。
- 成功返回 `PA={leaf.PFN,VA[11:0]}`；fault 分类为 miss、permission、bus、format。

这是 CPU/MMU 当前阶段的硬件翻译扩展 contract，不等同于完整 MIPS Linux 页表 ABI。
CPU refill ownership、TLBWI/TLBWR 仲裁和异常向量接入仍需后续集成 gate。
# Hardware Walker CPU Integration

在 `mips_cpu` 的 `hardware_walker_enable=1` opt-in 路径中，I/D 侧 TLBL/TLBS
miss 会冻结流水线并通过独立 `ptw_mem_*` 端口发起一次 outstanding 页表读。
成功后由 CP0 的硬件 TLB 写端口写入动态 entry，并自动重试原访问；walker
fault 保持原有异常路径。默认 SoC 将该端口关闭并 tie-off。

`make cpu-hardware-walker-gate` 已验证真实 CPU 的两级页表读、TLB 写入、物理
地址重取指和无异常误报。该闭合不包含完整 OS demand paging 或 page-table
allocator。
