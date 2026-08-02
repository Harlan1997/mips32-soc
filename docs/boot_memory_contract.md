# Boot and Memory Product Contract

> Version: v1.10 (2026-08-03)
>
> Status: Phase 2 architecture freeze candidate with verified Boot ROM
> reset/map, fetch-response PC alignment, general-exception, TLB refill/invalid
> vector, IP-based vectored interrupt, minimal BEV MMU boot-firmware, EBase/Modified recovery, SPI XIP
> pin-level slices, a bounded AXI XIP timeout/DBE path, and a development
> manifest-to-kseg0-SRAM handoff, an MMU-enabled kseg0 stage-1 instruction
> handoff slice, a bounded kseg0 runtime linker/data-layout slice, an always-on boot-status/WDT retention slice, and a
> no-preload Boot ROM WDT failure/reset gate.
> This document defines the
> minimum boot, address, reset, and memory behavior required before the SoC can
> claim `PRODUCT_FUNCTION_READY`. It does not claim that the RTL implements
> these requirements today.

## 1. Scope and decision

The prototype simulation contract is not a product boot contract. The prototype
configuration starts at `0x0000_0000`, places firmware and exception code in useg SRAM,
uses a behavioral DDR array, and runs a single-lane SPI model. That is useful
for RTL-contract regression but cannot initialize a commercial SoC from reset.

The product configuration defined here is:

1. Reset enters immutable Boot ROM at `BFC0_0000` (MIPS bootstrap vector).
2. Boot ROM executes from uncached kseg1 and loads a signed or development-
   integrity-checked image from QSPI into SRAM/DDR.
3. The CPU uses kseg0/kseg1 direct mapping for the low physical memory windows;
   APB and other high physical windows are mapped by wired TLB entries before
   firmware accesses them with MMU enabled.
4. The first-stage image relocates the exception handler to kseg0 SRAM, sets
   `EBase=8000_0000`, clears `BEV`, and enters the kernel boot path only after
   DDR initialization has reached `init_done`.
5. A reset-to-first-instruction test must run with no `preload_sram_hex` or
   implicit firmware copy. A loadable flash-image model is allowed only for
   controller/block tests, not as product boot evidence.

The exact DDR PHY vendor, board timing file, and secure-boot key provisioning
remain integration inputs. They must be selected before RTL implementation of
the PHY wrapper, but they do not change the address or reset contract below.

## 2. Current blockers and source evidence

