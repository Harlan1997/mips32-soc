# Architecture Review

## Current State

The project already has the basic blocks of a real SoC:
- MIPS32 CPU core
- L1 instruction/data caches
- AXI interconnect and decoder
- APB peripheral block
- timer, GPIO, PIC, SPI flash, JTAG debug

The problem is not feature count. The problem is integration discipline.

## Main Architecture Issues

1. Product and verification boundaries are mixed.
   The SoC top exposes debug and test injection paths that should not live in a
   production top-level.

2. No single source of truth exists for interface parameters.
   AXI widths, burst lengths, reset behavior, and memory map are duplicated in
   RTL, TB, and scripts.

3. The interconnect is assembled as a chain of point fixes.
   This works for simulation, but it does not scale as a product fabric.

4. Address decode policy is inconsistent.
   Comments, testbench assumptions, and RTL decoding do not fully agree.

5. Verification is tied to hierarchy.
   Current checks depend on internal signal names and force-based hooks.

## Production Impact

These issues increase risk in:
- RTL maintenance
- software bring-up
- regressions
- CDC/RDC closure
- DFT planning
- tapeout signoff

## Architecture Goal

Turn the project into a layered SoC with:
- a stable product top
- a separate verification top
- a single address map
- a reusable bus package
- explicit reset and clock policy
- documented debug/test modes
- signoff-ready validation flow
