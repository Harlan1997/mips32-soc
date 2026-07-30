# Address Map

This file is the first draft of the project-wide memory map.

## Rules

- One address map for RTL, firmware, and verification.
- Every region must have a defined access type.
- Every unmapped access must complete with AXI `DECERR` (`2'b11`).
- Comments in RTL are not the source of truth; this file is.

## Draft Map

| Region | Base | Size | Type | Notes |
| --- | --- | --- | --- | --- |
| Boot SRAM | `0x0000_0000` | 64 KB | cacheable | Early boot / reset vector |
| Boot SRAM uncached alias | `0xA000_0000` | 64 KB | uncached | Same physical SRAM aperture; used by firmware mailbox/DMA buffers |
| DDR (behavioral placeholder) | `0x0800_0000` | 128 MB | cacheable | Phase C.4: capacity/addressing placeholder only, backed by `rtl/perips/axi_ddr_behavioral.v` (plain `reg` array, no DDR3 timing/refresh/PHY). Real controller is `docs/block_specs/ddr3_spec.md`, deferred pending procured PHY IP. Sized at 128 MB (not 256 MB) so the window ends at `0x0FFF_FFFF`, directly below SPI Flash — this is not 256MB-aligned, so the crossbar decodes it via an explicit range compare instead of the mask-equality check used for the other regions. |
| SPI Flash | `0x1000_0000` | 256 MB | read-mostly | Boot image / XIP candidate |
| APB Bridge | `0x4000_0000` | 64 KB | uncached | Peripheral window |
| Debug / Test | `0xE000_0000` | 64 KB | privileged | Reserved; only decoded when a future product feature gate enables it |

All addresses outside the listed implemented windows are unmapped and must
return AXI `DECERR`.

## APB Submap

| Peripheral | Offset | Notes |
| --- | --- | --- |
| UART | `0x0000` | console / bring-up |
| Timer | `0x1000` | system tick / watchdog candidate |
| GPIO | `0x2000` | board control |
| DMA | `0x3000` | optional bandwidth path |
| PIC | `0x4000` | interrupt aggregation |

## GPIO Register Map

Base: `0x4000_2000`

| Offset | Register | Access | Reset | Notes |
| --- | --- | --- | --- | --- |
| `0x000` | `GPIO_DATA` | RW | `0x0000_0000` | Output data when direction bit is 1, synchronized input when 0 |
| `0x004` | `GPIO_DIR` | RW | `0x0000_0000` | `1` = output, `0` = input |

## Required Follow-Up

The RTL, TB, and firmware must be aligned to this map before deeper
architecture cleanup continues.