| Blocker | Current evidence | Required change |
|---|---|---|
| Reset address | Product configuration passes `BFC0_0000` to `mips_if_stage`; prototype mode retains reset address zero | Keep `SOC_PRODUCT_BOOT_ENABLE` opt-in until the remaining product boot gates pass |
| Boot ROM map | `axi_boot_rom` is a distinct 64-KB read-only S4 slave; the crossbar gives its exact range priority over the broad legacy Flash window. A plusarg-loaded development ROM now validates and copies a flash manifest payload in a full-SoC directed gate | Add a production immutable-ROM artifact and boot-status/boot-failure integration; WDT reset path is integrated but not yet part of the boot-failure gate |
| Exception vector | Product mode resets `BEV=1/ERL=1`; CacheErr uses `BFC0_0100`/`EBase+0x100`, true TLB miss selects `BFC0_0200` or `EBase`, invalid/general selects `BFC0_0380` or `EBase+0x180`, and accepted `Cause.IV=1` interrupts select `EBase+0x200+VN*VS*32`; prototype mode retains literal `0x0000_0180` | CacheErr sideband/CP0 ERL/ErrorEPC and an injected cached-refill handler/ERET recovery slice are RTL-directed verified; ECC, complete runtime policy and external EIC/VEIC dispatch remain separate |
| Firmware placement | `tb/soc_test/fw/common/link.ld` keeps the prototype image in useg SRAM; `tests/mmu_product_boot/link.ld` links reset/refill entries at Boot ROM kseg1; `tests/mmu_ebase_modified` copies a relocatable general handler to SRAM `0x180`; the manifest handoff image is linked at kseg0 VA `0x8000_1000` with physical load address `0x0000_1000`, and its stage-1 issues kseg0 writes/readback at VA `0x8000_7000/0x8000_7004`; the runtime-depth payload extends this to `0x8000_7000..0x8000_704C` plus stack `0x8000_8000`; the runtime-layout payload links `.rodata` at `0x8000_1100`, initialized `.data` at `0x8000_1110`, `.bss` at `0x8000_1120..0x8000_112f`, and a linker-defined stack top at `0x8000_8000` | The MMU-enabled kseg0 instruction, bounded multi-word/stack data path, and one linker/data-layout initialization slice are verified; CPU/D-cache support the six documented D-cache maintenance operations plus a limited TagLo/TagHi/SYNC CPU contract. A complete production runtime ABI/loader, I-cache tag state, parity/ECC, complex ordering semantics and separate production Boot ROM/SPL image remain required |
| MMU enable | `SOC_MMU_ENABLE` defaults to `0`; product firmware installs a wired APB mapping, dynamically refills useg DDR, relocates an EBase handler that changes a valid `D=0` entry to `D=1` before `ERET` retry, and the handoff gate confirms kseg0 `0x8000_1000 -> 0x0000_1000` instruction plus `0x8000_7000 -> 0x0000_7000` data translation; unit and product SoC gates prove software page-table lookup, ASID 1/2 switching, bounded ASID 1..4 round-robin pressure, wired-global retention, `TLBWI` dynamic flush and re-refill | Kernel runtime data mapping, full SoC page-table allocator/multi-process scheduler pressure, shootdown IPI, invalid-fault policy and complete runtime firmware still require product work |
| Main memory | `rtl/soc_memory_subsystem.v` connects `axi_ddr_behavioral`; `docs/block_specs/ddr3_spec.md` v1.0 now freezes the controller/PHY contract and `soc_config.vh` defines `0x4000_6000` | Select PHY/DRAM inputs, implement the AXI/APB/DFI contract, replace S3, then run init/calibration/refresh and memory tests |
| Flash boot | `rtl/perips/axi_spi_flash.v` is the default single-lane read/XIP path; its pin-level `0x03`/24-bit address, serial burst read and write-reject behavior are unit-tested. Production XIP reads are wrapped by a 512-cycle AXI acceptance/response guard that returns `SLVERR`, drains a late response, and reaches the CPU as uncached IBE/DBE or cached CacheErr. The development handoff gate reads its manifest and payload through these physical SPI pins; APB `0x4000_5000` now exposes a version/presence/timeout/last-error observability slice with W1C clear; `qspi_apb_integration` adds a `+0x20` APB command/FIFO window and the vendor-neutral `spi_flash_behavioral` endpoint gate proves x1 read/WREN/page-program exchange; standalone `qspi_axi_xip` proves x1 and optional `ENABLE_QUAD_IO=1` (`0x6B` + x4 data) AXI read-only command bridges against vendor-neutral endpoints; command timeout/abort/reset-in-flight semantics are bounded and WDT-tested; `qspi_soc_pad_mux` is integrated in `mips_soc_impl`, and `soc_top.v` exposes optional `qspi_io[3:0]` with `ENABLE_QSPI_QUAD=1` while preserving legacy x1 pins | The limited SoC slice now has defined APB-command versus AXI-XIP pin ownership, priority, command timeout, abort and reset-in-flight behavior, plus a vendor-neutral four-lane tri-state boundary. Standalone quad AXI/XIP is `BLOCK_VERIFIED (vendor-neutral)` only; remaining work is SoC four-lane XIP/boot integration, real PHY/electrical timing, a licensed/device-specific flash model or board endpoint, and the directed cached-refill handler slice to ECC/complete software-visible fault classes |
| UART pins | `soc_top.v` now exposes UART TX/RX, RTS/CTS, DTR/DSR, DCD and RI; `ENABLE_UART_PINS=0` preserves legacy/UVM tie-offs. The product subsystem routes RX-specific IRQ to PIC bit0 and preserves aggregate UART IRQ on bit1 | Bind the pins through the selected pad-mux/electrical wrapper and add an external RX waveform/board-level gate; pin exposure alone is not pad signoff |
| WDT/boot status | `apb_wdt` is decoded at APB `0x4000_7000`; expiry produces a one-cycle reset request into `mips_soc_impl`; the always-on WDT retains sticky `STATUS.expired`, and `apb_boot_status` at `0x4000_8000` retains stage/failure/cause across that pulse | RTL/unit, AXI/APB retention and no-preload Boot ROM failure gates pass; map manifest/QSPI/DDR fault classes to production failure codes and prove deterministic restart for each |
| Test preload | `mips_soc` exposes `preload_sram_hex`; current UVM firmware flow uses `FW_HEX`. The manifest handoff gate instead supplies only Boot ROM and external SPI flash images | Keep preload for block/debug tests only; product boot gates must not preload SRAM or use an AXI flash-image verification model |

## 3. Physical and virtual memory map

Physical addresses are the AXI/fabric addresses. Virtual aliases are the
addresses firmware may use after the MIPS segment rules are active.

