# Address Map

> Version: v0.3 (2026-08-01). The product boot/memory contract is defined in
> `docs/boot_memory_contract.md`; the table below is the shared source of
> truth for implementation and verification. Prototype smoke tests may still
> use the legacy SRAM preload path until the product gate is enabled.

This file is the first draft of the project-wide memory map.

## Rules

- One address map for RTL, firmware, and verification.
- Every region must have a defined access type.
- Every unmapped access must complete with AXI `DECERR` (`2'b11`).
- Comments in RTL are not the source of truth; this file is.

## Draft Map

| Region | Base | Size | Type | Notes |
| --- | --- | --- | --- | --- |
| Boot ROM | `0x1FC0_0000` | 64 KB | read-only, uncached | Product reset image; kseg1 alias `0xBFC0_0000` |
| Boot SRAM | `0x0000_0000` | 64 KB | cacheable | Post-ROM code/data; kseg0 alias `0x8000_0000` |
| Boot SRAM uncached alias | `0xA000_0000` | 64 KB | uncached | Same physical SRAM aperture; used by firmware mailbox/DMA buffers |
| DDR (behavioral placeholder) | `0x0800_0000` | 128 MB | cacheable | Phase C.4 capacity placeholder only, backed by `rtl/perips/axi_ddr_behavioral.v`; product kseg0 alias `0x8800_0000`. No DDR3 timing/refresh/PHY. |
| SPI Flash | `0x1000_0000` | 256 MB | read-mostly | Boot image / XIP candidate |
| APB Bridge | `0x4000_0000` | 64 KB | uncached | Peripheral window |
| Debug / Test | `0xE000_0000` | 64 KB | privileged | Reserved; only decoded when a future product feature gate enables it |

All addresses outside the listed implemented windows are unmapped and must
return AXI `DECERR`.

## APB Submap

| Peripheral | Offset | Notes |
| --- | --- | --- |
| UART | `0x0000` | console / bring-up |
| Timer | `0x1000` | system tick |
| GPIO | `0x2000` | board control |
| DMA | `0x3000` | optional bandwidth path |
| PIC | `0x4000` | interrupt aggregation |
| QSPI/XIP status | `0x5000` | version/status/last-error observability; full command/XIP/FIFO controller not yet integrated |
| DDR controller | `0x6000` | init/calibration/refresh status; product block not yet integrated |
| Watchdog | `0x7000` | APB watchdog control/count/status; reset pulse and always-on boot-status retention are integrated |
| Boot status | `0x8000` | always-on stage/failure/reset-cause registers; RTL/APB retention gate integrated |

### QSPI/XIP Status Registers (`0x4000_5000`)

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x000` | `VERSION` | RO | `0x5153_5001` |
| `0x004` | `STATUS` | RO | bit 0: captured XIP timeout; bit 1: controller present |
| `0x008` | `LAST_ERROR` | RO | `[31:16]` class, `[15:0]` code; `0x0001_0001` is AXI XIP timeout |
| `0x00C` | `CONTROL` | WO | bit 0 W1C clears captured timeout and last error |

## GPIO Register Map

Base: `0x4000_2000`

| Offset | Register | Access | Reset | Notes |
| --- | --- | --- | --- | --- |
| `0x000` | `GPIO_DATA` | RW | `0x0000_0000` | Output data when direction bit is 1, synchronized input when 0 |
| `0x004` | `GPIO_DIR` | RW | `0x0000_0000` | `1` = output, `0` = input |

## Required Follow-Up

The RTL, TB, and firmware must be aligned to this map before deeper
architecture cleanup continues.
