# DDR4 Controller Integration Inputs

> Version: v0.1 (2026-08-02)
>
> Target route: **ASIC Profile C1 DDR4 (selected)**.
> Status: **BASELINE_ACCEPTED / BLOCKED**. This is the product DDR4 entry
> manifest; placeholders are not implementation inputs.

The candidate contract is
[`docs/block_specs/ddr4_spec.md`](block_specs/ddr4_spec.md). The legacy DDR3
manifest remains at [`docs/ddr_integration_inputs.md`](ddr_integration_inputs.md)
and must not be used to authorize the C1 product controller.
The upstream parameter decisions are tracked in
[`docs/asic_c1_ddr4_parameter_decision.md`](asic_c1_ddr4_parameter_decision.md);
stage A is not closed yet.
The accepted baseline is 28nm LP, **TSMC N28/28HPC RFQ target**, BGA, 1.2 V
commercial, DDR4-2133, x32 single-rank and ECC disabled; Synopsys is the
priority PHY RFQ target, while foundry/PHY compatibility remains open.

| ID | Required input | Current state | Required evidence / owner |
|---|---|---|---|
| `DDR4-IN-01` | Process node, foundry, PDK and DDR IO library | **MISSING** | Immutable node/PDK/library release and access owner; SoC/implementation |
| `DDR4-IN-02` | Package, IO voltage, temperature grade and board topology | **MISSING** | Package/ball map, voltage/corner and x32 single-rank sign-off; package/board |
| `DDR4-IN-03` | Commercial DDR4 PHY/IP, release and license | **MISSING** | Foundry-approved vendor, version, entitlement, delivery path and SHA256; memory/implementation |
| `DDR4-IN-04` | Complete PHY DFI port list, ratio and training semantics | **MISSING** | Vendor port declaration, init/training/fail states and wrapper assumptions; memory/implementation |
| `DDR4-IN-05` | Exact DDR4 DRAM part, rank, width, density and speed grade | **MISSING** | Ordering code, datasheet revision and supported PHY part list; board/hardware |
| `DDR4-IN-06` | Board/package SI/PI, timing, ODT and constraint files | **MISSING** | Trace, termination, timing/corner files with hashes; board/implementation |
| `DDR4-IN-07` | Real DDR4 memory model and verification license | **MISSING** | Simulator-runnable vendor/DRAM model exercising init/training/refresh/timing/error; verification |
| `DDR4-IN-08` | PLL/reset/power-good implementation and boot/WDT budget | **PARTIAL** | Concrete clock/reset ownership, timeout values and failure ABI; clock/system |

## Entry Decision

`DDR4_ENTRY_READY=0`. No DDR4 PHY wrapper, real DDR4 model or product
controller exists in the repository. `rtl/perips/axi_ddr_behavioral.v` remains
capacity/address evidence only.

The repository now contains an F1 vendor-neutral abstract model and gate, but it
does not satisfy `DDR4-IN-03`, `DDR4-IN-04` or `DDR4-IN-07`.

The entry audit may pass its consistency checks while returning `BLOCKED`. That
result is not DDR4 functionality evidence and must not be included in
`PRODUCT_FUNCTION_READY`.

## Unblock Procedure

1. Fill `DDR4-IN-01..08` with artifact path, version, SHA256, license, owner and
   review sign-off.
2. Run `make ddr-contract-entry-audit` and require `DDR4_ENTRY_READY=1`.
3. Add the selected PHY wrapper and real memory model in a separate reviewed
   change set; then implement the DDR4 controller against the candidate contract.
4. Run init/training/refresh/error/backpressure/reset/no-preload boot gates before
   replacing S3 or upgrading the DDR domain beyond `BLOCK_VERIFIED`.