| Region | Physical base | Size | Product virtual access | State |
|---|---:|---:|---|---|
| Boot ROM | `0x1FC0_0000` | 64 KB | `0xBFC0_0000` kseg1 | Reset/map/vector slices and development manifest handoff have directed SoC evidence; immutable production image remains P0 |
| Boot SRAM | `0x0000_0000` | 64 KB | `0x8000_0000` kseg0 / `0xA000_0000` kseg1 | Existing behavioral SRAM; stage-1 entry `0x8000_1000` is fetched through MMU-enabled kseg0 in the handoff slice; full runtime data use remains open |
| DDR | `0x0800_0000` | 128 MB | `0x8800_0000` kseg0 / `0xA800_0000` kseg1 | Address window is frozen; behavioral placeholder must be replaced by the v1.0 controller/PHY contract |
| SPI/QSPI flash | `0x1000_0000` | 256 MB | `0xB000_0000` kseg1 | Default path remains single-lane `axi_spi_flash` XIP with a 512-cycle AXI-side guard; APB command and AXI XIP now share pins through the SoC `qspi_shared_pin_arbiter`, with grant-gated downstream `ARVALID` and fabric `ARREADY`; command `TIMEOUT`, CTRL abort/disable, W1C event clear and WDT/reset-in-flight pin-safe recovery are verified in the APB integration slice; standalone `qspi_axi_xip` x1 and optional quad (`0x6B` x4 data) bridges are block-verified against vendor-neutral models but are not selected by `soc_memory_subsystem`; SoC four-lane XIP, commercial flash and production boot remain incomplete |
| APB peripherals | `0x4000_0000` | 64 KB | `0xC000_0000` kseg2 via wired TLB | Existing APB window; no direct kseg1 alias because PA is above 512 MB |
| Debug/test | `0xE000_0000` | 64 KB | kseg2 via TLB, privileged only | Existing reserved window; not part of boot image |

Rules:

- Boot ROM must be added as a distinct AXI slave. It must not alias writable
  SRAM, and all writes must return `SLVERR` or `DECERR` according to the final
  AXI policy.
- The DDR window remains exactly `0x0800_0000..0x0FFF_FFFF`; the existing
  `mips_soc_impl.v` comment that extends it to `0x17FF_FFFF` is stale and must
  not be used as a decode requirement.
- The existing SRAM alias `0xA000_0000` maps to physical SRAM through kseg1
  translation when MMU is enabled. A second ad-hoc alias is not allowed.
- Any access outside these windows completes with AXI `DECERR`; an access to a
  valid window while its controller is unavailable completes with `SLVERR` and
  a diagnostic status bit.

## 4. APB product submap

The existing offsets remain stable. New product blocks use previously unused
4-KB slots in the existing 64-KB APB aperture:

| Block | APB address | Required status |
|---|---:|---|
| UART | `0x4000_0000` | TX/RX, FIFO, RX IRQ, pin status |
| Timer | `0x4000_1000` | timer interrupt |
| GPIO | `0x4000_2000` | pin direction/data |
| DMA | `0x4000_3000` | copy, IRQ and error |
| PIC/VIC | `0x4000_4000` | source mask/active/priority |
| QSPI/XIP status slice | `0x4000_5000` | version, controller-present, guarded-XIP timeout/last-error and W1C; command/FIFO APB window is integrated for x1 and the SoC four-lane APB command read/write gate passes with timeout/abort/W1C event bits; WDT/reset-in-flight pin-safe recovery is verified; `qspi_soc_pad_mux` and optional `qspi_io[3:0]` are present; standalone quad AXI/XIP is block-verified, while SoC four-lane AXI XIP and PHY selection remain future work |
| DDR controller | `0x4000_6000` | init, calibration, refresh, error |
| Watchdog | `0x4000_7000` | unlock, timeout, reset status |
| Boot status | `0x4000_8000` | always-on diagnostic stage/failure/reset-cause registers |

These addresses are now defined as `SOC_APB_QSPI_BASE`,
`SOC_APB_DDRCTRL_BASE`, `SOC_APB_WDT_BASE`, and `SOC_APB_BOOT_STATUS_BASE` in
`rtl/include/soc_config.vh`. The DDR register offsets and error ABI are frozen
in `docs/block_specs/ddr3_spec.md`; implementation must not introduce an
alternate base, undefined macro, or silently wrap an address outside the DDR
window.

The command window begins at `0x4000_5020` (`0x20 + command offset`). Its
front-end status contract is: `STATUS[0:6] = busy, tx_full, rx_empty, done,
error, timeout, aborted`; `IRQ_STATUS[0:2]` are W1C for done/timeout/aborted;
`TIMEOUT` at `0x4000_5038` is a reference-clock budget, and CTRL[2] at
`0x4000_5020` is a write-one abort. Clearing CTRL.enable also aborts an active
command. An external or watchdog reset drops the in-flight command and drives
the shared pin boundary to `SCLK=0`, `CS_N=1`, `MOSI=0`.

The implemented boot-status register contract is:

