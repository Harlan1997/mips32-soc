# Multi-Channel Scatter-Gather DMA (`apb_axi_dma`) Specification

## 1. Overview

`apb_axi_dma` is a multi-channel Scatter-Gather (SG) Direct Memory Access (DMA) controller. It acts as an APB slave for software configuration and status reporting, and as an AXI master for high-speed data transfers across the SoC fabric.

As of Phase 4C, `apb_axi_dma` is closed under the single-outstanding AXI fabric contract.

## 2. Bus Contract & Architecture

- **APB Slave Interface**: 32-bit width, 12-bit address space (`0x000`–`0x1FF`).
- **AXI Master Interface**: Single-beat word (32-bit) transfers:
  - `AWLEN / ARLEN = 8'd0`
  - `AWSIZE / ARSIZE = 3'b010` (4 bytes)
  - `WSTRB = 4'hF`
  - Single outstanding transaction at a time.
- **Channel Allocation**: 4 channels by default (`N_CHANNELS = 4`).

## 3. Register Map

### 3.1 Legacy v1 Channel 0 Alias (`0x00`–`0x0C`)

Maintained for backward compatibility with legacy firmware and UVM sequences:

| Address | Register | Access | Description |
|---|---|---|---|
| `+0x00` | `SRC` | RW | Source physical address |
| `+0x04` | `DST` | RW | Destination physical address |
| `+0x08` | `LEN` | RW | Length in bytes (4-byte aligned) |
| `+0x0C` | `CTRL` | RW/W1C | Bit 0: `EN` (auto-clears on start/done), Bit 1: `INT_EN`, Bit 2: W1C `DONE`, Bit 4: `ERR` |

Writing `CTRL[0]=1` automatically clears prior `DONE` and `ERR` status for seamless re-arming.

### 3.2 v2 Per-Channel Registers (`0x40 + c * 0x40`)

Each channel $c \in [0, 3]$ occupies a 64-byte window:

| Offset | Register | Access | Description |
|---|---|---|---|
| `+0x00` | `CTRL` | RW / W1C | Bit 0: `EN`, Bit 1: `SG_MODE`, Bit 2: `INT_EN`, Bit 3: W1C `DONE`, Bit 4: W1C `ERR`, Bits [7:5]: RO `ERR_CODE` |
| `+0x04` | `SRC` | RW | Direct mode source address |
| `+0x08` | `DST` | RW | Direct mode destination address |
| `+0x0C` | `LEN` | RW | Direct mode transfer length (bytes) |
| `+0x10` | `DESC_HEAD` | RW | SG mode initial descriptor head address |
| `+0x14` | `STATUS` | RO | Bit 0: `BUSY`, Bit 1: `DONE`, Bit 2: `ERR`, Bits [5:3]: `ERR_CODE` |
| `+0x18` | `CUR_SRC` | RO | In-flight / current source address |
| `+0x1C` | `CUR_DST` | RO | In-flight / current destination address |
| `+0x20` | `CUR_LEN` | RO | In-flight / remaining byte count |
| `+0x24` | `DESC_PTR` | RO | Current descriptor address |

### 3.3 Global Registers

| Address | Register | Access | Description |
|---|---|---|---|
| `0x100` | `GLOBAL_CTRL` | RW | Bit 0: Global DMA Enable (`global_en`) |
| `0x104` | `IRQ_STATUS` | RO | Bits [`N_CHANNELS-1`:0]: Pending interrupt for each channel (`INT_EN & (DONE \| ERR)`) |

## 4. Error Handling Policy & Codes

When an error occurs during transfer initiation, descriptor loading, or data movement:
1. The channel immediately terminates the active transfer.
2. `busy_r` clears (0), `done_r` sets (1), `err_r` sets (1).
3. The specific error code is recorded in `ERR_CODE` (visible in both `CTRL[7:5]` and `STATUS[5:3]`).
4. If `INT_EN = 1`, `ch_int` asserts to trigger a PIC interrupt.

### Error Code Summary:

- `ERR_NONE` (`3'd0`): No error.
- `ERR_ALIGN` (`3'd1`): Direct mode `SRC`, `DST`, or `LEN` is not 4-byte aligned (`[1:0] != 0`). Rejects before emitting any AXI traffic.
- `ERR_AXI_READ` (`3'd2`): Downstream AXI read response (`RRESP`) is not `OKAY`.
- `ERR_AXI_WRITE` (`3'd3`): Downstream AXI write response (`BRESP`) is not `OKAY`.
- `ERR_DESC` (`3'd4`): SG descriptor is malformed (unaligned descriptor address, unaligned `SRC/DST/LEN`, or zero-length with non-zero `NEXT`).
- `ERR_DESC_LIMIT` (`3'd5`): Descriptor chain exceeds `MAX_DESCRIPTORS = 16` (prevents infinite cyclic chains).

## 5. Reprogramming & Safety Rules

- **Busy Protection**: While `BUSY = 1`, writes to `SRC`, `DST`, `LEN`, `DESC_HEAD`, `SG_MODE`, or `EN` are ignored and cannot corrupt the in-flight transfer. `INT_EN` updates take effect dynamically.
- **W1C Re-arm**: Sticky `DONE` and `ERR` bits are cleared by writing 1 to `CTRL[3]` (`DONE_W1C`) or `CTRL[4]` (`ERR_W1C`). Clearing both resets `ERR_CODE` to `ERR_NONE`.

## 6. Phase 4C Scope & Future Work

- **Closed Scope**: Functional contract for direct copy, scatter-gather, error codes, busy protection, status W1C, and IRQ generation.
- **Non-Claims / Exclusions**:
  - No AXI burst or multi-outstanding transaction claims (single-beat current fabric baseline).
  - No IOMMU or hardware cache coherency claims.
  - No formal verification or linting claims in this phase.
  - Coverage exclusion maintenance remains a separate task.
