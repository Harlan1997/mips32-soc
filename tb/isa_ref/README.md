# ISA Reference Model Cosim Harness (Phase F)

QEMU-MIPS reference-model infrastructure for the implemented MIPS32 R2
subset. The gate executes QEMU with one guest instruction per translation block,
captures instruction/memory events plus CPU snapshots, and compares the
resulting retire JSONL against the RTL trace.

## Design intent

For every instruction the DUT retires:
1. Feed the same PC + memory state to the reference model
2. Reference model produces expected GPR / CP0 / PC / memory diff
3. Compare against DUT trace signal (instruction retire event on WB stage)
4. Report mismatch → dump waveform → fail regression

## Cosim options

**QEMU-MIPS as ISA sim**
- QEMU plugin records every executed instruction, opcode, and memory access.
- `-one-insn-per-tb -d cpu,nochain` supplies the before/after architectural
  register snapshots used to construct retire records.
- The current gate is single-vCPU linux-user MIPS and requires the exact guest
  ELF plus RTL trace to be supplied explicitly.

The current implementation uses the project-local QEMU 9.2.0
`build-mipsel-linux-user/qemu-mipsel` build, produced by `make qemu-linux-user`.
`QEMU_BIN` may point to an equivalent validated build.
Missing QEMU returns `BLOCKED`; it is not silently treated as a passing
reference run.

## Harness architecture

```
tb/isa_ref/
  README.md                     ← this file
  retire_trace_capture.sv       ← JSONL sink bound to the DUT observation IF
  trace_compare.py              ← deterministic architectural diff
  qemu_retire_plugin.c          ← per-instruction QEMU plugin
  qemu_cpu_trace_to_jsonl.py    ← CPU snapshot/event merger
  run_qemu_reference_gate.sh    ← QEMU retire differential gate
  run_cpu_lockstep_gate.sh      ← compatibility alias to QEMU gate
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

`soc_observation_if.sv` now exposes the versioned retire bundle and the UVM top
can capture it with `RETIRE_TRACE=/path/trace.jsonl` (the compile is opt-in via
`SOC_RETIRE_TRACE_ENABLE=1`). Run the QEMU differential gate with:

The differential wrapper also passes `RETIRE_TRACE_MAX_RECORDS` into the RTL
simulation (default `1000000`). A nonzero limit stops a stuck guest before its
JSONL sink can grow without bound; set it to `0` only for a deliberately
reviewed unbounded capture.

```text
QEMU_ELF=/path/to/exact_guest.elf \
RTL_TRACE=/path/to/rtl_retire.jsonl \
QEMU_EXPECTED_EXIT=0 \
make cpu-reference-gate
```

The gate writes `qemu_instruction_events.jsonl`, `qemu_cpu.log`,
`qemu_retire.jsonl`, and `trace_compare.log` below `build/isa_ref/qemu`.
Missing guest or RTL trace returns `BLOCKED`; QEMU version readiness alone is
never a pass. The historical `make cpu-lockstep-gate` target aliases this
same retire differential gate.

## System-mode SoC reference machine

The project bare-metal ELF is not a Linux-user guest. Build the opt-in QEMU
system-mode machine with:

```bash
make qemu-system-mips32-soc-ref
```

The resulting binary is
`build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel`. The
`mips32-soc-ref` machine models the 64-KB SRAM, kseg0/kseg1 aliases, the UART
TX/LSR subset, the `0xA000FFFC` `0xDEADBEEF` exit mailbox, APB GPIO/timer/DMA/
PIC behavior, a behavioral DDR window/status block, and x1 image-backed
QSPI/XIP. Pass `-M mips32-soc-ref,qspi-image=/path/image.bin` to populate the
`0x10000000` XIP window. The mailbox exit is a `0xDEADBEEF` store, not merely
an access to its aliased physical address: ordinary firmware stacks may use
`0x0000fffc`.

The reference machine accepts the opt-in `gpio-input=0x<value>` property for
external GPIO input readback. GPIO bits with `GPIO_DIR=0` read this value,
while output bits continue to read the driven `GPIO_DATA` value. The timer
model follows the RTL source-2 interrupt, sticky `0x4000100c` status and W1C
clear contract. Run `make qemu-system-gpio-input-gate` for the combined
GPIO-input/timer-IRQ reference-model check.

For an opt-in DDR status fault model, use
`-M mips32-soc-ref,ddr-fault-mode=1` for an AXI error or `=2` for a geometry
error. `make qemu-system-ddr-fault-gate` verifies sticky error status, W1C,
and continued cached/uncached DDR window access; the default mode remains
READY with no error.

The current system RTL retire gates are:

```bash
make qemu-system-retire-differential-gate
make qemu-system-exception-differential-gate
make qemu-system-bd-exception-differential-gate
make qemu-system-peripheral-differential-gate
make qemu-system-vic-differential-gate
```

The VIC gate compares a deterministic two-source software interrupt sequence
through vector entry, `VEC_ID`, `ACK`, `SOFT_CLR`, and `ERET`. It remains an
RTL prototype reference machine, not a PHY/JEDEC product model; command/FIFO
QSPI, quad electrical behavior, external interrupt replay, VEIC, and full
`vic_cpu` firmware differential behavior remain separate closure work.

Example:

```bash
qemu-system-mipsel -M mips32-soc-ref -m 64K \
  -kernel tb/soc_test/fw/firmware.elf -nographic -monitor none
```

## Success criteria (per docs/vplan.md)

> >10⁹ retired instructions cosim-verified with zero mismatch — required
> for Phase F Linux-boot regression sign-off.