| Offset | Register | Access/reset behavior |
|---:|---|---|
| `0x00` | `BOOT_STAGE` | RW, low byte is the current boot stage; POR reset `0x00`; retained across WDT reset |
| `0x04` | `FAILURE` | RW sticky code; a non-zero write records a code and a zero write clears it; POR reset `0x0000_0000`; retained across WDT reset |
| `0x08` | `RESET_CAUSE` | sticky `[0] POR`, `[1] WDT`; POR initializes bit 0, a WDT pulse sets bit 1; writing 1 clears the selected bits |

The block is software-writable by design so Boot ROM can record each state and
failure before requesting reset. It is not a security authenticity register;
signature/key policy remains a separate production requirement.

## 5. Reset and exception contract

### 5.1 Reset entry

After reset deassertion:

| Item | Required value |
|---|---|
| PC | `0xBFC0_0000` |
| Status.BEV | `1` |
| Status.ERL | `1` |
| EBase | `0x8000_0000` |
| MMU execution mode | kseg1 Boot ROM fetches; no useg fetch is permitted |
| Interrupts | disabled until Boot ROM explicitly enables them |

The Boot ROM reset image must fit in the 64-KB region and must have no data
dependency on DDR or APB before it installs the APB TLB mappings.

### 5.2 Vector selection

The CPU must implement the vector table already specified by
`docs/block_specs/cp0_spec.md`:

| Cause | BEV=1 | BEV=0 |
|---|---:|---:|
| TLB refill | `0xBFC0_0200` | `EBase + 0x000` |
| General exception | `0xBFC0_0380` | `EBase + 0x180` |
| Vectored interrupt | bootstrap policy defined by CP0 spec | `EBase + 0x200 + VN*VS*32` |
| Reset/NMI | `0xBFC0_0000` | not applicable |

The current literal `0x0000_0180` path is retained only for the prototype
smoke configuration and must not be used to sign product boot.

The implemented product slice distinguishes a TLB lookup miss from a matching
invalid entry with a pipeline sideband; it does not infer refill from
`ExcCode=TLBL/TLBS`, because both causes share that code. Directed full-SoC
tests cover I-side miss/invalid for both BEV settings and D-side miss/invalid
for `BEV=1`. `tb_product_mmu_ebase_modified.sv` additionally proves a Boot ROM
image copies its EBase general handler to SRAM, clears `BEV/ERL`, takes a
precise `Mod` on a valid `D=0` useg mapping, checks `Cause`/`BadVAddr`/`EPC`,
sets `D=1`, and retries the store by `ERET`. The IP-based vectored-interrupt
slice (`Cause.IV`/`IntCtl.VS`) is now implemented and has a product directed
gate; CacheErr hardware routing and the cached-refill recovery slice are
implemented and directed-tested, while ECC escalation, invalid-fault policy and
the complete runtime handler set remain product requirements.

### 5.3 MMU and early mappings

The product build must use the real translation path. Boot ROM installs at
least these wired mappings before touching APB or entering the first-stage
kernel:

- kseg0/kseg1 direct-map accesses for Boot SRAM, DDR, and QSPI/Boot ROM;
- four 16-KB-equivalent APB mappings covering virtual `0xC000_0000` to
  physical `0x4000_0000` (or an equivalent page-size arrangement supported by
  the TLB implementation);
- a privileged mapping for the boot-status/debug window only if diagnostics
  require it.

The firmware linker must place the post-ROM image at virtual `0x8000_0000`,
with the physical load address in Boot SRAM or DDR explicitly recorded in the
image manifest. No product image may link executable code at useg address zero.
The current development handoff has a narrower executable proof: stage 1 is
loaded at physical `0x0000_1000`, entered at kseg0 VA `0x8000_1000`, and with
`SOC_MMU_ENABLE=1` the observed instruction request translates to PA
`0x0000_1000`. The runtime-depth and runtime-layout gates additionally prove
bounded kseg0 data translation, linker-defined `.rodata/.data/.bss` accesses,
explicit `.bss` clearing, and stack-top-derived readback. These remain finite
freestanding slices; they do not prove a complete runtime ABI, heap/stack
allocator, cache maintenance, page-table setup, or context switching.

## 6. Boot image and state machine

### 6.1 Image contract

The QSPI image starts with a fixed 64-byte manifest. The exact signature
algorithm is a security-program decision, but the fields and failure behavior
are fixed now:

| Offset | Field | Requirement |
|---:|---|---|
| `0x00` | Magic | `SOC1` (`0x534F4331`) |
| `0x04` | Format/version | Reject unsupported versions |
| `0x08` | Header length | Must be at least 64 bytes and aligned |
| `0x0C` | Payload offset | Within the QSPI image |
| `0x10` | Payload length | Non-zero and bounded by target memory |
| `0x14` | Load physical address | SRAM or DDR range only |
| `0x18` | Entry virtual address | kseg0/kseg1 address in the loaded image |
| `0x1C` | Flags | Development-integrity vs production-signed policy |
| `0x20` | CRC32 | Required for development and simulation images |
| `0x24..0x3F` | Digest/signature descriptor | Reserved now; production signing must fill it |

