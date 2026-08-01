# Boot and Memory Product Contract

> Version: v0.8 (2026-08-01)
>
> Status: Phase 2 architecture freeze candidate with verified Boot ROM
> reset/map, fetch-response PC alignment, general-exception, TLB refill/invalid
> vector, minimal BEV MMU boot-firmware, EBase/Modified recovery, and SPI XIP
> pin-level slices.
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
| Boot ROM map | `axi_boot_rom` is a distinct 64-KB read-only S4 slave; the crossbar gives its exact range priority over the broad legacy Flash window | Add the immutable ROM image and prove reset through header check; do not treat the zero-filled simulation array as a boot image |
| Exception vector | Product mode resets `BEV=1/ERL=1`; true TLB miss selects `BFC0_0200` or `EBase`, while invalid and ordinary exceptions select `BFC0_0380` or `EBase+0x180`; prototype mode retains literal `0x0000_0180` | A minimal firmware handler is now copied from Boot ROM into SRAM and recovers a precise `Mod`; complete vectored-interrupt and cache-error behavior from `cp0_spec.md` |
| Firmware placement | `tb/soc_test/fw/common/link.ld` keeps the prototype image in useg SRAM; `tests/mmu_product_boot/link.ld` links reset/refill entries at Boot ROM kseg1; `tests/mmu_ebase_modified` copies a relocatable general handler to SRAM `0x180` | Keep the smoke linker for prototype tests; add a full runtime kseg0 linker and a separate Boot ROM/SPL image |
| MMU enable | `SOC_MMU_ENABLE` defaults to `0`; product firmware installs a wired APB mapping, dynamically refills useg DDR, and relocates an EBase handler that changes a valid `D=0` entry to `D=1` before `ERET` retry | Kernel runtime MMU contract, invalid-fault policy, ASID/page-table policy, and vectored/cache-error handling still require product firmware work |
| Main memory | `rtl/soc_memory_subsystem.v` connects `axi_ddr_behavioral` | Replace with DDR controller + PHY wrapper, init/calibration/refresh status and a memory test |
| Flash boot | `rtl/perips/axi_spi_flash.v` is single-lane read/XIP; its pin-level `0x03`/24-bit address, serial burst read and write-reject behavior are unit-tested; `soc_top.v` exposes `spi_mosi/miso` only | Integrate QSPI command/XIP controller and expose four data lanes or a pad-wrapper equivalent |
| WDT/boot status | `apb_wdt` exists but is not instantiated by `soc_peripheral_subsystem.v` | Add product APB decode, reset request path, boot-failure status and timeout test |
| Test preload | `mips_soc` exposes `preload_sram_hex`; current UVM firmware flow uses `FW_HEX` | Keep preload for block/debug tests only; product boot gate must preload the flash image and observe reset fetch |

## 3. Physical and virtual memory map

Physical addresses are the AXI/fabric addresses. Virtual aliases are the
addresses firmware may use after the MIPS segment rules are active.

| Region | Physical base | Size | Product virtual access | State |
|---|---:|---:|---|---|
| Boot ROM | `0x1FC0_0000` | 64 KB | `0xBFC0_0000` kseg1 | Reset/map and general-vector slices `BLOCK_VERIFIED`; immutable image and handoff are P0 |
| Boot SRAM | `0x0000_0000` | 64 KB | `0x8000_0000` kseg0 / `0xA000_0000` kseg1 | Existing behavioral SRAM; post-boot code and mailbox |
| DDR | `0x0800_0000` | 128 MB | `0x8800_0000` kseg0 / `0xA800_0000` kseg1 | Existing address reservation; behavioral placeholder must be replaced |
| SPI/QSPI flash | `0x1000_0000` | 256 MB | `0xB000_0000` kseg1 | Existing AXI XIP window; controller and boot command path incomplete |
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
| QSPI controller | `0x4000_5000` | command, FIFO, XIP and error |
| DDR controller | `0x4000_6000` | init, calibration, refresh, error |
| Watchdog | `0x4000_7000` | unlock, timeout, reset status |
| Boot status | `0x4000_8000` | immutable boot stage/failure code |

