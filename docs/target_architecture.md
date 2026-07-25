# Target Architecture

## Top-Level Partitioning

### 1. Product Top

Responsibilities:
- expose board-level pins only
- instantiate CPU, memory system, peripherals, interrupt controller, debug
  block if enabled
- keep testbench-only hooks out

Current implementation entry:
- `rtl/soc_top.v`
- `rtl/mips_soc.v`

Transition note:
- `soc_top` wraps the product-facing `mips_soc`.
- `mips_soc` exposes product pins only and does not expose the UVM external AXI
  master.
- `mips_soc` currently wraps `mips_soc_impl` with all verification-only hooks
  explicitly disabled: external AXI master, APB fault injector, and loadable
  flash-image model.
- The next architecture step is to refactor `mips_soc_impl` into smaller
  product-owned integration blocks.

### 2. Verification Top

Responsibilities:
- instantiate the product top
- connect UVM agents, monitors, scoreboards, stimulus, and coverage
- allow temporary backdoors and force only here

Current implementation entry:
- `tb/uvm_tb/tb_top/tb_top.sv`
- `tb/uvm_tb/tb_top/soc_verif_top.sv`

Transition note:
- The UVM top now instantiates `soc_verif_top`.
- `soc_verif_top` contains the transitional `mips_soc_impl u_dut`, exposes the
  verification-only external AXI master, and centralizes temporary observation
  hooks used by the regression mailbox and debug trace.
- `soc_verif_top` explicitly sets `mips_soc_impl.ENABLE_EXT_AXI_MASTER`,
  `mips_soc_impl.ENABLE_APB_FAULT_INJECTOR`, and
  `mips_soc_impl.ENABLE_FLASH_IMAGE_MODEL` to `1` so UVM stress tests, APB
  fault stress, and loadable flash-image checks preserve their current behavior.
- CPU/CP0, mailbox, execution-trace, and JTAG AXI-state observation now cross
  the named `soc_observation_if` and are driven by a verification-only
  `soc_observation_bind`.
- Legacy smoke observation now uses `soc_legacy_observation_if` plus
  `soc_legacy_observation_bind`, and legacy firmware preload uses a
  simulation-only `preload_sram_hex()` task instead of direct SRAM array access.
  Remaining verification debt is reducing the legacy smoke bind surface as UVM
  coverage replaces that bench.

### 3. Common Package

Responsibilities:
- define AXI/APB widths
- define address map
- define interrupt source IDs
- define reset defaults and boot address
- define feature enable switches

Current implementation entry:
- `rtl/include/soc_config.vh`

## Interconnect Direction

The current multi-stage arbiter chain should be replaced by a clearer fabric:
- CPU instruction port
- CPU data port
- optional external debug master
- optional DMA master
- routed into a single interconnect layer

Expected properties:
- deterministic arbitration
- explicit priority policy
- backpressure-safe channel handling
- address decode in one place
- illegal access response defined centrally

## Memory System

Target organization:
- boot ROM / SRAM region
- cacheable DDR/SRAM region
- flash region
- uncached peripheral region

The decode policy must be identical across:
- RTL
- firmware linker scripts
- regression tests
- docs

## Debug Policy

Debug must be controlled by build-time configuration:
- production mode: minimal mandatory debug only
- bring-up mode: JTAG/trace/mailbox enabled
- verification mode: full test hooks and monitors

## Reset and Clock Policy

Requirements:
- one clock domain unless a domain split is explicitly documented
- reset polarity and release sequence documented once
- no hidden asynchronous behavior in wrappers