Development images must fail closed on bad magic, bounds, CRC, or controller
error. A production image additionally fails closed if signature verification
or key-policy validation is unavailable. The boot-status register must retain a
stage and failure code across watchdog reset.

The implemented development format is the fixed `SOC1` version-1 layout above:
64-byte header, 64-byte payload offset, Boot SRAM physical load address
`0x0000_1000`, kseg0 entry `0x8000_1000`, development-CRC flag, and CRC32/IEEE
over a word-padded payload. Its directed negative evidence independently
rejects bad magic, version, header length, payload offset, zero/unaligned/
out-of-bounds payload length, load address, entry address, flags, and CRC.
Controller-error and timeout injections remain required before this image
contract can be closed.

### 6.2 Required state sequence

```text
RESET
  -> BOOTROM_FETCH
  -> QSPI_PROBE
  -> IMAGE_HEADER_CHECK
  -> DDR_INIT_WAIT
  -> IMAGE_COPY_AND_CRC
  -> TLB_EARLY_MAP
  -> VECTOR_RELOCATE
  -> HANDOFF
```

The current development handoff implements the subset
`RESET -> BOOTROM_FETCH -> IMAGE_HEADER_CHECK -> IMAGE_COPY_AND_CRC -> HANDOFF`.
Its MMU-enabled handoff check additionally observes stage-1 instruction fetch
at VA `0x8000_1000` reaching physical SRAM `0x0000_1000`.
It deliberately does not claim DDR wait, early APB mapping, vector relocation,
or production boot-status persistence.

Every state has a bounded timeout. Any failure records a code, disables normal
interrupts, and requests a watchdog reset or enters a deterministic diagnostic
loop. A silent CPU stall is not an acceptable failure behavior.

Handoff requirements:

- `EBase=0x8000_0000`, handler installed at `EBase+0x180`;
- `BEV=0`, `ERL=0`, and interrupts remain disabled until the kernel programs
  its own mask and stack;
- stack, `.bss`, and image entry are in the declared loaded memory range;
- DDR `init_done` and calibration status have been checked;
- a boot-status transition records `HANDOFF` before jumping to the image entry.

## 7. Product top-level I/O requirements

The current `soc_top.v` pins are still not sufficient for full board signoff:

- `soc_top.v` now exposes `qspi_io[3:0]` behind `ENABLE_QSPI_QUAD`, with
  `qspi_soc_pad_mux` preserving `spi_mosi/spi_miso` single-lane compatibility;
  the standalone `qspi_axi_xip` quad contract is verified only against a
  vendor-neutral behavioral endpoint. Connect the SoC quad AXI/XIP source,
  replace this boundary with the selected QSPI PHY/pad ring, and validate
  qspi_sck/chip-select timing for the board;
- add the selected DDR3 PHY/pad interface (address, bank, command, clock,
  reset, DQ/DQS/DM) through a board-specific wrapper;
- `soc_top.v` now exposes UART TX/RX and modem flow-control pins. Bind them to
  the selected pad-mux/electrical interface and verify an external RX waveform
  before product top signoff;
- expose or intentionally isolate boot-status and watchdog reset observability;
  the APB boot-status block is now software-readable at `0x4000_8000`, while
  the watchdog reset pulse remains an internal reset-aggregation signal.

## 8. Verification gates (behavioral, not coverage)

Each gate must run from a flash image and must not call `preload_sram_hex`:

| Gate | Pass condition | Minimum negative/reset cases |
|---|---|---|
| `bootrom_reset_test` | First fetch is `BFC0_0000`; ROM reaches header check | reset during fetch; illegal ROM write |
| `qspi_boot_test` | QSPI read/XIP and command path deliver a valid manifest | bad magic, bounds, CRC, timeout, reset during transfer |
| `ddr_init_test` | init/calibration/refresh reaches `init_done`; memory march passes | init timeout, calibration error, AXI backpressure |
| `mmu_product_boot_test` | wired TLB map, kseg aliases, refill and EBase vectors all pass | invalid/modified/refill, BEV transition, ERET |
| `boot_handoff_test` | no SRAM preload; image reaches `HANDOFF` and writes boot mailbox | bad image must not execute payload |
| `wdt_boot_failure_test` | failed boot records stage/code, produces deterministic reset, and reads both after reboot | timeout, reset while status is written, POR/WDT cause clear |