These addresses become the definitions `SOC_APB_QSPI_BASE`,
`SOC_APB_DDRCTRL_BASE`, `SOC_APB_WDT_BASE`, and `SOC_APB_BOOT_STATUS_BASE` in
the RTL configuration commit. The current QSPI and DDR draft specs reference
undefined base macros; implementation must not proceed with undefined or
duplicated addresses.

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
sets `D=1`, and retries the store by `ERET`. Vectored-interrupt
(`Cause.IV`/`IntCtl.VS`), cache-error, invalid-fault policy, and a production
runtime handler set remain unimplemented product requirements.

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

The current `soc_top.v` pins are insufficient for this contract:

- replace `spi_mosi/spi_miso` with a QSPI pad wrapper exposing `qspi_io[3:0]`,
  `qspi_sck`, and chip-select(s), while allowing a single-lane compatibility
  mode in simulation;
- add the selected DDR3 PHY/pad interface (address, bank, command, clock,
  reset, DQ/DQS/DM) through a board-specific wrapper;
- add UART TX/RX and flow-control pins, or explicitly bind them to a pad-mux
  interface before product top signoff;
- expose or intentionally isolate boot-status and watchdog reset observability.

## 8. Verification gates (behavioral, not coverage)

Each gate must run from a flash image and must not call `preload_sram_hex`:

| Gate | Pass condition | Minimum negative/reset cases |
|---|---|---|
| `bootrom_reset_test` | First fetch is `BFC0_0000`; ROM reaches header check | reset during fetch; illegal ROM write |
| `qspi_boot_test` | QSPI read/XIP and command path deliver a valid manifest | bad magic, bounds, CRC, timeout, reset during transfer |
| `ddr_init_test` | init/calibration/refresh reaches `init_done`; memory march passes | init timeout, calibration error, AXI backpressure |
| `mmu_product_boot_test` | wired TLB map, kseg aliases, refill and EBase vectors all pass | invalid/modified/refill, BEV transition, ERET |
| `boot_handoff_test` | no SRAM preload; image reaches `HANDOFF` and writes boot mailbox | bad image must not execute payload |
| `wdt_boot_failure_test` | failed boot records code and produces deterministic reset | timeout, reset while status is written |

`PRODUCT_FUNCTION_READY` for boot/memory requires all six gates on the same
integration baseline, plus a real DDR PHY model/board wrapper and firmware
image hash recorded in the report. Generic AXI flash-image or behavioral DDR
tests remain block evidence only.

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
- `tb/unit/flash/tb_axi_spi_flash.sv` drives the production
  `axi_spi_flash` pins rather than `axi_flash_image_model`. It verifies the
  standard-read command/address sequence (`0x03_000000`), two sequential
  serial-read response words and a rejected AXI write (`SLVERR`).
  `make spi-flash-unit-gate` is its standalone entry point.

These tests do not prove manifest parsing, vectored/cache-error vectors,
QSPI/DDR initialization, a complete relocated runtime handler set, or handoff.
The ROM image is a simulation plusarg and is not a production mask-ROM artifact.

## 9. Implementation sequence

1. Add the product map macros and update `docs/address_map.md`; correct stale
   comments without changing the prototype smoke map.
2. Implement Boot ROM slave, reset-PC parameter, ordinary BEV/EBase,
   miss-versus-invalid TLB vector paths, and the minimal BEV product linker,
   wired mapping, dynamic refill and `ERET` retry slice, plus a minimal copied
   EBase general-handler/Modified recovery slice (complete only for the opt-in
   directed slice); implement vectored/cache-error policy and a product
   manifest builder next.
   Keep prototype smoke as a separate configuration until the product gate
   passes.
3. Integrate QSPI controller/pads and add the QSPI command/XIP block tests.
4. Integrate DDR controller/PHY wrapper, APB status, refresh/calibration and
   the DDR init gate. Do not call `axi_ddr_behavioral` a product memory model.
5. Integrate WDT and boot-status registers into the peripheral/reset path.
6. Run the six gates above with no coverage, lint, CDC/RDC, formal,
   synthesis/timing, or PPA work in this phase.

Exit criteria for this contract are a reviewed product map, a reproducible
flash image format, a reset-to-handoff trace, and six passing behavioral gates.
