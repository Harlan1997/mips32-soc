# ISA Reference Model Cosim Harness (Phase F)

Placeholder for QEMU-MIPS or Sail-MIPS lockstep reference-model comparison
against the DUT after each retired instruction.

## Design intent

For every instruction the DUT retires:
1. Feed the same PC + memory state to the reference model
2. Reference model produces expected GPR / CP0 / PC / memory diff
3. Compare against DUT trace signal (instruction retire event on WB stage)
4. Report mismatch → dump waveform → fail regression

## Cosim options

**Option A — QEMU-MIPS as ISA sim**
- Pros: pre-existing, wide test coverage, boots Linux
- Cons: needs custom trace shim (QEMU replay-trace); coarse-grained (block-level)
- Effort: ~3-4 weeks integration
- License: GPL-2

**Option B — Sail-MIPS golden model**
- Pros: formal-quality spec, exact instruction-level trace built in
- Cons: less mature MIPS coverage than QEMU; toolchain (OCaml)
- Effort: ~6-8 weeks
- License: BSD-2

**Recommendation**: start with Option A for functional bring-up (find gross
bugs); introduce Option B in Phase F.2 for sign-off-quality assurance.

## Harness architecture (planned)

```
tb/isa_ref/
  README.md                     ← this file
  qemu/
    qemu_trace_shim.c           ← QEMU replay-trace consumer
    dut_trace.sv                ← DUT retire event capture
    trace_compare.py            ← post-run diff
    cosim_harness.mk            ← build glue
  sail/
    (future) sail_step.ml       ← per-instruction step wrapper
```

## Integration hook (RTL side)

Requires a **retire event bundle** exposed from writeback stage:
- `wb_valid` (1)
- `wb_pc` (32)
- `wb_instr` (32)
- `wb_gpr_wr_en` (1)
- `wb_gpr_wr_addr` (5)
- `wb_gpr_wr_data` (32)
- `wb_mem_wr_en` (1)
- `wb_mem_wr_addr` (32)
- `wb_mem_wr_data` (32)
- `wb_cp0_wr_en` (1)
- `wb_cp0_wr_addr` (5+3)
- `wb_cp0_wr_data` (32)

Currently `soc_observation_if.sv` exposes basic retire signals; extend as
needed when cosim integration lands.

## Success criteria (per docs/vplan.md)

> >10⁹ retired instructions cosim-verified with zero mismatch — required
> for Phase F Linux-boot regression sign-off.