`PRODUCT_FUNCTION_READY` for boot/memory requires all six gates on the same
integration baseline, plus a real DDR PHY model/board wrapper and firmware
image hash recorded in the report. Generic AXI flash-image or behavioral DDR
tests remain block evidence only. The current `wdt-boot-failure-gate` is a
separate preloaded firmware reset-retention smoke; it is not evidence for the
no-preload `wdt_boot_failure_test`. The separate
`product-wdt-boot-failure-gate` now provides that no-preload Boot ROM reset /
retention evidence, but deliberately does not inject a manifest/QSPI/DDR
failure.

### 8.1 Current executable evidence

The following evidence closes only the reset-address, fetch-response PC
alignment, fabric-routing, and ordinary/refill/invalid-vector sub-items of
`bootrom_reset_test`; it does not
close that gate:

- `tb/unit/bootrom/tb_axi_boot_rom.v` verifies a four-word read burst,
  out-of-range `DECERR`, unsupported-size `DECERR`, and write `SLVERR`.
- `tb/unit/bootrom/tb_product_reset_fetch.sv` builds the complete SoC with
  `SOC_PRODUCT_BOOT_ENABLE=1`, does not preload SRAM, verifies PC
  `0xBFC0_0000`, and verifies the first I-cache AR transaction is accepted by
  S4 at physical address `0x1FC0_0000`.
- `tb/unit/bootrom/run_product_wdt_boot_failure.sh` runs the Boot ROM with no
  SRAM preload, installs the early APB TLB map, records stage/failure, arms the
  WDT, and verifies the second reset entry reads `POR|WDT` and retained fields.
- `tb/unit/bootrom/tb_fetch_pc_alignment.sv` runs the same reset program in
  prototype and `SOC_PRODUCT_BOOT_ENABLE=1` configurations. It proves the
  reset `addiu`, its dependent `bne`, and the branch delay slot reach ID with
  their exact PCs, observes the expected writes in WB, and verifies that the
  branch reaches `reset+0x10`. The test
  rejects the prior `inst_addr=pc` implementation, which shifts the I-cache
  response PC by one word.
- `tb/unit/bootrom/tb_product_boot_vector.sv` loads a simulation ROM image,
  raises a `syscall` at reset, verifies the `BFC0_0380` S4 fetch, clears
  `BEV/ERL` in the bootstrap vector, then verifies the `EBase+0x180` virtual
  PC (`0x8000_0180`) maps to an S0 fetch at physical `0x0000_0180`.
- `tb/unit/bootrom/tb_product_tlb_vectors.sv` compiles with
  `SOC_PRODUCT_BOOT_ENABLE=1` and `SOC_MMU_ENABLE=1`; it proves I-TLB miss
  (`hit=0`) takes `BFC0_0200` then `EBase`, while matching invalid
  (`hit=1,V=0`) takes `BFC0_0380` then `EBase+0x180`.
- `tb/unit/bootrom/tb_product_tlb_data_vectors.sv` proves the same miss versus
  invalid separation for a MEM-side useg load under `BEV=1`.
- `tb/unit/bootrom/tb_product_mmu_boot.sv` builds a complete product-mode SoC
  with `SOC_PRODUCT_BOOT_ENABLE=1` and `SOC_MMU_ENABLE=1`, loading a Boot ROM
  image linked at `BFC0_0000`. Its firmware clears `ERL` while retaining `BEV`,
  writes TLB index 0 as a wired kseg2-to-APB entry, takes a DTLB refill at
  `BFC0_0200`, restores the interrupted registers before `ERET`, installs a
  dynamic useg DDR mapping with `TLBWR`, completes a DDR store/load retry,
  performs the kseg2 APB write, and writes the standard SRAM completion
  mailbox. `make product-mmu-boot-gate` is its standalone entry point.
- `tb/unit/bootrom/tb_product_mmu_ebase_modified.sv` builds a separate
  product-mode SoC image with no SRAM preload. Boot ROM copies a local handler
  to physical SRAM `0x180`; after `BEV/ERL` clear, a valid `D=0` useg mapping
  raises `Mod` at `0x8000_0180`. The handler checks precise CP0
  `Cause`/`BadVAddr`/`EPC`, rewrites the same entry dirty, returns with `ERET`,
  and firmware verifies the retried store/load.
  `make product-mmu-ebase-modified-gate` is its standalone entry point.
- `tb/unit/bootrom/tb_product_vectored_interrupt.sv` builds a product-mode
  image with no SRAM preload, writes
  `Cause.IV=1`, `IntCtl.VS=1`, and software `IP1`, then clears `BEV/ERL` and
  enables `IE|IM1`. It proves the CPU enters `0x8000_0220` (`EBase+0x220`),
  the fetch is translated to physical `0x0000_0220`, and CP0 records
  `EXL=1`, `ExcCode=INT`, `IV=1`. `make product-vectored-interrupt-gate` is
  its standalone entry point.
