# DDR Controller Integration Inputs

> Version: v0.2 (2026-08-01)
>
> Target route: **ASIC (selected)**. Process/foundry/package/PHY inputs are not
> selected yet.
>
> Status: **BLOCKED**. This is the entry manifest for the DDR3 controller/PHY
> implementation. It is intentionally separate from the behavioral S3 model;
> an empty or placeholder row must never be treated as an implementation input.

The interface contract is frozen in
[`docs/block_specs/ddr3_spec.md`](block_specs/ddr3_spec.md). The following
external inputs are required before `ddr3_ctrl` RTL or an S3 replacement is
authorized. The ASIC acquisition sequence is tracked in
[`docs/asic_ddr_input_acquisition.md`](asic_ddr_input_acquisition.md).

| ID | Required input | Current state | Required evidence / owner |
|---|---|---|---|
| `DDR-IN-01` | PHY vendor/IP, release and license | **MISSING** | Contracted IP name/version, license entitlement and delivery artifact; owner: memory/implementation |
| `DDR-IN-02` | Complete DFI 3.1 port list and PHY ratio | **MISSING** | Vendor port declaration, supported `DFI_FREQ_RATIO`, update-handshake behavior and wrapper assumptions; owner: memory/implementation |
| `DDR-IN-03` | DDR3 part number, rank, width and density | **MISSING** | Exact DRAM ordering code and x32/single-rank confirmation; owner: board/hardware |
| `DDR-IN-04` | Board timing/electrical file | **MISSING** | Board trace/timing constraints, CK/DQS/ODT settings, voltage and temperature corner; owner: board/hardware |
| `DDR-IN-05` | Real DDR3 memory model | **MISSING** | Simulator-runnable Micron/commercial model, version and license; model must exercise init, timing, refresh and calibration responses; owner: verification |
| `DDR-IN-06` | Clock/reset/power-good implementation | **PARTIAL** | `clock_reset_spec.md` has target domains (400 MHz controller / 800 MHz PHY), but PLL source, reset release and power-good ownership are not selected; owner: clock/reset |
| `DDR-IN-07` | APB/software ABI owner | **CONTRACT FROZEN** | `SOC_APB_DDRCTRL_BASE`, offsets, status bits and error codes in `soc_config.vh`/`ddr3_spec.md`; firmware owner and review sign-off still missing |
| `DDR-IN-08` | Boot/WDT timeout budget | **MISSING** | Maximum PHY init/calibration/refresh-failure latency and corresponding boot failure code; owner: firmware/system |

## Entry Decision

`DDR_ENTRY_READY=0`. The repository contains no selected PHY wrapper, no real
DDR3 model and no `ddr3_ctrl` implementation. The only RTL memory target is
`rtl/perips/axi_ddr_behavioral.v`, which is capacity/address evidence only and
must remain labeled `BLOCK_VERIFIED`.

ASIC is the selected product route, but `ASIC-DDR-01..08` is not yet closed:
there is no process/foundry/package decision, PHY license/delivery, DRAM part,
board timing file, real model or boot timeout budget in this repository.

The entry audit may therefore report `BLOCKED` while passing its own consistency
checks. That result is not a DDR functionality pass and must not be included in
`PRODUCT_FUNCTION_READY` evidence.

## Unblock Procedure

1. Fill `DDR-IN-01..08` with immutable artifact paths, versions/hashes and named
   owners; update this manifest in the same integration branch as the inputs.
2. Re-run `make ddr-contract-entry-audit` and require `DDR_ENTRY_READY=1`.
3. Add the PHY wrapper and real memory model in a separate reviewed change set;
   compile the contract checker before implementing scheduler optimizations.
4. Implement `ddr3_ctrl`, replace S3 only after block init/error/refresh gates
   pass, and then run the no-preload product DDR boot gate.

No input is currently present in this repository, so step 1 is an external
dependency rather than an RTL task.
