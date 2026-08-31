# Scheduler/OS Hardware Contract

状态：v0.4，当前 RTL/仿真阶段 CONTRACT_CLOSED；scheduler 已以 opt-in 方式接入
`mips_core`，默认 SoC 仍关闭。

当前证据：`make cpu-scheduler-gate` 已通过，覆盖 timer trigger、task 轮询、
save/restore 握手、switch event 和 IPI reschedule trigger；
`make scheduler-timer-ipi-gate` 已通过真实 `apb_timer` tick 与 IPI 触发路径。

- scheduler 接受 `timer_tick`、`ipi_resched` 和 `yield_req` 三类调度触发。
- `active_mask` 标记可运行 task；当前实现最多 4 个 task，按 current task 后的轮询顺序选择下一个。
- 一次切换严格经过 `ctx_save_req` -> `ctx_save_done` -> `ctx_restore_req` -> `ctx_restore_ack`。
- 上下文包含 PC、SP、status、ASID、CP0 `Context.PTEBase` 和 32 个 GPR，由
  scheduler 为每个 task 保存一份；`switch_valid` 表示恢复确认完成。
- `Context.PTEBase` 使用 32 位、512 MiB 对齐的地址表示；恢复通过
  `ctx_restore_ptebase_valid` 握手更新 CP0。根发生变化时，CP0 保留 Wired
  项并清空动态主 TLB 以及 I/D micro-TLB，避免新 ASID 与旧页表根混用。
- 切换期间 `scheduler_busy=1`，新的 timer/IPI/yield 触发不打断当前切换；软件必须在 busy 清除后重试。
- `mips_core` 的 `ENABLE_SCHEDULER=1` 路径将 save/restore 请求接入 IF PC、GPR
  regfile 和 CP0 Status/ASID；恢复时冻结并清空流水线。当前集成接口保留为
  timer/IPI/yield 输入和 active-mask 输入，未声称完整 OS 调度器或 firmware ABI。
- `make cpu-scheduler-integration-gate` 已验证真实 `mips_cpu` 保存任务 0 并恢复
  任务 1 的 PC、GPR、GPR29/SP、CP0 ASID/Status 和 `Context.PTEBase`；当前可复现
  命令为 `RUN_DIR=build/unit_tb/cpu_scheduler_integration_ptebase
  tb/unit/cpu_test/run_cpu_scheduler_integration.sh`。
- `resched_ack` 与保存完成同周期有效，表示当前触发已被接收。

该接口是 CPU/OS 集成边界，不等同于完整 Linux 调度器。后续需要接入 CP0/异常返回、真实 timer APB IRQ、双核 IPI 目标和 firmware ABI。