- `tb/unit/wdt/tb_wdt.v` checks WDT reset defaults, arm/countdown, one-cycle
  expiry pulse, sticky status/W1C and valid kick behavior. `make wdt-unit-gate`
  is its standalone entry point.
- `tb/unit/wdt/tb_wdt_peripheral.sv` drives the peripheral subsystem through
  AXI/APB at `0x4000_7000`, verifies the decode, observes the aggregate reset
  pulse and reads sticky status after reset. `make wdt-peripheral-gate` is its
  integration entry point.
- `tb/unit/flash/tb_axi_spi_flash.sv` drives the production
  `axi_spi_flash` pins rather than `axi_flash_image_model`. It verifies the
  standard-read command/address sequence (`0x03_000000`), two sequential
  serial-read response words and a rejected AXI write (`SLVERR`).
  `make spi-flash-unit-gate` is its standalone entry point.
- `tb/unit/flash/tb_qspi_axi_xip.sv` drives the standalone
  `qspi_axi_xip` bridge through a vendor-neutral `spi_flash_behavioral`
  endpoint. It checks a single read, a two-beat burst, AXI ID/RLAST/RRESP,
  APB command sequencing, and the read-only AXI write rejection. The bridge
  is not wired into `soc_memory_subsystem`; `make qspi-axi-xip-gate` is its
  standalone entry point.
- `tb/unit/flash/tb_qspi_shared_pin_arbiter.sv` drives the standalone
  `qspi_shared_pin_arbiter` contract. It verifies latched ownership, no
  preemption of an active memory/command transaction, command priority while
  idle, conflict indication and safe idle pins. `mips_soc_impl` now uses the
  same contract for the existing single-lane `axi_spi_flash` and APB command
  path; `make qspi-shared-pin-arbiter-gate` remains the standalone contract
  entry point and `make soc-smoke` covers the limited SoC integration.
- `tb/unit/flash/tb_qspi_cmd_behavioral.sv` additionally drives the command
  timeout budget, CTRL abort/disable, timeout/abort W1C and external reset while
  CS is asserted. `tb_qspi_status_integration.sv` repeats timeout through the
  AXI/APB bridge and arms the always-on WDT during an active command; the gate
  checks command cancellation, `CS_N=1/SCLK=0` and sticky WDT expiry.
- `rtl/axi/axi_read_timeout_guard.v` wraps only the production
  `axi_spi_flash` read path. With `SPI_READ_TIMEOUT_CYCLES=512` by default,
  it bounds waiting for downstream `ARREADY` and each next downstream
  `RVALID`, returns deterministic AXI `SLVERR` upstream on expiry, and drains
  any late downstream transaction before accepting another request. It does
  not time out legal R-channel backpressure once downstream `RVALID` is high.
- `tb/unit/flash/tb_axi_read_timeout_guard.sv` proves no-`ARREADY` and
  no-`RVALID` cases, late-response drain, recovery by a following good read,
  and the sticky timeout indication. `make xip-read-timeout-unit-gate` is its
  standalone entry point.
- `tb/unit/bootrom/tb_product_manifest_xip_timeout.sv` sets the real guard to
  four cycles without forcing controller internals or changing MISO. It proves
  that an in-flight production XIP read becomes CPU DBE (`Cause.ExcCode=7`)
  and that the Boot ROM general handler records `DEAD_B007` instead of handing
  off to stage 1. This test runs as part of
  `make product-manifest-handoff-gate` and the block aggregate.
- `tb/soc_test/fw/tests/boot_manifest_handoff` builds a Boot ROM image, a
  fixed development manifest, and a kseg0 stage-1 payload. Its full-SoC
  directed test uses only `+BOOT_ROM_HEX` and `+SPI_FLASH_HEX`: it neither
  preloads SRAM nor instantiates `axi_flash_image_model`. The valid image must
  issue standard-read `0x03` traffic for both header and payload, copy to
  kseg1 Boot SRAM, record `HAND`, clear `BEV/ERL`, fetch stage 1 at
  `0x8000_1000`, and write its success mailbox. Eleven independently corrupted
  header/CRC images must each write the failure mailbox and never reach
  handoff or stage 1.
  `make product-manifest-handoff-gate` is its standalone entry point.
- `make product-kseg0-runtime-gate` reruns the same no-preload manifest image
  with `SOC_MMU_ENABLE=1`, `+EXPECT_KSEG0_RUNTIME` and `+EXPECT_KSEG0_DATA`.
  The test requires stage-1 requests at VA `0x8000_1000` and `0x8000_7000` to
  carry physical addresses `0x0000_1000` and `0x0000_7000`, then repeats the
  negative manifest and XIP-timeout cases. This is a directed kseg0
  instruction/single-data handoff slice, not a claim that the complete runtime
  address space or page-table manager is implemented.
