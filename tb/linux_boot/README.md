# Linux Boot Regression (Phase F)

This directory is the product boot integration boundary. The current tree does
not contain the external toolchain, U-Boot, Linux, QEMU, or a device-specific
flash/DDR endpoint, so the boot regression is dependency-gated. Run
`tb/linux_boot/check_dependencies.sh` before attempting the end-to-end flow; it
reports each missing dependency and exits 2 rather than falling back to a host
compiler or a preload model.

Defaults:

```text
MIPS_CROSS_COMPILE=mips64-linux-gnu-
UBOOT_SOURCE_DIR=third_party/u-boot
LINUX_SOURCE_DIR=third_party/linux
QEMU_SYSTEM_BIN=build/deps/src/qemu-9.2.0/build-mipsel-softmmu/qemu-system-mipsel
QEMU_USER_BIN=build/deps/src/qemu-9.2.0/build-mipsel-linux-user/qemu-mipsel
```

The dependency checker accepts the project-built `qemu-system-mipsel` binary
for the `mips32-soc-ref` custom machine. `qemu-mipsel` remains a separate
linux-user binary; build it from the same official QEMU source with
`scripts/qemu/build_mips32_linux_user.sh`. System-mode QEMU is not substituted
for linux-user execution.

## Reproducible source acquisition

The project does not vendor Linux or U-Boot. `sources.lock` pins official
upstream immutable archive commits, and the following command downloads them
under the ignored `build/` dependency cache and extracts them under
`third_party/`:

```text
make linux-boot-fetch-sources
```

The script refuses to overwrite a directory whose `.source-commit` marker does
not match the lock file. This closes source provenance only; it does not claim
that the custom machine can boot Linux or U-Boot.

## QEMU UHI/DTB contract

The opt-in `make qemu-system-uhi-dtb-gate` target verifies the first Linux
handoff boundary. It passes `-dtb` to the custom machine, which places the
opaque blob in guest RAM and supplies the MIPS UHI arguments (`a0=-2`, kseg0
`a1`). The guest checks the FDT magic and exits through the success mailbox.
This is not a Linux kernel boot test and does not provide a device-specific
DTS, U-Boot loader, or Linux driver model.

## Generic Linux kernel gate

The opt-in `make linux-boot-build-gate` target builds a pinned generic MIPS
32r2 little-endian Linux kernel, a project DTS, and a minimal initramfs, then
boots them on the project-built `mips32-soc-ref` machine. The gate currently
passes the kernel-to-userspace marker: Linux prints its version, registers
`ttyS0`, reaches `/init`, and emits `MIPS32_SOC_LINUX_BOOT_SUCCESS`. It does
not claim a complete product Linux boot because U-Boot, real QSPI/DDR devices,
the full device-driver set, and RTL system-mode Linux differential remain
outside this gate.

The separate opt-in `make linux-uboot-build-gate` target builds the pinned
official U-Boot `maltael_defconfig` with the MIPS32 little-endian cross
toolchain. This is a source/build prerequisite only: Malta is not the
`mips32-soc-ref` machine, so the gate does not claim QSPI loading, DDR init,
SoC-specific U-Boot support, or Linux handoff.

The diagnostic `make linux-uboot-custom-machine-probe` target uses a separate
U-Boot build with `CONFIG_SKIP_LOWLEVEL_INIT` and the opt-in
`malta-u-boot-compat=on` QEMU property. It proves that the custom machine can
load the ELF through its kseg1 flash alias and execute into U-Boot
`board_init_f`. The probe currently stops during board initialization because
the image still contains Malta board code; it is evidence for the porting
boundary, not a custom-machine boot gate.

## Boot flow (target)

```
Reset  →  BootROM       (mask ROM, verifies QSPI header, jumps to SPL)
       →  SPL           (loads U-Boot proper from QSPI to DDR)
       →  U-Boot proper (initializes DDR, GMAC, storage; loads kernel)
       →  Linux kernel  (arch/mips/bcm47xx-like port)
       →  busybox init
       →  shell prompt  (marker for regression success)
```

## Dependencies (from other phases)

| Phase | Blocking dependency |
|---|---|
| Phase B | Full R2 ISA + MMU + precise exceptions |
| Phase C | Multi-outstanding AXI + L2 cache (perf floor) |
| Phase D | Real QSPI XIP, DDR3 controller, UART 16550, GMAC (optional for boot), Timer |
| Phase E | Multi-clock domain, proper reset sequence |

Linux boot cannot be claimed until the dependency gate passes and the four
hardware/software phases above have working implementations. Existing
behavioral Boot ROM, DDR4 controller, and QSPI/XIP gates remain lower-level
evidence, not substitutes for this end-to-end regression.

## Directory layout (planned)

```
tb/linux_boot/
  README.md                      ← this file
  bootrom/
    Makefile
    boot.S                       ← minimal mask-ROM
  uboot/
    (patched U-Boot source ref)
    build.sh
  kernel/
    (kernel source ref, config)
    build.sh
  rootfs/
    busybox.config
    init
  qspi_image_builder.py          ← packs bootrom+uboot+kernel+dtb into QSPI hex
  regress.sh                     ← runs simv, greps for shell prompt
  vcs_boot_top.sv                ← top wrapper for boot regression
```

## Success criteria

- `regress.sh` returns 0 → boot reached shell prompt → REGRESSION_BOOT_SUCCESS
- Time budget: ≤ 6 hours per boot run in simulation (initial target)
- 100 consecutive nightly boots pass → cleared for tape-out sign-off input