- `make product-kseg0-runtime-depth-gate` uses a separate payload to observe 20
  contiguous kseg0 data words across three cache lines and a stack readback.
- `make product-kseg0-runtime-layout-gate` uses `stage1_layout.ld/.s` and a
  separate manifest image to observe `.rodata`/`.data` reads, explicit clearing
  of four `.bss` words, `.bss` read-before/read-after behavior, and the linker
  stack-top-derived access `0x8000_7ff0 -> 0x0000_7ff0`. Its payload is 288
  bytes and is checked against the 32 KiB stage-1 limit. This is a bounded
  freestanding layout contract, not a production kernel linker/loader.
- The handoff uncovered and fixed two integration defects: SPI command/read
  phase transitions could shift a CPU-originated XIP command to `0x06`, and
  D-cache could lose the MMU C=2 uncached attribute after kseg1 translation.
  `axi_spi_flash` now has explicit serial start phases, while `mips_cpu`,
  `mips_core`, and `dcache` carry the uncached attribute with the buffered
  request. The D-cache unit regression and the full handoff gate exercise the
  corrected paths.
- The rejection matrix also exposed a testbench false-pass risk: its former
  128-character SPI-image plusarg buffer truncated aggregate-run paths, after
  which the all-`FF` array initializer looked like a rejected image. The SPI
  and Boot ROM image buffers now hold 512 characters, and the fixture rejects
  an unloaded external-flash image before simulation starts.

These tests prove this fixed development manifest, header rejection, CRC,
handoff, the MMU-enabled kseg0 instruction/single-data handoff slice, bounded
runtime-depth and linker/data-layout slices, the
bounded AXI-side XIP stall-to-DBE path and the APB QSPI timeout status slice
only. A standard SPI
`0x03` read has no ready/error signal: a silent or static MISO line still
produces serial data, so this RTL cannot honestly detect a raw flash-device
"timeout." The guard protects a wedged AXI/controller response path, not a
non-responsive physical flash. The APB status block reports guarded AXI
timeouts, not raw SPI silence. These tests do not prove signature/key policy,
ECC/complete CacheErr policy, external EIC/VEIC dispatch, QSPI/DDR
initialization, a complete relocated runtime handler set, or boot-status/WDT
failure handling.
The ROM image is a simulation plusarg and is not a production mask-ROM
artifact.

## 9. Implementation sequence

1. Add the product map macros and update `docs/address_map.md`; correct stale
   comments without changing the prototype smoke map.
2. Implement Boot ROM slave, reset-PC parameter, ordinary BEV/EBase,
   miss-versus-invalid TLB vector paths, and the minimal BEV product linker,
   wired mapping, dynamic refill and `ERET` retry slice, plus a minimal copied
   EBase general-handler/Modified recovery slice (complete only for the opt-in
   directed slice), plus the IP-based vectored interrupt table, development
   manifest/CRC-to-SRAM handoff and its header rejection matrix. The bounded
   AXI-side controller-stall/timeout path, the CPU CacheErr hardware contract,
   and an injected cached-refill handler/recovery gate are implemented; ECC,
   complete cache-error policy and external EIC/VEIC policy are next.
   Keep prototype smoke as a separate configuration until the product gate
   passes.
3. Keep the standalone QSPI command/XIP bridge block-verified, while the
   existing single-lane `axi_spi_flash` and APB command path use the
   `qspi_shared_pin_arbiter` SoC slice. The grant-gated AR acceptance and
   response-accounting fix are verified by SoC smoke; command timeout,
   abort and reset-in-flight behavior are now defined and covered by block/
   AXI-APB/WDT gates. The vendor-neutral `qspi_soc_pad_mux` and optional
   `qspi_io[3:0]` boundary are now integrated and gated; standalone quad
   AXI/XIP behavior is separately verified with the `0x6B` contract; next add
   the SoC four-lane AXI/XIP connection, real PHY and production boot gates.
4. Select the PHY/DRAM/timing inputs required by `docs/block_specs/ddr3_spec.md`
   v1.0, then integrate the DDR controller/PHY wrapper, APB status, refresh/
   calibration and the DDR init gate. Do not call `axi_ddr_behavioral` a product
   memory model; the S3 replacement is blocked until the contract entry criteria
   and real memory model are available.
5. Add boot-failure firmware around the integrated WDT/reset path. The
   always-on boot-status registers, retention gate, and no-preload Boot ROM
   deliberate-failure gate are implemented; connect manifest/QSPI/DDR failure
   causes to the same codes and verify deterministic restart/cause handling.
6. Run the six gates above with no coverage, lint, CDC/RDC, formal,
   synthesis/timing, or PPA work in this phase.

Exit criteria for this contract are a reviewed product map, a reproducible
flash image format, a reset-to-handoff trace, and six passing behavioral gates.
